extends Node
## A native Settings tab for Harness preferences, independent of model profiles.
const TAB := "pax_harness"
var owner_mod: Node
var tab_button: Button
var panel: VBoxContainer
var name_field: LineEdit
var width_field: SpinBox
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
		tab_button.text = "🛠  Харнес"
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
	var chats_box: VBoxContainer = _section(menu,"Чаты Harness","Подключение и параметры модели находятся в штатной «Тонкой настройке».")
	chats_box.add_child(_label(menu,"Имя агента"))
	name_field = LineEdit.new()
	name_field.name = "HarnessAgentName"
	name_field.max_length = 64
	name_field.text = str(owner_mod.get_setting("agent_display_name","ВИ"))
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chats_box.add_child(name_field)
	chats_box.add_child(_label(menu,"Ширина списка чатов, пикселей"))
	width_field = SpinBox.new()
	width_field.name = "HarnessSidebarWidth"
	width_field.min_value = 180; width_field.max_value = 1200; width_field.step = 1
	width_field.value = float(owner_mod.get_setting("sidebar_width",230.0))
	width_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chats_box.add_child(width_field)
	chats_box.add_child(_label(menu,"На небольшом окне фактическая ширина ограничивается свободным местом для переписки. Разделитель по-прежнему можно перетаскивать мышью."))
	var actions := HFlowContainer.new()
	chats_box.add_child(actions)
	var apply: Button = menu._button("Применить")
	apply.name = "ApplyHarnessSettings"
	apply.pressed.connect(_apply)
	actions.add_child(apply)
	var chats: Button = menu._button("Открыть чаты")
	chats.pressed.connect(func(): menu.close_button(); owner_mod.chat_ui.open())
	actions.add_child(chats)
	var model: Button = menu._button("Тонкая настройка модели")
	model.pressed.connect(_open_model)
	actions.add_child(model)
	feedback = _label(menu,"")
	chats_box.add_child(feedback)
	var images_box: VBoxContainer = _section(menu,"Изображения Harness","")
	if is_instance_valid(owner_mod._image_generation): images_box.add_child(owner_mod._image_generation.settings_panel())

func _section(menu: Node, title: String, description: String) -> VBoxContainer:
	if menu.has_method("settings_screen"):
		var service: Object = menu.settings_screen()
		if service != null and service.has_method("block"):
			var body: Variant = service.call("block",panel,title,description)
			if body is VBoxContainer: return body
	panel.add_child(_label(menu,title))
	if description != "": panel.add_child(_label(menu,description))
	return panel

func _apply() -> void:
	var value: String = name_field.text.replace("\n"," ").replace("\r"," ").replace("\t"," ").strip_edges()
	if value.is_empty(): feedback.text = "Введите имя агента."; return
	owner_mod.set_setting("agent_display_name",value)
	owner_mod.set_setting("sidebar_width",width_field.value)
	var chat: Node = owner_mod.chat_ui
	if is_instance_valid(chat):
		chat.agent_name.field.text = value
		chat.agent_name.editing = true
		chat.agent_name.commit()
		chat.sidebar_resize.preferred_width = width_field.value
		chat.sidebar_resize._fit_width()
	feedback.text = "Настройки Harness сохранены."

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
