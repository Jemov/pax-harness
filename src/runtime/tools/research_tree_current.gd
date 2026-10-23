extends RefCounted
## Fixed native research-tree bridge. Reads never seed the tree or ask the AI.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const TREE_PATH := "res://src/web/casual/ResearchTree.gd"
const VIEW_PATH := "res://src/web/casual/ResearchTreeView.gd"

static func enabled() -> bool:
	var api: Node = _api()
	if api == null or not bool(api.call("has_resource",TREE_PATH)): return false
	var tree: Variant = api.call("resource",TREE_PATH)
	return tree != null and tree.has_method("on") and bool(tree.call("on"))

static func _api() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	var api: Node = loop.root.get_node_or_null("Pax") if loop is SceneTree else null
	return api if api != null and api.has_method("has_resource") and api.has_method("resource") else null

static func read(main: Node) -> Dictionary:
	var model: Variant = Data.property(main,"model")
	var features: Variant = Data.property(model,"features")
	var state: Variant = features.get("research_tree",{}) if features is Dictionary else {}
	var scopes: Array = []
	var nodes: Array = []
	var states: Dictionary = {}
	if state is Dictionary:
		if state.get("spheres") is Array: scopes = Data.clean(state.spheres)
		if state.get("nodes") is Array:
			for node: Variant in state.nodes:
				if node is Dictionary:
					states[str(node.get("id",""))] = str(node.get("state","locked"))
			for node: Variant in state.nodes:
				if not node is Dictionary: continue
				var row: Dictionary = Data.clean(node)
				var status: String = str(node.get("state","locked"))
				if status == "locked":
					status = "open"
					for required: Variant in node.get("requires",[]):
						if states.get(str(required),"") != "done": status = "locked"; break
				row["status"] = status
				nodes.append(row)
	var legacy: Variant = Data.property(model,"research_list")
	return {"mode":"research_tree","window_open":visible(main),"initialized":state is Dictionary and state.get("nodes") is Array,
		"scopes":scopes,"scope_source":"model.features.research_tree.spheres","nodes":nodes,
		"legacy_proposals":Data.clean(legacy) if legacy is Array else [],"legacy_proposals_separate":true,
		"read_only":true,"instruction":"These are the current native tree nodes. Status is computed from state and requires; legacy proposals are separate native records and may progress independently. Use the observed native tree controls to start or cancel a tree node; research.propose/confirm/cancel address legacy proposals only."}

static func can_open() -> bool:
	var api: Node = _api()
	if not enabled() or api == null or not bool(api.call("has_resource",VIEW_PATH)): return false
	var script: Variant = api.call("resource",VIEW_PATH)
	return script != null and script.has_method("toggle")

static func view(main: Node) -> Node:
	var ui: Variant = Data.property(main,"ui")
	if not ui is Object or not is_instance_valid(ui) or not ui.has_meta("research_tree_view"): return null
	var window: Variant = ui.get_meta("research_tree_view")
	return window if window is Node and is_instance_valid(window) and not window.is_queued_for_deletion() and window.is_inside_tree() and main.is_ancestor_of(window) else null

static func visible(main: Node) -> bool:
	var window: Node = view(main)
	return window != null and bool(Data.property(window,"visible"))

static func title(main: Node) -> String:
	var ui: Variant = Data.property(main,"ui")
	var button: Variant = ui.get_meta("research_button") if ui is Object and ui.has_meta("research_button") else null
	if button is Button and is_instance_valid(button) and button.text.strip_edges() != "": return button.text.left(200)
	return L.text("Исследования")

static func open(main: Node) -> Dictionary:
	if not can_open(): return Data.failed("ui.panel_unavailable")
	var opened: bool = not visible(main)
	if opened:
		# Native toggle also calls grow_pending: opening may ask the game's AI
		# to extend the catalogue, as the ordinary player button does.
		if view(main) != null: return Data.failed("ui.panel_not_visible")
		var script: Variant = _api().call("resource",VIEW_PATH)
		script.call("toggle",main)
	if not visible(main): return Data.failed("ui.panel_not_visible")
	var observed: Dictionary = read(main)
	return Data.success({"panel":"science","title":title(main),"backend":"research_tree","visible":true,
		"navigation_only":true,"settings_modified":false,"research_started":false,"native_growth_check":opened,
		"instruction":"Opened the game's research tree. A newly opened native view may ask its provider to grow the catalogue; this does not start research. Use research.read for node details.",
		"research_summary":{"scope_count":observed.scopes.size(),"node_count":observed.nodes.size()}})
