extends RefCounted
const Style = preload("res://mods/pax_harness/chat_style.gd")
const Icons = preload("res://mods/pax_harness/chat_icons.gd")
const Workspace = preload("res://mods/pax_harness/workspace_ui.gd")

static func icon_button(ui: Node, kind: String, action: Callable, tooltip: String, side: int = 32) -> Button:
	var button: Button = ui._button("",action)
	button.icon = Icons.make(kind)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(side,side)
	button.tooltip_text = tooltip
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,Style.box(Color("#292c32") if state == "hover" else Color("#202226"),5,Color("#35383f"),0))
	return button

static func sidebar_footer(ui: Node, column: VBoxContainer) -> Button:
	var footer := VBoxContainer.new()
	footer.name = "SidebarActions"
	footer.add_theme_constant_override("separation",6)
	column.add_child(footer)
	var detach: Button = ui._button("Отдельное окно",func(): ui.window_manager.toggle_external())
	detach.name = "DetachChats"
	detach.icon = Icons.make("external",ui.QUIET,16)
	detach.alignment = HORIZONTAL_ALIGNMENT_LEFT
	footer.add_child(detach)
	return detach

static func header(ui: Node, body: VBoxContainer, detach: Button) -> void:
	var panel := PanelContainer.new()
	panel.name = "ChatHeader"
	var style: StyleBoxFlat = Style.box(ui.BG,0,Color.TRANSPARENT,16)
	style.corner_radius_top_right = 6
	panel.add_theme_stylebox_override("panel",style)
	body.add_child(panel)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",8)
	panel.add_child(heading)
	ui.title_group = Control.new()
	ui.title_group.name = "ChatTitleGroup"
	ui.title_group.custom_minimum_size.y = 32
	ui.title_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(ui.title_group)
	ui.title_label = ui._label("",16,ui.TEXT)
	ui.title_label.name = "ChatTitleText"
	ui.title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ui.title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui.title_label.clip_text = true
	ui.title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ui.title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.title_group.add_child(ui.title_label)
	ui.title_edit_button = icon_button(ui,"edit",ui._begin_title,"Переименовать чат",24)
	ui.title_edit_button.name = "EditChatTitle"
	for state: String in ["normal","hover","pressed","focus"]:
		ui.title_edit_button.add_theme_stylebox_override(state,Style.box(Color("#292c32") if state == "hover" else Color.TRANSPARENT,4,Color.TRANSPARENT,0))
	ui.title_group.add_child(ui.title_edit_button)
	ui.title_field = LineEdit.new()
	ui.title_field.name = "ChatTitle"
	ui.title_field.max_length = 100
	ui.title_field.placeholder_text = "Название чата"
	ui.title_field.text_submitted.connect(func(_text: String): ui._rename())
	ui.title_field.focus_exited.connect(ui._rename)
	ui.title_field.gui_input.connect(ui._title_key)
	ui.title_group.add_child(ui.title_field)
	ui.title_field.hide()
	ui.title_group.resized.connect(ui._layout_title)
	var instructions: Button = icon_button(ui,"instructions",func(): Workspace.edit(ui),"Инструкции чата")
	instructions.name = "Instructions"
	heading.add_child(instructions)
	ui.window_manager = preload("res://mods/pax_harness/chat_window.gd").new()
	ui.add_child(ui.window_manager)
	ui.window_manager.setup(ui,panel,ui.title_group,heading,detach)
	var cross: Button = icon_button(ui,"close",ui.close,"Закрыть · Esc")
	cross.name = "CloseChats"
	heading.add_child(cross)
	body.add_child(HSeparator.new())

