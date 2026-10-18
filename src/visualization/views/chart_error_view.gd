extends PanelContainer
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
const Response = preload("res://mods/pax_harness/src/visualization/chart_response.gd")
var _reason: Label
var _block: Dictionary
func setup(ui: Node, block: Dictionary) -> void:
	_block = block.duplicate(true)
	name = "ChartError"
	add_theme_stylebox_override("panel",Style.box(Color("#292326"),6,Color("#66504f"),12))
	var body := VBoxContainer.new(); body.add_theme_constant_override("separation",8); add_child(body)
	body.add_child(ui._label(L.text("Не удалось построить диаграмму"),15,Color("#e4b6ab")))
	_reason = ui._label(str(block.reason),14,ui.TEXT)
	_reason.set_meta("mod_user_text",true); body.add_child(_reason)
	var details := TextEdit.new(); details.name = "ChartErrorData"; details.editable = false
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; details.custom_minimum_size.y = 180
	details.text = str(block.raw).left(32000); details.visible = false
	var toggle: Button = ui._button(L.text("Показать данные диаграммы"),func(): details.visible = not details.visible)
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT; body.add_child(toggle); body.add_child(details)

func refresh_locale() -> void:
	if not is_instance_valid(_reason): return
	if _block.get("code","") == "charts.unclosed_fence":
		_reason.text = L.text("Ответ оборвался: блок диаграммы не завершён.")
	else:
		var checked: Dictionary = Response.inspect(str(_block.get("raw","")))
		if not checked.ok and checked.code == _block.get("code",""): _reason.text = checked.reason
