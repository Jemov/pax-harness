extends CanvasLayer
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## In-game session browser and event-driven tool disclosures.
const Preferences = preload("res://mods/pax_harness/src/ui/chat/chat_preferences.gd")
const Markdown = preload("res://mods/pax_harness/src/ui/markdown/chat_markdown.gd")
const Metrics = preload("res://mods/pax_harness/src/chat/chat_metrics.gd")
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
const WorkspaceUI = preload("res://mods/pax_harness/src/ui/chat/workspace_ui.gd")
const Layout = preload("res://mods/pax_harness/src/ui/chat/chat_layout.gd")
const Icons = preload("res://mods/pax_harness/src/ui/components/chat_icons.gd")
const BG := Color("#18191c")
const SIDE := Color("#111215")
const TEXT := Color("#d0d1d3")
const QUIET := Color("#949ba7")
const ACCENT := Color("#8fcaff")
const TOOL_LABELS = preload("res://mods/pax_harness/src/runtime/tools/tool_labels.gd").LABELS
var owner_mod: Node
var store: RefCounted
var main: Node
var native: Control
var surface: PanelContainer
var backdrop: ColorRect
var sidebar: VBoxContainer
var search: LineEdit
var title_group: Control
var title_label: Label
var title_edit_button: Button
var _editing_title := false
var _title_edit_id := ""
var composer_input: PanelContainer
var title_field: LineEdit
var image_attachments: Node
var feed: VBoxContainer
var scroll: ScrollContainer
var input: TextEdit
var send_button: Button
var stop_button: Button
var mic_button: Button
var status: Label
var delete_dialog: ConfirmationDialog
var _delete_id: String = ""
var chat_menu: Node
var mentions: Node
var _pending := false
var _guard := false
var _active_id: String = ""
var _message_views: Dictionary = {}
var _prefix_state: Array = []
var _expanded: Dictionary = {}
var _visible_count := 60
var _keep_position := false
var _timer := 0.0
var _fit_pending := false
var _stat_buttons: Array = []
var _stat_panel: PanelContainer
var _stat_body: VBoxContainer
var _stat_pinned: String = ""
var _stat_index := 0
var _stat_fit_pending := false
var _scroll_revision := 0
var window_manager: Node
var sidebar_resize: Control
var agent_name: Control
var scroll_motion: Node

