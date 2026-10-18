# Tool discovery

Assistant turns start with `tools.groups` and `tools.load`, plus a compact catalogue of available permitted groups. `tools.load({"groups":["charts"]})` exposes the selected group's full schemas on the next model request. It loads metadata only. Chart and interface guides follow their groups as well.

Group IDs: `charts`, `maps`, `analytics`, `ui`, `images`, `space`, `economy`, `world`, `chat`, `workspace`, `prompts`, `people`, `orders`, `research`, `diplomacy`, `military`, `time`. Only groups containing available tools granted to the current session are listed. Existing `package_id` metadata remains compatible with prompt profiles; `group_id` controls discovery.

Loading does not grant tools, run an action, read a dataset or generate a star system. Calls into unloaded groups return `tools.group_not_loaded` before the handler runs. Unknown or ungranted groups fail without partially loading a batch. Each new user turn and analysis child has independent discovery state. Native non-chat task contracts retain their original grants and delivery protocol.

Within a selected group, expensive content remains on demand: `charts.describe` returns one visualization schema; `analytics.sources` returns provider metadata; `analytics.query` reads a page; map geometry remains in local chart receipts. Saved step events record the advertised tool names and schema character count without recording API credentials.