static func composer(ui: Node, body: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "ChatComposer"
	var composer_style: StyleBoxFlat = Style.box(ui.BG,0,Color.TRANSPARENT,16)
	composer_style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel",composer_style)
	body.add_child(panel)
	var composer := VBoxContainer.new()
	composer.add_theme_constant_override("separation",6)
	panel.add_child(composer)
	ui.status = ui._label("",13,ui.QUIET)
	ui.status.name = "ChatRunStatus"
	composer.add_child(ui.status)
	var shell := PanelContainer.new()
	ui.composer_input = shell
	shell.name = "ComposerInput"
	shell.add_theme_stylebox_override("panel",Style.box(Color("#202226"),5,Color("#6699bf"),8))
	composer.add_child(shell)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation",0)
	shell.add_child(fields)
	ui.input = TextEdit.new()
	ui.input.name = "ChatInput"
	ui.input.custom_minimum_size.y = 42
	ui.input.placeholder_text = "Сообщение помощнику…"
	ui.input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ui.input.add_theme_font_override("font",ui.surface.theme.default_font)
	for state: String in ["normal","focus","read_only"]:
		ui.input.add_theme_stylebox_override(state,Style.box(Color.TRANSPARENT,0,Color.TRANSPARENT,0))
	ui.input.gui_input.connect(ui._input_key)
	ui.input.text_changed.connect(func():
		if not ui.store.current().is_empty(): ui.store.current().draft = ui.input.text
		if is_instance_valid(ui.send_button): ui._update_send_state())
	fields.add_child(ui.input)
	var actions := HBoxContainer.new()
	actions.name = "ComposerActions"
	actions.add_theme_constant_override("separation",6)
	fields.add_child(actions)
	var space := Control.new(); space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(space)
	ui.mic_button = icon_button(ui,"mic",func(): ui.native.mic_toggled.emit(),"Голосовой ввод",28)
	ui.mic_button.name = "ChatMicrophone"
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		var mic_style: StyleBoxFlat = Style.box(Color("#292c32") if state == "hover" else Color.TRANSPARENT,6,Color.TRANSPARENT,0)
		mic_style.set_corner_radius_all(14)
		ui.mic_button.add_theme_stylebox_override(state,mic_style)
	actions.add_child(ui.mic_button)
	ui.stop_button = icon_button(ui,"stop",func(): ui.owner_mod.chat_stop(),"Остановить ответ")
	ui.stop_button.name = "StopChatTurn"
	actions.add_child(ui.stop_button)
	ui.send_button = icon_button(ui,"send",ui._send,"Отправить")
	ui.send_button.name = "SendChatMessage"
	ui.send_button.icon = Icons.make("send",Color.WHITE)
	ui.send_button.add_theme_color_override("icon_disabled_color",ui.QUIET)
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		var color: Color = Color("#4c6085") if state == "disabled" else Color("#91b7ff") if state == "hover" else Color("#6493ed") if state == "pressed" else Color("#79a7ff")
		var style: StyleBoxFlat = Style.box(color,6,Color.TRANSPARENT,0)
		style.set_corner_radius_all(16)
		ui.send_button.add_theme_stylebox_override(state,style)
	actions.add_child(ui.send_button)
	var statistics := HBoxContainer.new()
	statistics.name = "SessionStatistics"
	statistics.alignment = BoxContainer.ALIGNMENT_CENTER
	statistics.add_theme_constant_override("separation",10)
	composer.add_child(statistics)
	for kind: String in ["session","tokens","context"]:
		var pill: Button = ui._button("",ui._pin_stat.bind(kind))
		pill.name = "Statistics_"+kind
		pill.icon = Icons.make({"session":"speed","tokens":"tokens","context":"context"}[kind],ui.QUIET,13)
		pill.custom_minimum_size = Vector2(0,24)
		pill.add_theme_font_size_override("font_size",11)
		pill.add_theme_color_override("font_color",ui.QUIET)
		for state: String in ["normal","hover","pressed","focus"]:
			var style: StyleBoxFlat = Style.box(Color("#2c2d2f") if state == "hover" else Color.TRANSPARENT,6,Color.TRANSPARENT,4)
			style.set_corner_radius_all(12)
			pill.add_theme_stylebox_override(state,style)
		pill.mouse_entered.connect(ui._show_stat.bind(kind))
		pill.mouse_exited.connect(ui._stat_mouse_exit)
		statistics.add_child(pill)
		ui._stat_buttons.append(pill)
	ui.mentions = preload("res://mods/pax_harness/chat_mentions.gd").new()
	ui.add_child(ui.mentions)
	ui.mentions.setup(ui,composer)
