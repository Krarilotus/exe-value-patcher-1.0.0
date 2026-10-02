--[[
  exe-value-patcher

  Writes plain values into the game's code at addresses listed in a YAML config file, the
  way an exe patcher would, but in memory at startup so the exe on disk stays untouched.

  The config has one list per game version ("extreme" and "vanilla"); only the list for the
  running exe is applied. See values.yml for the entry format.

  UCP runs module code from the exe's entry point, before the game's static constructors,
  so values those constructors use (such as the texture buffer size) still take effect.
]]

local MODULE_NAME = "exe-value-patcher"
local DEFAULT_CONFIG_PATH = "ucp/modules/exe-value-patcher-*/values.yml"

local IMAGE_BASE = 0x400000
local FIRST_SECTION_ADDRESS = 0x401000
local PE_HEADER_POINTER_OFFSET = 0x3C
local SIZE_OF_IMAGE_OFFSET = 0x50

-- Number of distinct values per supported size, i.e. where the unsigned range ends.
local VALUE_LIMITS = {
  [1] = 0x100,
  [2] = 0x10000,
  [4] = 0x100000000,
}

---Turn a config number into an integer. yaml gives plain integers for most values, a float
---for anything past 2^31 (Balanceprog's unsigned 4-byte form) and a string when it could not
---read the number itself, e.g. a quoted "0x..." value.
---@param raw any
---@return number|nil
local function toInteger(raw)
  if type(raw) == "number" then
    return math.tointeger(raw)
  end
  if type(raw) ~= "string" then
    return nil
  end

  local text = raw:gsub("%s", "")
  local sign = 1
  local first = text:sub(1, 1)
  if first == "-" or first == "+" then
    if first == "-" then
      sign = -1
    end
    text = text:sub(2)
  end

  local number
  if text:sub(1, 2):lower() == "0x" then
    number = tonumber(text:sub(3), 16)
  else
    number = tonumber(text, 10)
  end
  number = number and math.tointeger(number)
  if number == nil then
    return nil
  end
  return sign * number
end

---Map a signed or unsigned value onto the bit pattern of a `size`-byte field.
---@return number|nil the unsigned pattern, or nil if the value does not fit in `size` bytes
local function toPattern(value, size)
  local limit = VALUE_LIMITS[size]
  if value < -(limit // 2) or value >= limit then
    return nil
  end
  if value < 0 then
    return value + limit
  end
  return value
end

---The signed reading of a `size`-byte pattern, for log messages.
local function toSigned(pattern, size)
  local limit = VALUE_LIMITS[size]
  if pattern >= limit // 2 then
    return pattern - limit
  end
  return pattern
end

local function readPattern(address, size)
  local pattern = 0
  for offset = size - 1, 0, -1 do
    pattern = (pattern << 8) | (core.readByte(address + offset) & 0xFF)
  end
  return pattern
end

local function patternToBytes(pattern, size)
  local bytes = {}
  for offset = 0, size - 1 do
    bytes[offset + 1] = (pattern >> (8 * offset)) & 0xFF
  end
  return bytes
end

---End of the loaded exe image, taken from its own PE header.
local function getImageEnd()
  local peHeader = IMAGE_BASE + core.readInteger(IMAGE_BASE + PE_HEADER_POINTER_OFFSET)
  return IMAGE_BASE + core.readInteger(peHeader + SIZE_OF_IMAGE_OFFSET)
end

---Validate one config entry and write it.
---@param entry table
---@param index number position in the list, for log messages
---@param imageEnd number first address past the exe image
---@param skipMismatched boolean skip entries whose default does not match the exe
---@return boolean true if the value was written
local function applyEntry(entry, index, imageEnd, skipMismatched)
  if type(entry) ~= "table" then
    log(WARNING, string.format("[%s] entry %d is not a map; skipped.", MODULE_NAME, index))
    return false
  end

  local label = string.format("[%s] entry %d (%s)", MODULE_NAME, index, tostring(entry.name))

  local size = toInteger(entry.size)
  if size == nil or VALUE_LIMITS[size] == nil then
    log(WARNING, string.format("%s: size must be 1, 2 or 4, got %s; skipped.", label, tostring(entry.size)))
    return false
  end

  local address = toInteger(entry.address)
  if address == nil then
    log(WARNING, string.format("%s: address %s is not a number; skipped.", label, tostring(entry.address)))
    return false
  end
  if address < IMAGE_BASE then
    -- A file offset, as Balanceprog writes them. Every section of both exes sits at
    -- file offset + 0x400000 in memory.
    address = address + IMAGE_BASE
  end
  if address < FIRST_SECTION_ADDRESS or address + size > imageEnd then
    log(WARNING, string.format("%s: address 0x%X is outside the game's exe; skipped.", label, address))
    return false
  end

  local value = toInteger(entry.value)
  local pattern = value ~= nil and toPattern(value, size) or nil
  if pattern == nil then
    log(WARNING, string.format("%s: value %s does not fit in %d byte(s); skipped.", label, tostring(entry.value), size))
    return false
  end

  local current = readPattern(address, size)

  if entry.default ~= nil and current ~= pattern then
    local default = toInteger(entry.default)
    local defaultPattern = default ~= nil and toPattern(default, size) or nil
    if defaultPattern == nil then
      log(WARNING, string.format("%s: default %s does not fit in %d byte(s); not checked.", label, tostring(entry.default), size))
    elseif current ~= defaultPattern then
      log(WARNING, string.format(
        "%s: expected the default %d at 0x%X but found %d. The address may be wrong for this game version, or the exe or another module already changed it.%s",
        label, default, address, toSigned(current, size), skipMismatched and " Skipped." or " Writing anyway."))
      if skipMismatched then
        return false
      end
    end
  end

  core.writeCodeBytes(address, patternToBytes(pattern, size))
  log(DEBUG, string.format("%s: 0x%X = %d (was %d)", label, address, value, toSigned(current, size)))
  return true
end

---Read and parse the config file.
---@return table|nil settings, string|nil error
local function loadConfig(path)
  local opened, handle, openError = pcall(io.open, path, "rb")
  if not opened or handle == nil then
    return nil, string.format("cannot open '%s': %s", path, tostring(opened and openError or handle))
  end

  local content = handle:read("*all")
  handle:close()

  local parsed, settings = pcall(yaml.parse, content)
  if not parsed then
    return nil, string.format("'%s' is not valid YAML: %s", path, tostring(settings))
  end
  if type(settings) ~= "table" then
    return nil, string.format("'%s' does not contain a map", path)
  end
  return settings
end

local namespace = {}

namespace.enable = function(self, config)
  local path = (config or {}).config_file
  if type(path) ~= "string" or path == "" then
    path = DEFAULT_CONFIG_PATH
  end

  -- Old built-in paths referred to the value payload, not UCP's config.yml.
  -- Keep external/custom file selections untouched.
  if path:match("^ucp/modules/exe%-value%-patcher[^/]*/config%.yml$") then
    path = path:gsub("/config%.yml$", "/values.yml")
  end
  local settings, loadError = loadConfig(path)
  if settings == nil then
    log(ERROR, string.format("[%s] %s. Nothing was changed.", MODULE_NAME, loadError))
    return
  end

  local versionKey = data.version.isExtreme() and "extreme" or "vanilla"
  local entries = settings[versionKey]
  if type(entries) ~= "table" then
    log(WARNING, string.format("[%s] '%s' has no '%s' list; nothing was changed.", MODULE_NAME, path, versionKey))
    return
  end

  local imageEnd = getImageEnd()
  local skipMismatched = settings.skip_mismatched == true
  local written = 0
  for index, entry in ipairs(entries) do
    if applyEntry(entry, index, imageEnd, skipMismatched) then
      written = written + 1
    end
  end

  log(INFO, string.format("[%s] wrote %d of %d '%s' values from '%s'.", MODULE_NAME, written, #entries, versionKey, path))
end

namespace.disable = function(self, config)
end

return namespace
