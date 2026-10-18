extends Node
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## All menu actions bind the clicked chat, independently of the selected chat.
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
const Icons = preload("res://mods/pax_harness/src/ui/components/chat_icons.gd")
var ui: Node
var store: RefCounted
var popup: PopupMenu
var sections_menu: PopupMenu
var copy_menu: PopupMenu
var section_popup: PopupMenu
var form: ConfirmationDialog
var view: Control
var name_field: LineEdit
var _target: String = ""
var _section_target: String = ""
var _form_target: String = ""
var _form_mode: String = ""

func setup(value: Node) -> void:
	ui = value
	store = ui.store
	view = preload("res://mods/pax_harness/src/ui/chat/chat_context_view.gd").new()
	ui.add_child(view)
	view.theme = ui.surface.theme
	popup = _popup("ChatContextMenu")
	sections_menu = PopupMenu.new()
	sections_menu.name = "ChatSectionsMenu"
	copy_menu = PopupMenu.new()
	copy_menu.name = "ChatCopyMenu"
	popup.add_child(sections_menu)
	popup.add_child(copy_menu)
	for submenu: PopupMenu in [sections_menu,copy_menu]:
		submenu.theme = ui.surface.theme
		submenu.add_theme_stylebox_override("panel",Style.box(Color("#202226"),6,Color("#393c43"),8))
		submenu.add_theme_constant_override("v_separation",10)
	popup.id_pressed.connect(_action)
	sections_menu.id_pressed.connect(_move)
	copy_menu.id_pressed.connect(_copy)
	section_popup = _popup("SectionContextMenu")
	section_popup.add_item(L.text("Переименовать раздел"),1)
	section_popup.add_item(L.text("Удалить раздел"),2)
	section_popup.id_pressed.connect(_section_action)
	form = ConfirmationDialog.new()
	form.name = "ChatNameDialog"
	form.theme = ui.surface.theme
	form.cancel_button_text = L.text("Отмена")
	form.exclusive = true
	form.add_theme_stylebox_override("panel",Style.box(Color("#25262a"),8,Color.TRANSPARENT,18))
	var border: StyleBox = form.get_theme_stylebox("embedded_border").duplicate()
	if border is StyleBoxFlat:
		border.bg_color = Color("#25262a")
		border.border_color = Color("#393c43")
	form.add_theme_stylebox_override("embedded_border",border)
	form.add_theme_stylebox_override("embedded_unfocused_border",border)
	form.add_theme_color_override("title_color",Color("#e8e9ed"))
	form.add_theme_font_size_override("title_font_size",18)
	form.add_theme_constant_override("buttons_min_height",34)
	form.add_theme_constant_override("buttons_min_width",100)
	form.add_theme_constant_override("buttons_separation",16)
	name_field = LineEdit.new()
	name_field.name = "SectionOrChatName"
	name_field.max_length = 100
	name_field.custom_minimum_size.x = 400
	name_field.custom_minimum_size.y = 42
	form.add_child(name_field)
	form.register_text_enter(name_field)
	name_field.text_changed.connect(func(text: String): form.get_ok_button().disabled = text.strip_edges().is_empty())
	form.confirmed.connect(_confirm_name)
	ui.add_child(form)
	var confirm: Button = form.get_ok_button()
	confirm.add_theme_stylebox_override("normal",Style.box(Color("#ededf0"),6,Color.TRANSPARENT,10))
	confirm.add_theme_stylebox_override("hover",Style.box(Color.WHITE,6,Color.TRANSPARENT,10))
	confirm.add_theme_stylebox_override("pressed",Style.box(Color("#cdced2"),6,Color.TRANSPARENT,10))
	confirm.add_theme_color_override("font_color",Color("#202125"))
	confirm.add_theme_color_override("font_hover_color",Color("#202125"))
	confirm.add_theme_color_override("font_pressed_color",Color("#202125"))
	var buttons: HBoxContainer = confirm.get_parent()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.move_child(confirm,buttons.get_child_count()-1)

func _popup(node_name: String) -> PopupMenu:
	var result := PopupMenu.new()
	result.name = node_name
	result.theme = ui.surface.theme
	result.add_theme_stylebox_override("panel",Style.box(Color("#202226"),6,Color("#393c43"),12))
	result.add_theme_color_override("font_color",Color("#e8e9ed"))
	result.add_theme_font_size_override("font_size",15)
	result.add_theme_constant_override("v_separation",12)
	ui.add_child(result)
	return result

func _show_at_pointer(menu: PopupMenu) -> void:
	ui.mentions.dismiss()
	var children: Dictionary = {3:[sections_menu,_move],4:[copy_menu,_copy]} if menu == popup else {}
	view.show_menu(menu,_action if menu == popup else _section_action,children,ui.get_viewport().get_mouse_position())

