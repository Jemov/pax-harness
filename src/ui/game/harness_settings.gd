extends Node
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## A native Settings tab for Harness preferences, independent of model profiles.
const Preferences = preload("res://mods/pax_harness/src/ui/chat/chat_preferences.gd")
const TAB := "pax_harness"
var owner_mod: Node
var tab_button: Button
var panel: VBoxContainer
var fields: Dictionary = {}
var _shortcut_action := ""
var _shortcut_buttons: Dictionary = {}
var feedback: Label
var _menu_ref: WeakRef
var _elapsed := 0.0
var _disposing := false
var _active_appearance: Dictionary = {}

func setup(owner: Node) -> void:
	owner_mod = owner
	name = "HarnessSettings"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _menu() -> Node:
	if not is_instance_valid(owner_mod) or not owner_mod._game_available(): return null
	var main: Node = owner_mod._game.scene_root()
	return main.ui.menu_node if is_instance_valid(main) else null

func _parts(menu: Node) -> Dictionary:
	if menu == null or not menu.visible or not is_instance_valid(menu.screen): return {}
	var strip: HBoxContainer
	var body: VBoxContainer
	for child: Node in menu.screen.get_children():
		if child.is_queued_for_deletion(): continue
		if child is HBoxContainer:
			var matches := 0
			for button: Node in child.get_children():
				if not button is Button or button.is_queued_for_deletion(): continue
				for key: String in ["game","graphics","нейросеть"]:
					if button.text.strip_edges() == str(menu.t_("вкл_"+key)) or button.text.strip_edges().ends_with("  "+str(menu.t_("вкл_"+key))): matches += 1
			if matches >= 3: strip = child
		if child is ScrollContainer:
			for node: Node in child.get_children():
				if node is VBoxContainer and not node.is_queued_for_deletion(): body = node
	return {"strip":strip,"body":body} if strip != null and body != null else {}

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25: return
	_elapsed = 0
	refresh()

func refresh() -> void:
	if _disposing: return
	var menu: Node = _menu()
	var parts: Dictionary = _parts(menu)
	if parts.is_empty(): return
	_remember_active_style(menu,parts)
	_menu_ref = weakref(menu)
	if not is_instance_valid(tab_button) or tab_button.is_queued_for_deletion() or tab_button.get_parent() != parts.strip:
		if is_instance_valid(tab_button) and not tab_button.is_queued_for_deletion(): tab_button.queue_free()
		# Duplicate a stock tab without scripts, signals or groups. Its complete theme,
		# font, icon spacing and layout follow the current game's settings UI.
		for child: Node in parts.strip.get_children():
			if child is Button and child != tab_button and not child.is_queued_for_deletion() and not _is_selected_native_tab(menu,child):
				tab_button = child.duplicate(0) as Button
				break
		if tab_button == null: return
		# Native icon/accessibility initialization belongs to this new control.
		for key: StringName in tab_button.get_meta_list(): tab_button.remove_meta(key)
		tab_button.name = "HarnessSettingsTab"
		tab_button.icon = null
		tab_button.text = L.text("🛠  Харнес")
		tab_button.pressed.connect(open)
		if menu.settings_tab == TAB: _apply_active_appearance()
		parts.strip.add_child(tab_button)

func _is_selected_native_tab(menu: Node, button: Button) -> bool:
	var caption: String = str(menu.t_("вкл_"+str(menu.settings_tab)))
	return button.text.strip_edges() == caption or button.text.strip_edges().ends_with("  "+caption)

func _apply_active_appearance() -> void:
	for property: String in _active_appearance:
		tab_button.set(property,_active_appearance[property])

func _remember_active_style(menu: Node, parts: Dictionary) -> void:
	if menu.settings_tab == TAB: return
	var caption: String = str(menu.t_("вкл_"+str(menu.settings_tab)))
	for child: Node in parts.strip.get_children():
		if child is Button and (child.text.strip_edges() == caption or child.text.strip_edges().ends_with("  "+caption)):
			_active_appearance.clear()
			for property: Dictionary in child.get_property_list():
				var key: String = str(property.name)
				if key.begins_with("theme_override") and child.get(key) != null:
					_active_appearance[key] = child.get(key)
			return

