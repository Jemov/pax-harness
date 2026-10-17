extends Control
## A display name shared by chats; persisted through the mod's UI preferences.
const Layout = preload("res://mods/pax_harness/src/ui/chat/chat_layout.gd")
var ui: Node
var display_name := "ВИ"
var label: Label
var pencil: Button
var field: LineEdit
var editing := false

func setup(value: Node) -> void:
	ui = value
	name = "AgentName"
	custom_minimum_size.y = 32
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ui.owner_mod.has_method("get_setting"):
		var saved: Variant = ui.owner_mod.get_setting("agent_display_name","ВИ")
		if saved is String and not _clean(saved).is_empty(): display_name = _clean(saved)
	label = ui._label("✦  "+display_name,19,ui.ACCENT)
	label.name = "AgentNameText"
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	pencil = Layout.icon_button(ui,"edit",begin_edit,"Переименовать агента",24)
	pencil.name = "EditAgentName"
	# Match the chat title's pencil, including its quiet hover style.
	for state: String in ["normal","hover","pressed","focus"]:
		pencil.add_theme_stylebox_override(state,ui.title_edit_button.get_theme_stylebox(state))
	add_child(pencil)
	field = LineEdit.new()
	field.name = "AgentNameInput"
	field.max_length = 64
	field.placeholder_text = "Имя агента"
	field.text_submitted.connect(func(_text: String): commit())
	field.focus_exited.connect(commit)
	add_child(field)
	field.hide()
	resized.connect(_layout)
	_layout()

func _clean(value: String) -> String:
	return value.replace("\n"," ").replace("\r"," ").replace("\t"," ").strip_edges().left(64).strip_edges()

func _layout() -> void:
	if label == null: return
	var desired: float = label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	var width: float = minf(desired,maxf(0,size.x-34))
	label.position = Vector2.ZERO
	label.size = Vector2(width,size.y)
	pencil.position = Vector2(width+7,(size.y-24)/2)
	pencil.size = Vector2(24,24)
	field.position = Vector2.ZERO
	field.size = size

func begin_edit() -> void:
	editing = true
	field.text = display_name
	label.hide()
	pencil.hide()
	field.show()
	field.grab_focus()
	field.select_all()

func commit() -> void:
	if not editing: return
	editing = false
	var value: String = _clean(field.text)
	if not value.is_empty() and value != display_name:
		display_name = value
		if ui.owner_mod.has_method("set_setting"): ui.owner_mod.set_setting("agent_display_name",display_name)
		label.text = "✦  "+display_name
		ui._keep_position = true
		ui._schedule_refresh()
	_finish()

func cancel() -> void:
	if not editing: return
	editing = false
	_finish()

func _finish() -> void:
	field.hide()
	label.show()
	pencil.show()
	_layout()
