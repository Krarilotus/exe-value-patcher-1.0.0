# Exe Value Patcher

Changes values inside the game (unit stance ranges, castle build range, building denial
ranges, tower overlay offsets and so on) the UCP way: in memory when the game starts,
without touching the exe on disk. Works with both Stronghold Crusader and Stronghold
Crusader Extreme.

## Usage

All values live in a YAML config file, by default `config.yml` in this module's folder.
It has two lists, `extreme` and `vanilla`, with the same entries under the same names;
only the addresses differ. The module applies the list for the exe you run.

Each entry has an `address`, a `size` (1, 2 or 4 bytes), the `value` to write and the
game's `default`. If the exe does not hold the default at that address, the UCP log says
so. Addresses below `0x400000` are treated as file offsets, so entries from Balanceprog's
`config.json` can be pasted in as they are.

To keep your own copy safe from module updates, copy `config.yml` somewhere else and
select it in the option above.

## Building denial ranges

The entries are tagged by who they affect:

* **[player + AI]**: the AI places its buildings through the same checks as the player,
  so these are the AI's build denial ranges too.
* **[AI only]**: `ai_denial_units_walls`, the range in which the AI cannot place wall,
  crenel and stair tiles near enemy units.
* **[player]**: build cursor checks, player-dragged walls, the delete tool and the repair
  button.

"1-player game modes" are campaign missions and custom scenarios. Skirmish, the Crusader
trail and multiplayer use the other value of each pair.
