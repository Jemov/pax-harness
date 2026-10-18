# Pax Harness

An in-game assistant workspace for **Pax Universe 0.31.4**. Use the model and API connection selected in the game to discuss plans, inspect current information, work with mod data, and create charts, tables and images.

[Русское описание](../README.md)

## Installation

**Official Workshop:** open Workshop in the launcher, find Pax Harness, install it and enable it under Mods.

**GitHub:** close the game, download `pax_harness-1.12.0.zip` from Releases and place the complete ZIP in the user mods folder without extracting it. Open Launcher → Mods → Mods folder to locate it; on Windows it is normally `%APPDATA%\Pax Universe\mods`. Enable the mod and approve its code using the game's normal permission prompt if requested. Choose a conversational model in the game, load or start a campaign, and open the normal AI assistant button.

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

The interface is available in Russian and English and follows the game's language, including open mod windows. Player messages, model answers, custom names and entered data remain unchanged. Internal API identifiers remain stable.

Runtime entry: `src/main.gd`. Code is organized under `src/`, translations under `data/lang/`, and project screenshots under `media/`. Release screenshots are separate assets; the installation ZIP does not need the promotional gallery.
