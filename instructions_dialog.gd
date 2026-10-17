extends Control
## One editor per scope; drafts are committed together to the captured chat.
const Style = preload("res://mods/pax_harness/chat_style.gd")
const Icons = preload("res://mods/pax_harness/chat_icons.gd")
var ui: Node
var chat_id: String
var panel: PanelContainer
var campaign: TextEdit
var current: TextEdit
var save_button: Button
var cancel_button: Button
var tabs: Dictionary = {}
var _previous_focus: WeakRef
var _closing := false

func setup(value: Node) -> void:
	ui = value
	chat_id = ui.store.selected
	name = "InstructionsDialog"
	theme = ui.surface.theme
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_STOP
	_previous_focus = weakref(ui.get_viewport().gui_get_focus_owner())
	ui.add_child(self)
	var dim := ColorRect.new()
	dim.color = Color(0,0,0,0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.name = "InstructionsPanel"
	panel.add_theme_stylebox_override("panel",Style.box(ui.BG,6,Color("#35383f"),20))
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",10)
	column.add_child(heading)
	var title: Label = ui._label("Инструкции",18,ui.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.clip_text = true
	heading.add_child(title)
	var close_button: Button = ui._button("",dismiss)
	close_button.icon = Icons.make("close",ui.TEXT)
	close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.name = "CloseInstructions"
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.tooltip_text = "Закрыть"
	close_button.custom_minimum_size = Vector2(32,32)
	for state: String in ["normal","hover","pressed","focus"]:
		var background := Color("#292c32") if state == "hover" else Color("#202226") if state == "pressed" else Color.TRANSPARENT
		close_button.add_theme_stylebox_override(state,Style.box(background,5,ui.ACCENT if state == "focus" else Color.TRANSPARENT,0))
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		close_button.add_theme_color_override(state,ui.TEXT)
	heading.add_child(close_button)
	var subtitle: Label = ui._label(str(ui.store.find(chat_id).get("title","")),13,ui.QUIET)
	subtitle.name = "InstructionsChatTitle"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.clip_text = true
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(subtitle)
	var scopes := HBoxContainer.new()
	scopes.add_theme_constant_override("separation",4)
	column.add_child(scopes)
	for scope: String in ["chat","campaign"]:
		var tab: Button = ui._button("Этот чат" if scope == "chat" else "Вся партия",select_scope.bind(scope))
		tab.name = "ChatScope" if scope == "chat" else "CampaignScope"
		tab.focus_mode = Control.FOCUS_ALL
		tab.add_theme_font_size_override("font_size",14)
		tabs[scope] = tab
		scopes.add_child(tab)
	var host := Control.new()
	host.name = "InstructionsEditor"
	host.custom_minimum_size.y = 100
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(host)
	campaign = _field(host,"CampaignInstructions",ui.store.campaign_instructions,"Правила для всех чатов этой партии…")
	current = _field(host,"ChatInstructions",str(ui.store.find(chat_id).get("instructions","")),"Как ВИ должен отвечать и действовать в этом чате…")
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation",8)
	column.add_child(buttons)
	cancel_button = ui._button("Отмена",dismiss)
	cancel_button.name = "CancelInstructions"
	cancel_button.focus_mode = Control.FOCUS_ALL
	cancel_button.custom_minimum_size = Vector2(96,36)
	buttons.add_child(cancel_button)
	save_button = ui._button("Сохранить",save)
	save_button.name = "SaveInstructions"
	save_button.focus_mode = Control.FOCUS_ALL
	save_button.custom_minimum_size = Vector2(112,36)
	for state: String in ["normal","hover","pressed","focus"]:
		save_button.add_theme_stylebox_override(state,Style.box(Color("#54739b") if state == "hover" else Color("#435e83"),5,ui.ACCENT if state == "focus" else Color.TRANSPARENT,10))
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		save_button.add_theme_color_override(state,Color("#f0f3f8"))
	buttons.add_child(save_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	select_scope("chat")
	current.grab_focus.call_deferred()

func select_scope(scope: String) -> void:
	current.visible = scope == "chat"
	campaign.visible = scope == "campaign"
	for key: String in tabs:
		var tab: Button = tabs[key]
		var selected: bool = scope == key
		for state: String in ["normal","hover","pressed","focus"]:
			tab.add_theme_stylebox_override(state,Style.box(Color("#292d35") if selected or state == "hover" else Color.TRANSPARENT,5,ui.ACCENT if state == "focus" else Color.TRANSPARENT,8))
		tab.add_theme_color_override("font_color",ui.TEXT if selected else ui.QUIET)
		tab.set_meta("selected",selected)

func _field(host: Control, node_name: String, text: String, placeholder: String) -> TextEdit:
	var field := TextEdit.new()
	field.name = node_name
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field.add_theme_font_override("font",theme.default_font)
	field.add_theme_font_size_override("font_size",14)
	field.add_theme_constant_override("line_spacing",4)
	field.add_theme_stylebox_override("normal",Style.box(Color("#202226"),5,Color("#35383f"),12))
	field.add_theme_stylebox_override("focus",Style.box(Color("#202226"),5,Color("#6699bf"),12))
	field.text = text
	field.placeholder_text = placeholder
	host.add_child(field)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return field

func _layout() -> void:
	size = get_viewport().get_visible_rect().size
	panel.size = Vector2(minf(680,size.x-32),minf(480,size.y-32))
	panel.position = ((size-panel.size)/2).floor()

func handle_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		dismiss()
		get_viewport().set_input_as_handled()

func save() -> void:
	if _closing: return
	var chat: Dictionary = ui.store.find(chat_id)
	if not chat.is_empty():
		ui.store.campaign_instructions = campaign.text.left(16000)
		chat["instructions"] = current.text.left(16000)
		ui.store.changed.emit()
	dismiss()

func dismiss() -> void:
	if _closing: return
	_closing = true
	hide()
	var previous: Control = _previous_focus.get_ref() if _previous_focus != null else null
	if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	queue_free()