func show_chat(id: String) -> void:
	var chat: Dictionary = store.find(id)
	if chat.is_empty(): return
	_target = id
	popup.clear()
	popup.add_item(L.text("Переименовать"),1,KEY_MASK_CTRL|KEY_MASK_ALT|KEY_R)
	popup.set_item_icon(popup.get_item_index(1),Icons.make("edit",Color("#9ba1ab"),16))
	popup.add_item(L.text("Открепить") if chat.get("pinned",false) else L.text("Закрепить"),2,KEY_MASK_CTRL|KEY_MASK_ALT|KEY_P)
	popup.set_item_icon(popup.get_item_index(2),Icons.make("pin",Color("#9ba1ab"),16))
	sections_menu.clear()
	sections_menu.add_radio_check_item(L.text("Без раздела"),0)
	sections_menu.set_item_checked(0,str(chat.get("section_id","")) == "")
	for section: Dictionary in store.sections:
		var index: int = sections_menu.item_count
		sections_menu.add_radio_check_item(str(section.title),index)
		sections_menu.set_item_metadata(index,str(section.id))
		sections_menu.set_item_checked(index,str(chat.get("section_id","")) == str(section.id))
	sections_menu.add_separator("",9999)
	sections_menu.add_item(L.text("Новый раздел…"),10000)
	popup.add_submenu_node_item(L.text("Раздел"),sections_menu,3)
	popup.set_item_icon(popup.get_item_index(3),Icons.make("section",Color("#9ba1ab"),16))
	copy_menu.clear()
	copy_menu.add_item(L.text("Как текст"),0)
	copy_menu.add_item(L.text("Как Markdown"),1)
	copy_menu.add_item(L.text("Как JSON"),2)
	copy_menu.add_separator("",100)
	copy_menu.add_item(L.text("Последний ответ"),3)
	copy_menu.set_item_disabled(copy_menu.get_item_index(3),store.export_chat(id,"last").is_empty())
	popup.add_submenu_node_item(L.text("Скопировать"),copy_menu,4)
	popup.set_item_icon(popup.get_item_index(4),Icons.make("copy",Color("#9ba1ab"),16))
	popup.add_separator("",9000)
	popup.add_item(L.text("Удалить навсегда"),5)
	popup.set_item_icon(popup.get_item_index(5),Icons.make("trash",Color("#d5979e"),16))
	popup.set_item_modulate(popup.get_item_index(5),Color("#d5979e"))
	popup.set_item_disabled(popup.get_item_index(5),store.running(id))
	_show_at_pointer(popup)

func _action(id: int) -> void:
	match id:
		1: rename_chat(_target)
		2: store.set_pinned(_target,not store.find(_target).get("pinned",false))
		5: ui._ask_delete(_target)

func _move(id: int) -> void:
	if id == 10000:
		_open_form("new_section",_target,L.text("Новый раздел"),"",L.text("Создать раздел"))
		return
	var index: int = sections_menu.get_item_index(id)
	if index < 0: return
	store.move_to_section(_target,"" if id == 0 else str(sections_menu.get_item_metadata(index)))

func _copy(id: int) -> void:
	if id < 0 or id > 3: return
	var text: String = store.export_chat(_target,["text","markdown","json","last"][id])
	if text != "": DisplayServer.clipboard_set(text)

func rename_chat(id: String) -> void:
	var chat: Dictionary = store.find(id)
	if not chat.is_empty(): _open_form("rename_chat",id,L.text("Переименовать чат"),str(chat.title),L.text("Сохранить"))

func _open_form(mode: String, target: String, title: String, text: String, confirm: String) -> void:
	_form_mode = mode
	_form_target = target
	form.title = title
	form.ok_button_text = confirm
	name_field.placeholder_text = L.text("Название раздела") if mode != "rename_chat" else L.text("Название чата")
	name_field.text = text
	form.get_ok_button().disabled = text.strip_edges().is_empty()
	form.popup_centered(Vector2i(520,160))
	name_field.grab_focus()
	name_field.select_all()

func _confirm_name() -> void:
	var value: String = name_field.text.strip_edges()
	if value == "": return
	match _form_mode:
		"rename_chat": store.rename(_form_target,value)
		"new_section": store.create_section(value,_form_target)
		"rename_section": store.rename_section(_form_target,value)

func show_section(id: String) -> void:
	if store.section(id).is_empty(): return
	_section_target = id
	_show_at_pointer(section_popup)

func _section_action(id: int) -> void:
	if id == 1:
		_open_form("rename_section",_section_target,L.text("Переименовать раздел"),str(store.section(_section_target).get("title","")),L.text("Сохранить"))
	elif id == 2: store.remove_section(_section_target)

func handle_key(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo: return false
	if view.visible: return view.handle_key(event)
	if event.keycode == KEY_ESCAPE:
		if form.visible or popup.visible or section_popup.visible:
			dismiss()
			return true
		return false
	if form.visible or ui.delete_dialog.visible or popup.visible: return false
	if event.ctrl_pressed and event.alt_pressed:
		if event.keycode == KEY_R:
			rename_chat(store.selected)
			return true
		if event.keycode == KEY_P:
			store.set_pinned(store.selected,not store.current().get("pinned",false))
			return true
	return false

func dismiss() -> void:
	view.dismiss()
	for window: Window in [popup,sections_menu,copy_menu,section_popup,form]: window.hide()