func setup(mod: Node, game_main: Node) -> void:
	owner_mod = mod
	set_meta("mod_i18n_scope","pax_harness")
	store = mod.chat_store
	main = game_main
	native = main.ui.assistant_window
	name = "PromptLabChats"
	layer = 90
	main.add_child(self)
	backdrop = ColorRect.new()
	backdrop.name = "ChatBackdrop"
	backdrop.color = Color(0,0,0,0.42)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	surface = PanelContainer.new()
	surface.name = "ChatWorkspace"
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	surface.theme = _theme()
	surface.add_theme_stylebox_override("panel",Style.box(BG,6,Color.TRANSPARENT,0))
	add_child(surface)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",0)
	surface.add_child(row)
	var side := PanelContainer.new()
	side.name = "ChatSidebar"
	side.custom_minimum_size.x = 230
	var sidebar_style: StyleBoxFlat = Style.box(SIDE,6,Color.TRANSPARENT,16)
	sidebar_style.corner_radius_top_right = 0
	sidebar_style.corner_radius_bottom_right = 0
	side.add_theme_stylebox_override("panel",sidebar_style)
	row.add_child(side)
	var side_column := VBoxContainer.new()
	side_column.add_theme_constant_override("separation",14)
	side.add_child(side_column)
	# Set up after the header so both pencils share the same styling.
	agent_name = preload("res://mods/pax_harness/src/ui/chat/chat_agent_name.gd").new()
	side_column.add_child(agent_name)
	var new_chat := _button(L.text("＋  Новый чат"),func(): owner_mod.chat_new())
	new_chat.name = "NewChat"
	side_column.add_child(new_chat)
	search = LineEdit.new()
	search.name = "SearchChats"
	search.placeholder_text = L.text("Найти чат")
	search.text_changed.connect(func(_text: String): _render_sidebar())
	side_column.add_child(search)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_column.add_child(list_scroll)
	sidebar = VBoxContainer.new()
	sidebar.name = "Sessions"
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation",6)
	list_scroll.add_child(sidebar)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",0)
	row.add_child(body)
	var detach: Button = Layout.sidebar_footer(self,side_column)
	Layout.header(self,body,detach)
	var instructions: Node = surface.find_child("Instructions",true,false)
	if instructions != null:
		var images_button: Button = Layout.icon_button(self,"image",_open_image_settings,L.text("Генератор изображений"))
		images_button.name = "ImageGenerationSettings"; instructions.get_parent().add_child(images_button)
		instructions.get_parent().move_child(images_button,instructions.get_index()+1)
	agent_name.setup(self)
	scroll = ScrollContainer.new()
	scroll.name = "ChatTranscript"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var transcript_margin := MarginContainer.new()
	transcript_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge: String in ["left","right","top","bottom"]: transcript_margin.add_theme_constant_override("margin_"+edge,24)
	scroll.add_child(transcript_margin)
	feed = VBoxContainer.new()
	feed.name = "Messages"
	feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed.add_theme_constant_override("separation",22)
	transcript_margin.add_child(feed)
	Layout.composer(self,body)
	sidebar_resize = preload("res://mods/pax_harness/src/ui/chat/chat_sidebar_resize.gd").new()
	row.add_child(sidebar_resize)
	row.move_child(sidebar_resize,1)
	sidebar_resize.setup(self,side)
	_stat_panel = PanelContainer.new()
	_stat_panel.name = "StatisticsDetails"
	_stat_panel.theme = surface.theme
	_stat_panel.add_theme_stylebox_override("panel",Style.box(Color("#2a2d33"),6,Color("#494d55"),16))
	_stat_panel.custom_minimum_size.x = 430
	add_child(_stat_panel)
	_stat_body = VBoxContainer.new()
	_stat_body.add_theme_constant_override("separation",12)
	_stat_panel.add_child(_stat_body)
	_stat_panel.minimum_size_changed.connect(_schedule_stat_fit)
	_stat_panel.hide()
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = L.text("Удалить чат?")
	delete_dialog.dialog_text = L.text("Переписка этого чата будет удалена из партии.")
	delete_dialog.get_label().set_meta("mod_user_text",true)
	delete_dialog.ok_button_text = L.text("Удалить")
	delete_dialog.cancel_button_text = L.text("Отмена")
	delete_dialog.confirmed.connect(func(): owner_mod.chat_delete(_delete_id))
	add_child(delete_dialog)
	chat_menu = preload("res://mods/pax_harness/src/ui/chat/chat_menu.gd").new()
	add_child(chat_menu)
	chat_menu.setup(self)
	scroll_motion = preload("res://mods/pax_harness/src/ui/chat/chat_scroll_motion.gd").new()
	add_child(scroll_motion)
	scroll_motion.setup(self,[scroll,list_scroll])
	store.changed.connect(_schedule_refresh)
	native.visibility_changed.connect(_native_visibility)
	surface.minimum_size_changed.connect(_schedule_fit)
	_fit()
	surface.hide()
	backdrop.hide()
	if native.visible: _native_visibility()

func _theme() -> Theme:
	var result: Theme = Style.theme()
	result.default_font_size = 15
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans","Segoe UI","Arial"])
	result.default_font = font
	result.set_stylebox("panel","TooltipPanel",Style.box(Color("#252a33"),6,Color("#454e60"),10))
	result.set_font("font","TooltipLabel",font)
	result.set_font_size("font_size","TooltipLabel",13)
	result.set_color("font_color","TooltipLabel",Color("#e4ecfa"))
	var separator := StyleBoxLine.new()
	separator.color = Color("#35383f")
	separator.thickness = 1
	result.set_stylebox("separator","HSeparator",separator)
	result.set_constant("separation","HSeparator",1)
	for type: String in ["Button","Label","LineEdit","TextEdit","RichTextLabel"]: result.set_color("font_color",type,TEXT)
	for type: String in ["Button","LineEdit","TextEdit"]:
		result.set_stylebox("normal",type,Style.box(Color("#202226"),6,Color("#35383f"),10))
		result.set_stylebox("focus",type,Style.box(Color("#202226"),6,Color("#6699bf"),10))
		result.set_color("caret_color",type,ACCENT)
	result.set_color("font_pressed_color","Button",ACCENT)
	result.set_stylebox("scroll","VScrollBar",Style.box(BG,4,Color.TRANSPARENT,2))
	return result

func _open_image_settings() -> void:
	if get_node_or_null("ImageGenerationDialog") != null: return
	preload("res://mods/pax_harness/src/ui/images/image_generation_dialog.gd").new().setup(self)

