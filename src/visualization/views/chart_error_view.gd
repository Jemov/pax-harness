extends PanelContainer
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
func setup(ui: Node, block: Dictionary) -> void:
	name = "ChartError"
	add_theme_stylebox_override("panel",Style.box(Color("#292326"),6,Color("#66504f"),12))
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",8); add_child(body)
	body.add_child(ui._label("Не удалось построить диаграмму",15,Color("#e4b6ab")))
	body.add_child(ui._label(str(block.reason),14,ui.TEXT))
	var details := TextEdit.new(); details.name = "ChartErrorData"; details.editable = false
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; details.custom_minimum_size.y = 180
	details.text = str(block.raw).left(32000); details.visible = false
	var toggle: Button = ui._button("Показать данные диаграммы",func(): details.visible = not details.visible)
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT; body.add_child(toggle); body.add_child(details)
