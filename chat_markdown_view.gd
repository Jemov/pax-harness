extends VBoxContainer
## Retain completed visual blocks while the trailing answer is streamed.
const Markdown = preload("res://mods/pax_harness/chat_markdown.gd")
var _blocks: Array = []
var _charts: Array = []

func update_content(ui: Node, text: String, events: Array = [], complete: bool = true) -> void:
	var blocks: Array = Markdown.blocks(text,events,complete).filter(func(block: Dictionary):
		return block.kind != "text" or not str(block.text).strip_edges().is_empty())
	for index: int in blocks.size():
		var block: Dictionary = blocks[index]
		if index < _blocks.size() and _blocks[index] == block: continue
		if index < _blocks.size() and _blocks[index].kind == "text" and block.kind == "text":
			get_child(index).text = Markdown.render(str(block.text))
			continue
		if index < get_child_count():
			var old: Node = get_child(index)
			remove_child(old); old.queue_free()
		var node: Control
		match block.kind:
			"text": node = ui._rich(str(block.text))
			"chart":
				node = preload("res://mods/pax_harness/chat_chart_view.gd").new()
				node.map_target = ui._chart_map_target
				node.province_requested.connect(ui._chart_go_to_province)
				node.setup(block.spec)
				node.resource_hovered.connect(_highlight)
			"table":
				node = preload("res://mods/pax_harness/chat_table_view.gd").new()
				node.setup(ui,block)
			"chart_error":
				node = preload("res://mods/pax_harness/chart_error_view.gd").new()
				node.setup(ui,block)
		add_child(node); move_child(node,index)
	while get_child_count() > blocks.size():
		var old: Node = get_child(-1)
		remove_child(old); old.queue_free()
	_blocks = blocks
	_charts.clear()
	for index: int in blocks.size():
		if blocks[index].kind == "chart": _charts.append(get_child(index))
	visible = not blocks.is_empty()

func _highlight(label: String) -> void:
	for chart: Node in _charts:
		if is_instance_valid(chart): chart.highlight_resource(label)
