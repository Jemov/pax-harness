# Pax Harness

An in-game assistant workspace for **Pax Universe 0.31.5**. Use the model and API connection selected in the game to discuss plans, inspect current information, work with mod data, and create charts, tables and images.

[Русское описание](../README.md)

## Tools on demand

The assistant initially receives a short group catalogue. Full chart, map, interface, space and other tool schemas are loaded only when needed. Mod datasets and individual visualization schemas are also queried separately.

## Creating new content

On an explicit request, the assistant can prepare a voxel object and icon, a new resource, an object panel, a warp route or an artificial surface for a star/gas giant. Models appear directly in chat messages with rotation, zoom and Apply/Reject buttons. Open the searchable collection through **Settings → Harness → Open new entity projects**. Only the player’s **Apply** button adds the reviewed change to the current campaign.

An artificial surface is a separate solid shell with its own native map and 4–40 territories. The original star or gas giant is preserved. After approval, ask to open that body's surface map. Territories and objects are saved with the campaign. This is scenario authoring: it grants no population, colony, stock or research. Use normal game orders for resource-funded terraforming.

Warp routes join two approved objects in actual existing systems. Rerouting an existing ship requires separate approval, preserves cargo/passengers and uses native arrival on a later turn. New universes are not created. Object panels contain labelled values, without arbitrary scripts.

Find the collapsible tool catalogue with short descriptions under **Settings → Harness → Agent tools**. Each group and function has a checkbox; a square marks a partially enabled group. Disabled functions are omitted from model schemas and cannot execute, even during an ongoing reply. Preferences persist across campaigns. Resource rows match the native game; a text-color accent requires an explicit request and a separately approved project.

## Geography and space

Ask for a sea, lake or coastline with surrounding land. Harness reads the current campaign's water raster, including scenario and mod edits. Small views retain province identities; wide views can merge land into a context layer. Maps on other bodies must already be loaded in the game. Mods can register named features through the general source API. Geometry stays in local receipts; the model receives a compact description and display reference.

Search the game's actual body and star catalogues, inspect configured orbital/terraforming rules, enter a system and focus its actual members. For example: “Move the camera to Ross 154 e.” If the native generated system has no such planet, Harness reports that instead of inventing one. Camera navigation does not transport residents, launch a ship or found a colony.

## How to open the chat and settings

1. Enable **Pax Harness** under **Mods**, then **load or start a campaign**.
2. Click the normal in-game **assistant (VI) button** to open the Harness chat.
3. Open **Game menu → Settings → Harness tab** for the mod settings.

The Harness tab controls text size, conversation display, keyboard shortcuts, sending during an answer and usage statistics. Model and API connection settings are separate, under **Settings → AI**.

## Installation

**Official Workshop:** open Workshop in the launcher, find Pax Harness, install it and enable it under Mods.

**GitHub:** close the game, download `pax_harness-1.16.0.zip` from Releases and place the complete ZIP in the user mods folder without extracting it. Open Launcher → Mods → Mods folder to locate it; on Windows it is normally `%APPDATA%\Pax Universe\mods`. Enable the mod and approve its code using the game's normal permission prompt if requested. Choose a conversational model in the game, load or start a campaign, and open the normal AI assistant button.

Keep only one installed copy. Close the game before manually replacing an older ZIP or folder. Workshop installations update through the launcher. Conversations belong to campaign saves and are not stored in the installation archive.

## Conversations and tools

- Create multiple chats and sections, pin conversations, search, rename and reorder them. Drag the sidebar divider to resize it. Edit the agent's display name beside its name in chat.
- Responses stream as they are generated. Expand completed steps and tool results to inspect the evidence behind an answer.
- Use `@` references or drag another chat into a message. The assistant can read referenced chats on request; cross-chat messages are kept in the same save.
- Set persistent instructions for one chat or the campaign and keep a task plan with progress markers.
- Drafts, chat history, plans and instructions are saved with the campaign. `/compact` summarizes older history when needed; missing current observations are never treated as facts merely because they appear in a summary.
- Ask the assistant to open registered game panels, including resources, production, research and settings. Panel navigation does not itself approve actions.
- Available data depends on installed and enabled mods. Adapters support sources such as Pax Corporations, economic mods and the Dyson Sphere. Extra source descriptions are requested as tools when needed.

Try: “Compare food production and consumption and explain the deficit”, “Group the last ten failed plans by cause”, “Compare company revenue and profit in a table”, or “Map provinces with the most enterprises”. State explicitly when you want analysis without changes to the world.

## Settings

Open **Settings → Harness**. Changes save immediately.

| Setting | Behavior |
| --- | --- |
| Font size | Conversation text and table cells; interface controls keep their usual size. |
| Conversation display | Detailed steps, collapsed steps, or answers only for completed turns. Active turns and errors remain discoverable. |
| Technical details | Show or hide expandable tool arguments and raw results. Tool access is unchanged. |
| Sending while working | Queue after the current response, interrupt and send, or keep the draft until completion. Ctrl+Enter swaps queue and interrupt. Queued messages can be cancelled and are not added to an active model request. |
| Performance and usage | Detailed timing/token/cache/context information, basic usage, or a hidden statistics bar. Unknown API usage remains unknown. |
| Keyboard shortcuts | Assign send, new chat, search and stop shortcuts. Esc cancels reassignment; Shift+Enter inserts a line break. |
| Images | Use the game's generator and optionally provide a ComfyUI API workflow. |

