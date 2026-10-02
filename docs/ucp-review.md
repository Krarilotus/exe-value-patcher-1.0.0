# UCP integration review

The values file is now values.yml, leaving config.yml available for standard UCP defaults. Descriptions and the file picker are translated into every launcher language.

Preserves the existing value payload, migrates only this module's old built-in config path, and leaves custom external paths untouched. Adds standard metadata/dependencies, aligned file-picker defaults and a runtime allowlist. Existing executable patch behavior is unchanged.

## Remaining native work

This remains an advanced tool with raw executable addresses and skip_mismatched=false; it is not a robust cross-build Fixes implementation. Writing despite a byte mismatch is a concrete risk. Values already exposed by Balance/Legacy owners should use those settings. Native binding and hook ownership must be corrected before Store acceptance; this PR does not disguise those gaps.

Inspected upstream parent: `0bbc81f996b080a4cb8deb7c3c0802bdc245fa86`. Launcher locales follow
`UCP3-GUI/resources/lang/languages.yaml` (de, en, fr, ru, hu, tr, ch, es, fa).
Category identities follow the current Legacy/GUI catalog, including its existing
English category fallback; setting and description text has full locale entries.
Human translation review and installed GUI/RTL layout checks are pending.

Offline checks passed: YAML/default consistency, actual GUI control types,
all referenced locale keys, Lua 5.4 syntax and runtime package inputs. Runtime
allowlists exclude research/bench Python. These are not game/editor/save/replay
acceptance. Multiplayer testing belongs to players. No Store release is claimed.
