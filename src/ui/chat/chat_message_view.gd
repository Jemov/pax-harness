extends VBoxContainer
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Message identity and chart controls survive status, usage and stream updates.
const Content = preload("res://mods/pax_harness/src/ui/markdown/chat_markdown_view.gd")
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
const Metrics = preload("res://mods/pax_harness/src/chat/chat_metrics.gd")
const Creations=preload("res://mods/pax_harness/src/creation/chat_creation_view.gd")
var _creations: VBoxContainer
var _header: VBoxContainer
var _events: VBoxContainer
var _content: VBoxContainer
var _header_state: Array = []
var _event_state: Array = []
var _role := ""
var _content_text := ""
var _content_events: Array = []
var _content_initialized := false
var _content_complete := false

func update_message(ui: Node, message: Dictionary) -> void:
	var role: String = str(message.get("role","assistant"))
	if _header == null or role != _role:
		ui._clear(self); _role = role; _header_state = []; _event_state = []
		_content_initialized = false; _content_events = []
		var column: VBoxContainer = self
		add_theme_constant_override("separation",9)
		if role == "user":
			var bubble := PanelContainer.new()
			bubble.add_theme_stylebox_override("panel",Style.box(Color("#25282e"),6,Color.TRANSPARENT,16))
			add_child(bubble); column = VBoxContainer.new(); bubble.add_child(column)
			column.add_theme_constant_override("separation",9)
		_header = VBoxContainer.new(); column.add_child(_header)
		_events = VBoxContainer.new(); column.add_child(_events)
		_content = Content.new(); column.add_child(_content)
		_creations=Creations.new(); column.add_child(_creations)
		_creations.visible=false
		_header.add_theme_constant_override("separation",9)
		_events.add_theme_constant_override("separation",9)
		_content.add_theme_constant_override("separation",9)
	if role == "system":
		_update_summary(ui,message)
		return
	var references: Array = []
	for reference: Dictionary in message.get("references",[]):
		var target: Dictionary = ui.store.find(str(reference.id))
		references.append([reference,target.get("title",reference.get("title",L.text("Удалённый чат"))),target.is_empty()])
	var header: Array = [role,message.get("date",""),ui.agent_name.display_name,references,message.get("origin",{}),message.get("status")]
	if _header_state != header:
		_header_state = header.duplicate(true); ui._clear(_header)
		_header.add_child(ui._label((L.text("Вы") if role == "user" else "✦  "+ui.agent_name.display_name)+"   ·   "+str(message.get("date","")),13,ui.QUIET if role == "user" else ui.ACCENT))
		for reference: Array in references:
			var link: Button = ui._button("@ "+str(reference[1]),ui.owner_mod.chat_select.bind(str(reference[0].id)))
			link.set_meta("mod_user_text",true); link.disabled = reference[2]; link.alignment = HORIZONTAL_ALIGNMENT_LEFT
			link.add_theme_color_override("font_color",ui.ACCENT); _header.add_child(link)
		if not message.get("origin",{}).is_empty(): _header.add_child(ui._label(L.text("Из чата «")+str(message.origin.get("title",""))+"»"+(L.text(" · в очереди") if message.get("status") == "queued" else ""),12,ui.QUIET))
		if role == "user" and message.get("status") == "queued":
			var cancel: Button = ui._button(L.text("В очереди · отменить"),ui.owner_mod.chat_cancel_queued.bind(str(message.id)))
			_header.add_child(cancel)
		elif role == "user" and message.get("status") == "cancelled": _header.add_child(ui._label(L.text("Отправка отменена"),12,ui.QUIET))

	if role=="assistant": _creations.update_message(ui,message)
	var events: Array = [message.get("events",[]),message.get("status"),message.has("stream"),message.get("elapsed_ms",0),ui._expanded]
	if _event_state != events:
		ui._clear(_events)
		if not message.get("events",[]).is_empty() or message.get("status") == "running": ui._render_events(_events,message)
		_event_state = events.duplicate(true)
	_events.visible = _events.get_child_count() > 0
	var text: String = str(message.get("text",""))
	if role == "user":
		if _content.get_child_count() == 0: _content.add_child(ui._rich(text,false))
		elif _content.get_child(0).text != ui.Markdown.escape(text): _content.get_child(0).text = ui.Markdown.escape(text)
		_content.visible = not text.is_empty()
	else:
		if message.get("status") == "running" and str(message.get("stream",{}).get("text","")) != "":
			text += ("\n\n" if text != "" else "")+str(message.stream.text)
		var body_events: Array = message.get("events",[])
		var events_changed: bool = _content_events != body_events
		var complete: bool = message.get("status") != "running"
		if not _content_initialized or _content_text != text or events_changed or _content_complete != complete:
			_content.update_content(ui,text,body_events,complete)
			_content_initialized = true; _content_text = text
			_content_complete = complete
			if events_changed: _content_events = body_events.duplicate(true)

func _update_summary(ui: Node, message: Dictionary) -> void:
	var key: String = str(message.id)+":summary"
	var state: Array = [message,ui._expanded.get(key,false)]
	if _header_state == state: return
	_header_state = state.duplicate(true); ui._clear(_header)
	var caption: String = str(message.get("text",""))
	if message.get("status") == "complete" and message.has("compressed_items"):
		caption = L.text("compact · Сжато элементов истории: %d (токенов: ~%s)") % [int(message.compressed_items),Metrics.exact(int(message.get("compressed_tokens_estimate",0)))]
	var marker: Button = ui._button(("▾  " if state[1] else "▸  ")+caption,ui._toggle.bind(key))
	marker.alignment = HORIZONTAL_ALIGNMENT_LEFT; marker.add_theme_color_override("font_color",ui.QUIET)
	_header.add_child(marker); _events.hide()
	_content.update_content(ui,str(message.get("summary","")) if state[1] else "")

func apply_preferences(ui: Node) -> void:
	_event_state.clear()
	if not is_instance_valid(_content): return
	var size: int = int(ui.Preferences.value(ui.owner_mod,"dialog_font_size"))
	for node: Node in _content.find_children("*","RichTextLabel",true,false): node.add_theme_font_size_override("normal_font_size",size)
	for node: Node in _content.find_children("*","Control",true,false):
		if (node is Label or node is Button) and node.get_meta("mod_user_text",false): node.add_theme_font_size_override("font_size",size)