Model, endpoint, context window and generation parameters stay in the game's existing **Settings → AI → Additional → Advanced settings** form. The separate AI tuning mod adds per-model profiles there.

## Charts and tables

The assistant can use 39 chart types, mathematical functions and province maps. Categories include horizontal and vertical bars (including stacked variants), lines and areas, combo charts, intervals and error bars, waterfalls, dumbbell comparisons, slopes and bumps, scatter and bubble plots, histograms, box/density/violin/ridgeline distributions, pie and donut charts, treemaps, heatmaps and calendar heatmaps, choropleths/cartograms/symbol maps/flow maps, Sankey flows, networks, trees/sunburst/icicle hierarchies, Gantt timelines, radar, parallel coordinates and small multiples.

Ask for the visualization you need in normal language. Tools describe each chart's schema and required data on demand. Unsupported or malformed structures return a specific error to the assistant so it can repair them. The conversation also keeps diagnostics if repair fails.

Charts support the controls relevant to their type, including zoom, filtering, animation replay and highlighting related flows or nodes. Province maps use game boundaries and can offer a right-click navigation action. Geographic coverage and missing values are stated; absent observations are not converted into invented zeros.

Tables support filtering, sorting, paging and CSV export. You can also copy conversation content as text, Markdown or JSON using its context menu.

For an illustrative calculation, ask for a parabola, sinusoid or projected growth curve. Examples and forecasts are labelled separately from observed campaign data, with their source or assumptions shown.

## Images and screenshots

Configure an image generator in **Settings → AI → Image generation**. Ask the assistant to generate an illustration and it uses that game service. If it is unavailable or not configured, the assistant receives the actual reason. Failed generation is not silently presented as a finished image.

For ComfyUI, export a workflow in API JSON format and select its positive prompt field in Harness settings. The server connection comes from the game. Keep access keys out of workflow files. Images are stored with chat metadata and shown in the conversation gallery.

To let a vision-capable model inspect the game, enable its profile and **Image input** in AI tuning. The API and model must accept images. The screenshot tool captures the game viewport with chat temporarily hidden; it does not capture unrelated desktop windows. A text-only model does not acquire vision by enabling this setting.

## Languages and files

The interface is available in Russian and English and follows the game's language, including open mod windows. Other game languages use English. Player messages, model answers, custom names and entered data remain unchanged. Internal API identifiers remain stable.

Runtime entry: `src/main.gd`. Code is organized under `src/`, translations under `data/lang/`, and project screenshots under `media/`. Release screenshots are separate assets; the installation ZIP does not need the promotional gallery.


### Inline 3D objects

Model projects appear directly in chat messages. Drag to rotate, scroll to zoom, and use Apply or Reject in the card. The collection in Settings → Harness has search, filters and ten rows per page, with collapsed details.

Ordinary voxel models need no optional component. Detached destructible objects require **Voxel Tools**. Enable Destruction in an applied object card and click the model to remove a region of its voxel volume. Damage persists with the campaign. The agent can propose a separate damage operation when explicitly requested. This does not add automatic combat, debris or portal animation.

Use **Go to object** on an applied model card to close chat and frame the actual object in space, rather than only its parent planet. Standard orbit controls and object-scale wheel zoom remain available. The agent can also use creation.focus for the same camera action.

**Local 3D ship routes:** with Dyson Sphere Program enabled, the assistant can prepare a route for a real vessel relative to a created object: approach, fly around it or cross a ring. It chooses the model, size, nose direction and waypoints. Apply the card, then use Replay flight. Routes persist with the campaign; a new normal ship order restores native control. The route controls motion. An agent-authored object program defines crossing reactions, relocation, charge costs or health changes; physical collision simulation is not included.


### Programmable entities

Ask the assistant to create both a model and its working behavior. It writes a program using state variables, conditions, loops, timers, day changes, volume entry and plane crossings. General host operations read game data, move real ships and authored objects, change ship health, modify native colony stock or damage a voxel object. Available actions depend on installed adapters; the assistant composes the behavior rather than selecting a predefined gate mechanic.

Apply the reviewed model and program together in the chat card. Its fields and buttons work in that card. Events then run independently, and state persists with the campaign. You can pause a program; revisions require another approval. A fault stops that program and reports its exact cause and source path to the assistant. Completed world actions remain in effect.

For example, request floating gates, an exit near another body, charge and hull-clearance checks, a transfer counter and a recharge button. With Dyson Sphere Program installed, the authored program can relocate the same native ship to a calculated destination while retaining cargo and health. It uses general operations rather than a built-in gate-link behavior. See the [program format](entity-programs.en.md).