func open() -> bool:
	var menu: Node = _menu()
	if menu == null: return false
	if is_instance_valid(owner_mod.chat_ui) and owner_mod.chat_ui.surface.visible: owner_mod.chat_ui.close()
	if menu.has_method("to_open"): menu.to_open()
	else: menu.visible = true
	if menu.settings_tab == TAB and is_instance_valid(panel) and not panel.is_queued_for_deletion(): return true
	if _active_appearance.is_empty():
		menu._settings_screen("game")
		var native_parts: Dictionary = _parts(menu)
		if not native_parts.is_empty(): _remember_active_style(menu,native_parts)
	# Reuse the native settings shell and tab actions. Replace only its page body.
	menu._settings_screen(TAB)
	var parts: Dictionary = _parts(menu)
	if parts.is_empty(): return false
	menu.settings_tab = TAB
	var body: VBoxContainer = parts.body
	for child: Node in body.get_children():
		body.remove_child(child); child.queue_free()
	panel = VBoxContainer.new()
	panel.name = "HarnessSettingsPage"
	panel.add_theme_constant_override("separation",12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_build(menu)
	refresh()
	return true

func _label(menu: Node, text: String) -> Label:
	var label: Label = menu._text(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _build(menu: Node) -> void:
	fields.clear(); _shortcut_buttons.clear(); _shortcut_action = ""
	panel.add_child(preload("res://mods/pax_harness/src/ui/game/tool_catalogue.gd").build(owner_mod))
	var chats_box: VBoxContainer = _section(menu,L.text("Диалог"),"")
	var font := SpinBox.new(); font.min_value = 10; font.max_value = 28; font.step = 1; font.suffix = "px"
	font.value = Preferences.value(owner_mod,"dialog_font_size"); fields.dialog_font_size = font
	_row(menu,chats_box,L.text("Размер шрифта"),L.text("Только сообщения и таблицы диалога; размер элементов интерфейса не меняется."),font)
	font.value_changed.connect(func(value: float): _save_preference("dialog_font_size",int(value)))
	_choice(menu,chats_box,"dialog_display",L.text("Отображение диалога"),L.text("Показ процесса в завершённых ответах. Текущий ход и ошибки остаются видны."),[L.text("Подробно"),L.text("Свёрнуто"),L.text("Только ответы")],["detailed","compact","answers"])
	var technical := CheckButton.new(); technical.button_pressed = Preferences.value(owner_mod,"technical_details"); fields.technical_details = technical
	_row(menu,chats_box,L.text("Технические подробности"),L.text("Разрешает раскрывать параметры и результаты инструментов. Не меняет доступ агента к инструментам."),technical)
	technical.toggled.connect(func(value: bool): _save_preference("technical_details",value))
	_choice(menu,chats_box,"busy_send",L.text("Отправка во время ответа"),L.text("Очередь — после текущего ответа; прерывание — остановить ответ и отправить следующее сообщение; ожидание — сохранить текст в поле ввода. Ctrl+Enter меняет очередь и прерывание местами."),[L.text("В очередь"),L.text("Прервать и отправить"),L.text("Ждать завершения")],["queue","interrupt","wait"])
	_choice(menu,chats_box,"usage_display",L.text("Производительность и токены"),L.text("Подробно — скорость, токены, кэш и контекст; кратко — только токены и контекст; скрыто — без строки статистики."),[L.text("Подробно"),L.text("Кратко"),L.text("Скрыто")],["detailed","basic","hidden"])
	var keys: VBoxContainer = _section(menu,L.text("Горячие клавиши"),L.text("Нажмите сочетание справа, затем новые клавиши. Esc отменяет назначение. Shift+Enter всегда переносит строку."))
	for action: String in Preferences.SHORTCUTS:
		var button: Button = menu._button(Preferences.label(Preferences.shortcut(owner_mod,action)))
		button.pressed.connect(_capture_shortcut.bind(action)); _shortcut_buttons[action] = button
		_row(menu,keys,{"send":L.text("Отправить сообщение"),"new_chat":L.text("Новый чат"),"search":L.text("Поиск чатов"),"stop":L.text("Остановить ответ")}[action],"",button)
	var reset: Button = menu._button(L.text("Сбросить сочетания"))
	reset.pressed.connect(func():
		for action: String in Preferences.SHORTCUTS: owner_mod.set_setting("shortcut_"+action,Preferences.SHORTCUTS[action])
		_refresh_shortcuts())
	keys.add_child(reset)
	feedback = _label(menu,""); keys.add_child(feedback)
	var images_box: VBoxContainer = _section(menu,L.text("Изображения Harness"),"")
	if is_instance_valid(owner_mod._image_generation): images_box.add_child(owner_mod._image_generation.settings_panel())

func _row(menu: Node, box: VBoxContainer, title: String, description: String, control: Control) -> void:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",24); box.add_child(row)
	var text := VBoxContainer.new(); text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(text)
	text.add_child(menu.call("_title",title,14) if menu.has_method("_title") else _label(menu,title))
	if description != "":
		var hint: Label = _label(menu,description); hint.add_theme_font_size_override("font_size",12); text.add_child(hint)
	control.custom_minimum_size.x = 200 if control is OptionButton or control is Button else 90
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(control)

func _choice(menu: Node, box: VBoxContainer, key: String, title: String, description: String, labels: Array, values: Array) -> void:
	var select := OptionButton.new(); select.fit_to_longest_item = false
	for label: String in labels: select.add_item(label)
	select.select(values.find(Preferences.value(owner_mod,key))); fields[key] = select
	select.item_selected.connect(func(index: int): _save_preference(key,values[index]))
	_row(menu,box,title,description,select)

func _save_preference(key: String, value: Variant) -> void:
	owner_mod.set_setting(key,value)
	if is_instance_valid(owner_mod.chat_ui): owner_mod.chat_ui.apply_preferences()

func _capture_shortcut(action: String) -> void:
	_shortcut_action = action; _refresh_shortcuts()
	_shortcut_buttons[action].text = L.text("Нажмите клавиши…")

func _refresh_shortcuts() -> void:
	for action: String in _shortcut_buttons: _shortcut_buttons[action].text = Preferences.label(Preferences.shortcut(owner_mod,action))

func _input(event: InputEvent) -> void:
	if _shortcut_action == "" or not is_instance_valid(panel) or not panel.is_visible_in_tree(): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE: _shortcut_action = ""; _refresh_shortcuts(); return
	if event.keycode in [KEY_CTRL,KEY_SHIFT,KEY_ALT,KEY_META]: return
	var code: int = event.get_keycode_with_modifiers()
	if code == (KEY_MASK_SHIFT|KEY_ENTER) or code == (KEY_MASK_CTRL|KEY_ENTER) or event.keycode == KEY_KP_ENTER:
		feedback.text = L.text("Это сочетание используется для переноса строки или альтернативной отправки."); return
	if _shortcut_action != "send" and not (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):
		feedback.text = L.text("Добавьте Ctrl, Alt или Meta, чтобы не перехватывать набор текста."); return
	for action: String in Preferences.SHORTCUTS:
		if action != _shortcut_action and Preferences.shortcut(owner_mod,action) == code:
			feedback.text = L.text("Это сочетание уже назначено другому действию."); return
	owner_mod.set_setting("shortcut_"+_shortcut_action,code); _shortcut_action = ""
	feedback.text = L.text("Сочетание сохранено."); _refresh_shortcuts()

func _section(menu: Node, title: String, description: String) -> VBoxContainer:
	if menu.has_method("settings_screen"):
		var service: Object = menu.settings_screen()
		if service != null and service.has_method("block"):
			var body: Variant = service.call("block",panel,title,description)
			if body is VBoxContainer: return body
	panel.add_child(_label(menu,title))
	if description != "": panel.add_child(_label(menu,description))
	return panel

func _open_model() -> void:
	var tuning: Node = owner_mod._tuning()
	if tuning != null and tuning.has_method("open_settings"): tuning.open_settings()
	else: owner_mod.ui_tool("ui.open",{"panel":"settings.brain"},{})

func dispose() -> void:
	_disposing = true
	set_process(false)
	var menu: Variant = _menu_ref.get_ref() if _menu_ref != null else null
	if is_instance_valid(menu) and menu.settings_tab == TAB: menu._settings_screen("game")
	if is_instance_valid(tab_button) and not tab_button.is_queued_for_deletion(): tab_button.queue_free()
	tab_button = null
	if is_instance_valid(panel) and not panel.is_queued_for_deletion(): panel.queue_free()
	panel = null
