extends RefCounted
const Icons=preload("res://mods/pax_harness/src/creation/creation_icons.gd")
const Data=preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
static func update(service: Node, panel: Object, body: String) -> void:
	var ui: Variant=Data.property(panel,"ui"); var list: Variant=Data.property(ui,"resources_list")
	if not list is Control or not panel.has_method("cell"): return
	# The bus fires after this colony's native grid, before its treasury. Append
	# cells inside that grid; keep the native separator below ALL resource rows.
	var grid: GridContainer
	for child: Node in list.get_children():
		if child is GridContainer and not child.is_queued_for_deletion(): grid=child
	if grid==null or grid.columns!=4: return
	for record: Dictionary in service.records.values():
		if record.kind!="resource": continue
		var d: Dictionary=record.definition; var key: String=record.resource_key
		for suffix: String in ["","Amount","Balance","Trade"]:
			var previous: Node=grid.get_node_or_null("HarnessResource"+suffix+"_"+str(d.id))
			if previous!=null: grid.remove_child(previous); previous.queue_free()
		var label: Label; var search: Array=grid.get_children()
		while not search.is_empty():
			var node: Node=search.pop_back(); search.append_array(node.get_children())
			if node is Label and (node.text==service._title(d) or node.text==key): label=node; break
		if label==null:
			panel.cell(grid,service._title(d)); label=grid.get_child(grid.get_child_count()-1)
			label.name="HarnessResource_"+str(d.id)
			var amount: float=float(service.game.resources(body).get(key,0))
			var number: String=str(panel.call("number_text",amount)) if panel.has_method("number_text") else str(int(amount)) if amount==floorf(amount) else str(amount)
			var formatter: Variant=panel.get_script().get_script_constant_map().get("WorldScript")
			if formatter is Script and formatter.has_method("_number"): number=str(formatter.call("_number",amount))
			panel.cell(grid,number); grid.get_child(grid.get_child_count()-1).name="HarnessResourceAmount_"+str(d.id)
			panel.cell(grid,""); grid.get_child(grid.get_child_count()-1).name="HarnessResourceBalance_"+str(d.id)
			var trade:=Control.new(); trade.name="HarnessResourceTrade_"+str(d.id); grid.add_child(trade)
		label.text=service._title(d)
		if d.get("text_color") is String: label.add_theme_color_override("font_color",Color(d.text_color))
		else: label.remove_theme_color_override("font_color")
		# Native ResourceIcons.name_cell uses a 16px icon and a 4px gap.
		if label.get_parent().get_meta("harness_resource_icon","")==key: continue
		var parent: Node=label.get_parent(); var index: int=label.get_index()
		parent.remove_child(label)
		var cell:=HBoxContainer.new(); cell.name=label.name; label.name="Name"; cell.set_meta("harness_resource_icon",key); cell.add_theme_constant_override("separation",4)
		parent.add_child(cell); parent.move_child(cell,index)
		var icon:=TextureRect.new(); icon.texture=Icons.make(d.icon); icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.custom_minimum_size=Vector2(16,16); icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon); cell.add_child(label)