func _label(text: String, size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	return node

func _button(text: String, action: Callable) -> Button:
	var button := preload("res://mods/pax_harness/src/ui/components/chat_button.gd").new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.pressed.connect(action)
	return button

func _stat_label(text: String, size: int, color: Color) -> Label:
	var node: Label = _label(text,size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	return node

func _rich(text: String, markdown: bool = true) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.set_meta("mod_user_text",true)
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.selection_enabled = true
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("normal_font_size",int(Preferences.value(owner_mod,"dialog_font_size")))
	node.add_theme_constant_override("line_separation",5)
	node.text = Markdown.render(text) if markdown else Markdown.escape(text)
	node.meta_clicked.connect(func(value: Variant):
		if str(value).begins_with("https://"): owner_mod.open_link(str(value)))
	return node

func _schedule_fit() -> void:
	if _fit_pending: return
	_fit_pending = true
	_fit.call_deferred()

func _fit() -> void:
	_fit_pending = false
	if window_manager != null: window_manager.fit()
	_layout_title()

func _append_markdown(parent: Control, text: String, events: Array = []) -> void:
	var content := preload("res://mods/pax_harness/src/ui/markdown/chat_markdown_view.gd").new()
	content.add_theme_constant_override("separation",9)
	parent.add_child(content)
	content.update_content(self,text,events)

func _chart_map_target(region: Dictionary) -> Dictionary:
	if not owner_mod._game_available(): return {}
	return preload("res://mods/pax_harness/src/visualization/controls/chart_navigation.gd").resolve(owner_mod._game,region)

func _chart_go_to_province(region: Dictionary) -> void:
	var target: Dictionary = _chart_map_target(region)
	if target.is_empty(): return
	var main: Node = owner_mod._game.scene_root()
	close()
	if target.body==owner_mod._game.home_body(): main.army_map_view().show_province_on_map(int(target.id))
	else:
		main.galaxy_view().open_body_map(Array(owner_mod._game.body_names()).find(target.body))
		main.political_map.навести_на(owner_mod._game._prov(target.body).label_point(int(target.id)),2.0)
	main.get_window().grab_focus()

func _native_visibility() -> void:
	if _guard or not is_instance_valid(native) or not native.visible: return
	_guard = true
	native.hide()
	_guard = false
	open()

func open() -> void:
	backdrop.show()
	surface.show()
	_fit()
	_refresh()
	input.grab_focus()
	window_manager.show_workspace()

func close() -> void:
	var image_dialog: Node = get_node_or_null("ImageGenerationDialog")
	if image_dialog != null: image_dialog.hide(); image_dialog.queue_free()
	scroll_motion.cancel()
	window_manager.hide_workspace()
	var instructions: Control = get_node_or_null("InstructionsDialog")
	if instructions != null: instructions.dismiss()
	mentions.dismiss()
	chat_menu.dismiss()
	delete_dialog.hide()
	surface.hide()
	backdrop.hide()
	_stat_panel.hide()
	_stat_pinned = ""

func _input(event: InputEvent) -> void:
	if agent_name != null and agent_name.editing and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		agent_name.cancel()
		get_viewport().set_input_as_handled()
		return
	if _editing_title and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_title_key(event)
		get_viewport().set_input_as_handled()
		return
	var instructions: Control = get_node_or_null("InstructionsDialog")
	if instructions != null:
		instructions.handle_key(event)
		return
	if is_instance_valid(surface) and surface.visible and mentions.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(surface) and surface.visible and chat_menu.handle_key(event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(surface) and surface.visible and event is InputEventKey and event.pressed and not event.echo:
		for action: String in ["new_chat","search","stop"]:
			if Preferences.matches(owner_mod,action,event):
				if action == "new_chat": owner_mod.chat_new()
				elif action == "search": search.grab_focus()
				else: owner_mod.chat_stop()
				get_viewport().set_input_as_handled(); return
	if surface != null and surface.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _stat_panel.visible:
			_stat_panel.hide()
			_stat_pinned = ""
		else: close()
		get_viewport().set_input_as_handled()

func _input_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var alternate: bool = event.keycode in [KEY_ENTER,KEY_KP_ENTER] and (event.ctrl_pressed or event.meta_pressed) and not event.shift_pressed and not event.alt_pressed
	if alternate or Preferences.matches(owner_mod,"send",event):
		input.accept_event(); _send(alternate)

func _send(alternate: bool = false) -> void:
	var text: String = input.text.strip_edges()
	if text.is_empty() and (image_attachments==null or image_attachments.images().is_empty()): return
	var accepted := false
	if owner_mod.chat_busy():
		var mode: String = str(Preferences.value(owner_mod,"busy_send"))
		if alternate: mode = "interrupt" if mode == "queue" else "queue"
		if mode == "wait" or not owner_mod.has_method("chat_enqueue"): return
		accepted = owner_mod.chat_enqueue(text,mentions.references(),image_attachments.images())
		if accepted and mode == "interrupt": owner_mod.chat_stop()
	else:
		accepted = owner_mod.chat_send_with_refs(text,mentions.references(),image_attachments.images()) if owner_mod.has_method("chat_send_with_refs") else owner_mod.chat_send(text)
	if accepted:
		input.text = ""; mentions.sync(); _update_status()

func apply_preferences() -> void:
	# Update display controls without recreating chart instances or losing filters.
	for view: Variant in _message_views.values():
		if is_instance_valid(view): view.apply_preferences(self)
	_keep_position = true; _schedule_refresh()

func _layout_title() -> void:
	if not is_instance_valid(title_group) or not is_instance_valid(title_label): return
	var height: float = title_group.size.y
	var desired: float = title_label.get_theme_font("font").get_string_size(title_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title_label.get_theme_font_size("font_size")).x
	var width: float = minf(desired,maxf(0,title_group.size.x-34))
	title_label.position = Vector2(0,0)
	title_label.size = Vector2(width,height)
	title_edit_button.position = Vector2(width+7,(height-24)/2)
	title_edit_button.size = Vector2(24,24)
	title_field.position = Vector2.ZERO
	title_field.size = title_group.size

func _begin_title() -> void:
	if store.current().is_empty(): return
	_editing_title = true
	_title_edit_id = store.selected
	title_field.text = str(store.current().title)
	title_label.hide()
	title_edit_button.hide()
	title_field.show()
	title_field.grab_focus()
	title_field.select_all()

func _title_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_editing_title = false
		title_field.hide()
		title_label.show()
		title_edit_button.show()
		title_field.accept_event()

func _rename() -> void:
	if not _editing_title: return
	_editing_title = false
	var value: String = title_field.text.strip_edges()
	if value != "" and not store.find(_title_edit_id).is_empty(): store.rename(_title_edit_id,value)
	title_field.hide()
	title_label.show()
	title_edit_button.show()
	title_label.text = str(store.current().get("title",L.text("Новый чат")))
	_layout_title()

func _ask_delete(chat_id: String = "") -> void:
	_delete_id = store.selected if chat_id == "" else chat_id
	if store.find(_delete_id).is_empty(): return
	if store.running(_delete_id):
		status.text = L.text("Сначала дождитесь ответа или нажмите «Стоп».")
		return
	L.bind(delete_dialog,"dialog_text",["Удалить чат «",{"value":store.find(_delete_id).title},"» навсегда?"])
	delete_dialog.popup_centered()

func _schedule_refresh() -> void:
	if _pending: return
	_pending = true
	_refresh.call_deferred()

func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _render_sidebar() -> void:
	_clear(sidebar)
	for group: Dictionary in store.sidebar_groups(search.text):
		if group.title != "":
			if str(group.id).begins_with("section:"):
				var header := _button(("▸  " if group.collapsed else "▾  ")+str(group.title),store.toggle_section.bind(str(group.id)))
				header.name = "Section_"+str(group.id).replace(":","_")
				header.alignment = HORIZONTAL_ALIGNMENT_LEFT
				header.set_meta("mod_user_text",true)
				header.clip_text = true
				header.add_theme_color_override("font_color",QUIET)
				header.gui_input.connect(_section_mouse.bind(str(group.id),header))
				sidebar.add_child(header)
			else: sidebar.add_child(_label(str(group.title),13,QUIET))
		if group.collapsed: continue
		for chat: Dictionary in group.items:
			var button := _button(("⌖  " if chat.get("pinned",false) else "")+str(chat.title)+( "  ◌" if store.running(str(chat.id)) else ""),owner_mod.chat_select.bind(str(chat.id)))
			button.set_meta("mod_user_text",true)
			button.name = "Session_"+str(chat.id).replace(":","_")
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.clip_text = true
			button.set_meta("mod_user_tooltip",true)
			button.tooltip_text = store.title_tooltip(chat)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_stylebox_override("normal",Style.box(Color("#282c33") if chat.id == store.selected else SIDE,6,Color.TRANSPARENT,10))
			button.gui_input.connect(_chat_mouse.bind(str(chat.id),button))
			button.set_drag_forwarding(mentions.drag_data.bind(str(chat.id),button),Callable(),Callable())
			sidebar.add_child(button)

func _chat_mouse(event: InputEvent, id: String, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		button.accept_event()
		chat_menu.show_chat(id)

func _section_mouse(event: InputEvent, id: String, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		button.accept_event()
		chat_menu.show_section(id)

func _refresh() -> void:
	_pending = false
	if not is_instance_valid(surface) or not surface.visible: return
	var old_position: int = scroll.scroll_vertical
	var follow: bool = scroll.get_v_scroll_bar().value >= scroll.get_v_scroll_bar().max_value-scroll.size.y-60 and not _keep_position
	_keep_position = false
	var switched: bool = _active_id != store.selected
	if switched:
		_clear(feed)
		_message_views.clear(); _prefix_state = []
		if _editing_title: _rename()
		mentions.dismiss()
		mentions._dismissed = ""
		_active_id = store.selected
		_visible_count = 60
		input.text = str(store.current().get("draft",""))
		follow = true
	if not _editing_title: title_field.text = str(store.current().get("title",L.text("Новый чат")))
	title_label.text = str(store.current().get("title",L.text("Новый чат")))
	_layout_title()
	mentions.sync()
	_render_sidebar()
	_render_transcript(store.current().get("messages",[]))
	_update_status()
	_scroll_revision += 1
	_restore_scroll.call_deferred(follow,old_position,_scroll_revision,scroll_motion.revision)

func _restore_scroll(follow: bool, position: int, revision: int, interaction_revision: int) -> void:
	# Container layout and wrapped text settle after the deferred refresh.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(scroll) or revision != _scroll_revision: return
	if interaction_revision != scroll_motion.revision or scroll_motion.is_animating(scroll): return
	if follow: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	else: scroll.scroll_vertical = position

func _render_transcript(messages: Array) -> void:
	var rows: Array = messages.slice(maxi(0,messages.size()-_visible_count))
	var ids: Array = rows.map(func(message: Dictionary): return str(message.id))
	for id: String in _message_views.keys():
		if id in ids: continue
		var view: Node = _message_views[id]
		if is_instance_valid(view): feed.remove_child(view); view.queue_free()
		_message_views.erase(id)
	# Keep the plan/header layout stable while only answer text is changing.
	var state: Array = [store.current().get("plan",{}),_expanded.get("plan:"+store.selected,false),messages.is_empty(),messages.size() > _visible_count]
	if state != _prefix_state:
		_prefix_state = state.duplicate(true)
		for child: Node in feed.get_children():
			if not child.has_meta("transcript_message"):
				feed.remove_child(child); child.queue_free()
		WorkspaceUI.render(self)
		if messages.is_empty():
			feed.add_child(_label(L.text("Чем помочь?"),26,TEXT))
			feed.add_child(_label(L.text("Обсудите планы, проверьте положение страны или дайте поручение.\nЗдесь будут видны шаги помощника и результаты его инструментов."),15,QUIET))
		if messages.size() > _visible_count:
			feed.add_child(_button(L.text("Показать предыдущие сообщения"),func():
				_visible_count += 60
				_keep_position = true
				_schedule_refresh()))
	var prefix: Array = feed.get_children().filter(func(child: Node): return not child.has_meta("transcript_message"))
	for index: int in prefix.size():
		if prefix[index].get_index() != index: feed.move_child(prefix[index],index)
	for index: int in rows.size():
		var view: Control = _render_message(rows[index])
		if view.get_index() != prefix.size()+index: feed.move_child(view,prefix.size()+index)

func _render_message(message: Dictionary) -> Control:
	var id: String = str(message.id)
	if not is_instance_valid(_message_views.get(id)):
		var view := preload("res://mods/pax_harness/src/ui/chat/chat_message_view.gd").new()
		view.name = "Message_"+id.replace(":","_")
		view.set_meta("transcript_message",id)
		feed.add_child(view); _message_views[id] = view
	var view: Control = _message_views[id]
	view.update_message(self,message)
	var gallery: Node = view.get_node_or_null("GeneratedImages")
	if gallery == null:
		gallery = preload("res://mods/pax_harness/src/ui/images/generated_image_gallery.gd").new(); gallery.name = "GeneratedImages"; view.add_child(gallery)
	var generator: Variant = owner_mod.get("_image_generation")
	gallery.update_images(generator if generator is Node and is_instance_valid(generator) else null,Markdown.generated_images(message.get("events",[])) if message.get("role") == "assistant" else [])
	var screens: Node=view.get_node_or_null("ScreenImages")
	if screens==null:
		screens=preload("res://mods/pax_harness/src/ui/images/screen_image_gallery.gd").new();screens.name="ScreenImages";view.add_child(screens)
	screens.update_images(self,message.get("events",[]) if message.get("role")=="assistant" else [])
	return view

func _toggle(key: String) -> void:
	_expanded[key] = not _expanded.get(key,false)
	_keep_position = true
	_schedule_refresh()

func _render_events(column: VBoxContainer, message: Dictionary) -> void:
	var key: String = str(message.id)
	var running: bool = message.get("status") == "running"
	var mode: String = str(Preferences.value(owner_mod,"dialog_display"))
	if mode == "answers" and not running and not message.get("events",[]).any(func(event: Dictionary): return event.get("status") == "failed" or not event.get("errors",[]).is_empty()): return
	var expanded: bool = _expanded.get(key,running or mode == "detailed")
	var events: Array = message.get("events",[])
	var tools: int = events.filter(func(e: Dictionary): return e.kind == "tool").size()
	var elapsed: int = int(message.get("elapsed_ms",0))
	var label: String = L.text("Выполняется") if message.get("status") == "running" else (L.text("Выполнено") if message.get("status") == "complete" else L.text("Прервано"))
	var button := _button(("⌄  " if expanded else "›  ")+label+L.text(" · инструментов: ")+str(tools)+( " · "+_duration(elapsed) if elapsed > 0 else ""),_toggle.bind(key))
	button.name = "Steps_"+key.replace(":","_")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color",QUIET)
	button.add_theme_stylebox_override("normal",Style.box(Color.TRANSPARENT,0,Color.TRANSPARENT,4))
	column.add_child(button)
	if not expanded: return
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation",5)
	column.add_child(group)
	for event: Dictionary in events:
		if event.kind == "note": _append_markdown(group,str(event.text))
		elif event.kind == "step":
			group.add_child(_label(("◌  " if event.status == "running" else "·  ")+L.text("Запрос к модели №")+str(event.round)+( " · "+_duration(int(event.elapsed_ms)) if event.status != "running" else (L.text(" · получаю ответ…") if message.has("stream") else L.text(" · ожидаю ответ…"))),13,QUIET))
		elif event.kind == "tool": _render_tool(group,key,event)

func _render_tool(group: VBoxContainer, message_id: String, event: Dictionary) -> void:
	var technical: bool = bool(Preferences.value(owner_mod,"technical_details"))
	var key: String = message_id+":"+str(event.id)
	var state: String = str(event.get("status","running"))
	var icon: String = "◌" if state == "running" else "✕" if state in ["failed","interrupted"] else "↗" if state in ["submitted","dispatched"] else "✓"
	var caption: String = L.text(TOOL_LABELS.get(str(event.name),str(event.name)))
	var detail: String = L.text("ожидаю") if state == "running" else L.text("ошибка") if state == "failed" else L.text("отправлено, ожидает исполнения") if state == "submitted" else L.text("прервано") if state == "interrupted" else _tool_summary(event)
	if state=="dispatched": detail=L.text("Действие отправлено; результат не проверен")
	var button := _button(icon+"  "+caption+"  ·  "+detail+("  ⌄" if _expanded.get(key,false) else "  ›"),_toggle.bind(key))
	button.disabled = not technical
	button.name = "Tool_"+str(event.id).replace(":","_")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = str(event.name)
	button.add_theme_font_size_override("font_size",13)
	button.add_theme_color_override("font_color",Color("#ed9292") if state == "failed" else QUIET)
	button.add_theme_stylebox_override("normal",Style.box(Color.TRANSPARENT,0,Color.TRANSPARENT,5))
	group.add_child(button)
	if str(event.name)=="creation.propose" and state=="complete" and is_instance_valid(owner_mod.get("_creations")):
		group.add_child(_button(L.text("Рассмотреть проект"),owner_mod._creations.open_review))
	if not technical or not _expanded.get(key,false): return
	var details := TextEdit.new()
	details.name = "ToolDetails"
	details.editable = false
	details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	details.custom_minimum_size.y = 230
	details.add_theme_font_size_override("font_size",12)
	var output: String = JSON.stringify(event.get("result",{}),"  ")
	details.text = L.text("Инструмент: ")+str(event.name)+L.text("\n\nПараметры:\n")+JSON.stringify(event.get("arguments",{}),"  ")+L.text("\n\nРезультат:\n")+output.left(32000)
	if output.length() > 32000: details.text += L.text("\n\n[Показан фрагмент. Полный результат сохранён в этом чате.]")
	if not event.get("errors",[]).is_empty(): details.text += L.text("\n\nОшибки:\n")+JSON.stringify(event.errors)
	group.add_child(details)

func _tool_summary(event: Dictionary) -> String:
	var result: Variant = event.get("result",{})
	if result is Dictionary:
		if result.has("total") and result.has("returned"): return L.text("найдено ")+str(result.total)+L.text(", показано ")+str(result.returned)
		if event.name == "money.read": return L.text("в казне ")+str(result.get("amount","—"))
		if event.name == "orders.read": return L.text("приказов: ")+str(result.get("queue",[]).size())
	return L.text("готово")

func _duration(milliseconds: int) -> String:
	if milliseconds < 1000: return str(milliseconds)+L.text(" мс")
	if milliseconds < 60000: return L.text("%.1f с") % (milliseconds/1000.0)
	return L.text("%d мин %d с") % [milliseconds/60000,(milliseconds/1000)%60]

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= 0.5 and surface != null and surface.visible:
		_timer = 0.0
		_update_status()

func _update_send_state() -> void:
	send_button.disabled = (owner_mod.chat_busy() and (Preferences.value(owner_mod,"busy_send") == "wait" or not owner_mod.has_method("chat_enqueue"))) or store.current().is_empty() or (input.text.strip_edges().is_empty() and (image_attachments==null or image_attachments.images().is_empty()))

func _update_status() -> void:
	var busy: bool = owner_mod.chat_busy()
	_update_send_state()
	send_button.visible = not busy or Preferences.value(owner_mod,"busy_send") != "wait"
	send_button.tooltip_text = L.text("В очередь") if busy and Preferences.value(owner_mod,"busy_send") == "queue" else L.text("Прервать и отправить") if busy else L.text("Отправить")
	stop_button.visible = busy
	status.text = agent_name.display_name+L.text(" работает…") if busy else ""
	status.visible = busy
	if native.mic_button != null:
		mic_button.icon = Icons.make("stop" if native.mic_button.button_pressed else "mic",Color("#d5979e") if native.mic_button.button_pressed else QUIET)
		mic_button.disabled = native.mic_button.disabled or busy
	_update_statistics()

func _update_statistics() -> void:
	if _stat_buttons.is_empty(): return
	var mode: String = str(Preferences.value(owner_mod,"usage_display"))
	_stat_buttons[0].get_parent().visible = mode != "hidden"
	_stat_buttons[0].visible = mode == "detailed"
	if mode == "hidden": _stat_panel.hide(); _stat_pinned = ""; return
	var stats: Dictionary = Metrics.summarize(store.current())
	_stat_buttons[0].text = L.text("Ходов: %d · шагов: %d") % [stats.turns,stats.steps]
	if stats.tps > 0: _stat_buttons[0].text += L.text(" · ≈%.0f ток/с") % stats.tps
	_stat_buttons[1].text = ""+Metrics.compact(int(stats.total))+L.text(" ток") if stats.usage_requests > 0 else L.text("Токены: нет данных")
	if stats.cache_known and mode == "detailed": _stat_buttons[1].text += L.text(" · Попадание в кэш %.0f%%") % stats.cache_percent
	var last: Dictionary = stats.last
	var limit: int = int(last.get("context_limit",0))
	var used: int = int(last.get("tokens",{}).get("input",0))
	_stat_buttons[2].text = "%.1f%%" % (100.0*used/limit) if limit > 0 and last.get("tokens",{}).get("known",false) else L.text("Контекст: —")
	_stat_buttons[0].tooltip_text = L.text("Статистика выбранного чата. Нажмите для подробностей.")
	if str(last.get("model","")) != "": _stat_buttons[0].tooltip_text += L.text("\nПоследняя модель запроса: ")+str(last.model)
	_stat_buttons[1].tooltip_text = L.text("Фактические токены и кэш из ответов API. Нажмите для подробностей.")
	_stat_buttons[2].tooltip_text = L.text("Использование контекста последнего завершённого запроса.")

func _pin_stat(kind: String) -> void:
	if _stat_pinned == kind:
		_stat_pinned = ""
		_stat_panel.hide()
	else:
		_stat_pinned = kind
		_show_stat(kind)

func _stat_mouse_exit() -> void:
	if _stat_pinned == "": _stat_panel.hide()

func _show_stat(kind: String) -> void:
	if not surface.visible: return
	if _stat_pinned != "" and _stat_pinned != kind: return
	var stats: Dictionary = Metrics.summarize(store.current())
	_stat_index = ["session","tokens","context"].find(kind)
	_clear(_stat_body)
	var rows: Array = []
	var index: int = _stat_index
	if kind == "session":
		_stat_body.add_child(_stat_label(L.text("◴  Статистика сессии"),16,TEXT))
		rows = [[L.text("Время LLM"),_duration(int(stats.llm_ms))],[L.text("Время инструментов"),_duration(int(stats.tool_ms))],
			[L.text("Токенов в секунду (TPS)"),L.text("≈%.1f ток/с") % stats.tps if stats.tps > 0 else "—"]]
		if str(stats.last.get("model","")) != "": rows.append([L.text("Модель последнего запроса"),str(stats.last.model)])
		if str(stats.last.get("provider_host","")) != "": rows.append([L.text("Провайдер запроса"),str(stats.last.provider_host)])
	elif kind == "tokens":
		var header := HBoxContainer.new()
		header.add_child(_stat_label(L.text("▣  Использование токенов"),16,TEXT))
		var total: Label = _stat_label(Metrics.exact(int(stats.total))+L.text(" ток") if stats.usage_requests > 0 else "—",14,TEXT)
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(total)
		_stat_body.add_child(header)
		if stats.usage_requests > 0:
			rows = [[L.text("Попадание в кэш"),"%.0f%%" % stats.cache_percent if stats.cache_known else "—"],
				[L.text("Некэшированный ввод"),Metrics.exact(int(stats.uncached))+L.text(" ток") if stats.cache_known else "—"],[L.text("Кэшированный ввод"),Metrics.exact(int(stats.cached))+L.text(" ток") if stats.cache_known else "—"],
				[L.text("Вывод"),Metrics.exact(int(stats.output))+L.text(" ток")]]
		else: rows = [[L.text("Попадание в кэш"),"—"],[L.text("Некэшированный ввод"),"—"],[L.text("Кэшированный ввод"),"—"],[L.text("Вывод"),"—"]]
	else:
		var last: Dictionary = stats.last
		var used: int = int(last.get("tokens",{}).get("input",0))
		var limit: int = int(last.get("context_limit",0))
		var known: bool = last.get("tokens",{}).get("known",false)
		_stat_body.add_child(_stat_label(L.text("◔  Использовано контекста: ")+("%.1f%%  %s / %s" % [100.0*used/limit,Metrics.compact(used),Metrics.compact(limit)] if limit > 0 and known else L.text("нет данных")),15,TEXT))
		var progress := ProgressBar.new()
		progress.custom_minimum_size.y = 6
		progress.show_percentage = false
		progress.value = 100.0*used/limit if limit > 0 else 0.0
		progress.add_theme_stylebox_override("fill",Style.box(Color("#6f9de8"),2,Color.TRANSPARENT,0))
		progress.add_theme_stylebox_override("background",Style.box(Color("#41454d"),2,Color.TRANSPARENT,0))
		_stat_body.add_child(progress)
		var parts: Dictionary = Metrics.context_parts(last)
		rows = [[L.text("Системный промпт"),"≈"+Metrics.compact(int(parts.system))],[L.text("Определения инструментов"),"≈"+Metrics.compact(int(parts.tools))],[L.text("Сообщения"),"≈"+Metrics.compact(int(parts.messages))]]
		if not known:
			for row: Array in rows: row[1] = "—"
	_stat_body.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",24)
	grid.add_theme_constant_override("v_separation",8)
	_stat_body.add_child(grid)
	for row: Array in rows:
		if kind == "context":
			var label_row := HBoxContainer.new()
			var chip := _stat_label("■",12,[Color("#acafb8"),Color("#b69cf4"),Color("#6197ed")][rows.find(row)])
			chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			label_row.add_child(chip)
			label_row.add_child(_stat_label(str(row[0]),13,QUIET))
			grid.add_child(label_row)
		else: grid.add_child(_stat_label(str(row[0]),13,QUIET))
		var value: Label = _stat_label(str(row[1]),13,TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if row[0] in [L.text("Модель последнего запроса"),L.text("Провайдер запроса")]:
			value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			value.custom_minimum_size.x = 230
		grid.add_child(value)
	_stat_panel.reset_size()
	_stat_panel.show()
	_position_stat.call_deferred(index)

func _position_stat(index: int) -> void:
	_stat_fit_pending = false
	if index < 0 or index >= _stat_buttons.size(): return
	_stat_index = index
	_stat_panel.reset_size()
	var rect: Rect2 = _stat_buttons[index].get_global_rect()
	var available: Vector2 = get_viewport().get_visible_rect().size
	_stat_panel.position = Vector2(clampf(rect.position.x,12,maxf(12,available.x-_stat_panel.size.x-12)),maxf(12,rect.position.y-_stat_panel.size.y-10))

func _schedule_stat_fit() -> void:
	if _stat_fit_pending: return
	_stat_fit_pending = true
	_position_stat.call_deferred(_stat_index)

func detach() -> void:
	if window_manager != null: window_manager.dispose()
	if is_instance_valid(native) and native.visibility_changed.is_connected(_native_visibility): native.visibility_changed.disconnect(_native_visibility)
	if store != null and store.changed.is_connected(_schedule_refresh): store.changed.disconnect(_schedule_refresh)
	queue_free()
