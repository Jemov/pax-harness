extends RefCounted
## Discovery changes schema exposure only; the original grants remain authoritative.
const CORE := ["tools.groups", "tools.load"]
const INFO := {
	"mods":["Mod entities and controls","Discover enabled mods, browse their campaign entities on demand and inspect/operate their actual visible controls. Read state/UI after actions; no arbitrary code or methods."],
	"creation":["Player-reviewed content","Voxel objects, icons, resources, panels, warp routes and artificial surfaces with native territories require player Apply; no apply tool. creation.focus moves only the space camera to an approved object. creation.inspect reads its geometry. creation.actors observes actual native Dyson ships, their location, cargo and health; ships.read is scheduled passenger transport only. creation.program_schema exposes a general entity language: state, events, conditions, loops and world primitives. The agent writes new behavior in object.program or a behavior project, validates source with creation.validate_program and reads actual results/errors with creation.program_status. Optional Dyson ship flights follow object-relative 3D routes after player review."],
	"charts":["Charts and tables","Visualization schemas, datasets, transformations and statistics."],
	"maps":["Maps and provinces","Land, water and mod map layers; province observations."],
	"analytics":["Analytics and mod data","Discover and page installed-mod data sources; resource history."],
	"ui":["Game interface","Inspect/open native panels and capture the game screen when vision is enabled."],
	"images":["Image generation","Status and generation through the configured native image service."],
	"space":["Space and navigation","Find bodies/stars, read project rules, navigate systems and ships."],
	"economy":["Economy","Resources, stocks and money."],
	"world":["World and history","Current world state and paged historical observations."],
	"chat":["Saved chats","Find/read chats and send messages only with player authorization."],
	"workspace":["Task workspace","Plans, standing instructions, execution traces and isolated analysis."],
	"prompts":["Prompt templates","Optional laboratory templates and authorized edits."],
	"people":["Characters","Character observations and supported actions."],
	"orders":["Orders","Read and submit supported game orders."],
	"research":["Research","Native research observations and actions."],
	"diplomacy":["Diplomacy and laws","Diplomatic and legal observations/actions."],
	"military":["Military","Native military observations and actions."],
	"time":["Time","Supported calendar/time actions; advancing time needs authorization."]
}

static func group_for(name: String) -> String:
	if name in CORE: return "tools"
	if name in ["charts.map", "charts.map_sources"] or name.begins_with("provinces."): return "maps"
	if name == "resources.history" or name.begins_with("analytics."): return "analytics"
	match name.get_slice(".",0):
		"charts", "datasets", "statistics": return "charts"
		"space", "navigation", "bodies", "ships": return "space"
		"resources", "money": return "economy"
		"world", "history": return "world"
		"plan", "instructions", "trace", "analysis": return "workspace"
		"characters": return "people"
		"laws", "diplomacy": return "diplomacy"
	return name.get_slice(".",0)

static func summaries(catalogue: Array, enabled: Variant) -> Array:
	var counts: Dictionary = {}
	for row: Dictionary in catalogue:
		if row.name in CORE or row.name not in enabled or not row.get("available",true) or not row.get("enabled",true): continue
		var id := group_for(row.name)
		counts[id] = int(counts.get(id,0))+1
	var result: Array = []
	for id: String in counts:
		var info: Array = INFO.get(id,[id,"Supported registered tools in this group."])
		result.append({"id":id,"title":info[0],"description":info[1],"tool_count":counts[id]})
	return result

static func visible(scope: Dictionary, name: String) -> bool:
	return not scope.get("lazy_tools",false) or name in CORE or group_for(name) in scope.get("loaded_tool_groups",[])

static func session_scope(original: Dictionary) -> Dictionary:
	var scope := original.duplicate()
	if scope.get("channel","") != "assistant": return scope
	scope["lazy_tools"] = true
	# A new user turn/analysis child starts with an independent discovery state.
	scope["loaded_tool_groups"] = []
	scope["enabled_tools"] = PackedStringArray(original.get("enabled_tools",[]))
	for name: String in CORE:
		if name not in scope.enabled_tools: scope.enabled_tools.append(name)
	return scope

static func execute(catalogue: Array, scope: Dictionary, name: String, arguments: Dictionary) -> Dictionary:
	var groups := summaries(catalogue,scope.get("enabled_tools",[]))
	if name == "tools.groups":
		return {"ok":true,"result":{"groups":groups,"loaded_groups":scope.get("loaded_tool_groups",[])}}
	var requested: Variant = arguments.get("groups",[])
	if not requested is Array or requested.is_empty() or requested.size()>4:
		return {"ok":false,"code":"tools.invalid_groups","result":{"groups":groups}}
	var known: Array = []
	for row: Dictionary in groups: known.append(row.id)
	for id: Variant in requested:
		if not id is String or id not in known:
			return {"ok":false,"code":"tools.unknown_or_ungranted_group","result":{"requested":requested,"groups":groups}}
	if not scope.has("loaded_tool_groups"): scope["loaded_tool_groups"] = []
	# Dispatch receives a shallow scope copy. Mutate this shared array in place.
	for id: String in requested:
		if id not in scope.loaded_tool_groups: scope.loaded_tool_groups.append(id)
	var names: Array = []
	for row: Dictionary in catalogue:
		if row.name in scope.get("enabled_tools",[]) and row.get("available",true) and row.get("enabled",true) and group_for(row.name) in requested: names.append(row.name)
	return {"ok":true,"result":{"loaded_groups":scope.loaded_tool_groups.duplicate(),"tools":names,"schemas_available":"next_request","permissions_changed":false}}
