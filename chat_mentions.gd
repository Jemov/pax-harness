extends Node
const Style = preload("res://mods/pax_harness/chat_style.gd")
var ui: Node
var store: RefCounted
var editor: TextEdit
var chips: VBoxContainer
var picker: PanelContainer
var choices: VBoxContainer
var drop_target: PanelContainer
var ids: Array = []
var selected: int = 0
var anchor_line: int = 0
var anchor_column: int = 0
var end_column: int = 0
var _pending: bool = false
var _dismissed: String = ""

func setup(value: Node, composer: VBoxContainer) -> void:
	ui = value
	store = ui.store
	editor = ui.input
	chips = VBoxContainer.new()
	chips.name = "AttachedChats"
	chips.add_theme_constant_override("separation",5)
	composer.add_child(chips)
	composer.move_child(chips,editor.get_index())
	chips.hide()
	picker = PanelContainer.new()
	picker.name = "ChatMentionPicker"
	picker.theme = ui.surface.theme
	picker.add_theme_stylebox_override("panel",Style.box(Color("#24262b"),8,Color("#41454d"),8))
	ui.add_child(picker)
	choices = VBoxContainer.new()
	picker.add_child(choices)
	picker.hide()
	drop_target = PanelContainer.new()
	drop_target.name = "ChatDropTarget"
	drop_target.add_theme_stylebox_override("panel",Style.box(Color(0.3,0.55,0.8,0.15),6,Color("#8fcaff"),0))
	drop_target.mouse_filter = Control.MOUSE_FILTER_STOP
	drop_target.set_drag_forwarding(Callable(),can_drop,drop)
	ui.add_child(drop_target)
	drop_target.hide()
	editor.text_changed.connect(schedule)
	editor.caret_changed.connect(schedule)

func sync() -> void:
	ui._clear(chips)
	var chat: Dictionary = store.current()
	for id: String in chat.get("draft_refs",[]):
		var target: Dictionary = store.find(id)
		var row := HBoxContainer.new()
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel",Style.box(Color("#303238"),16,Color("#464950"),5))
		chips.add_child(panel)
		panel.add_child(row)
		var label: Button = ui._button("@ "+str(target.get("title","Удалённый чат")),ui.owner_mod.chat_select.bind(id))
		label.clip_text = true
		label.alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.y = 25
		label.disabled = target.is_empty()
		row.add_child(label)
		var remove: Button = ui._button("×",remove_reference.bind(id))
		remove.custom_minimum_size.y = 25
		row.add_child(remove)
	chips.visible = chips.get_child_count()>0

func add_reference(id: String) -> bool:
	if store.current().is_empty() or store.find(id).is_empty(): return false
	if not store.current().has("draft_refs"): store.current()["draft_refs"] = []
	if id not in store.current().draft_refs: store.current().draft_refs.append(id)
	sync()
	editor.grab_focus()
	return true

func remove_reference(id: String) -> void:
	store.current().get("draft_refs",[]).erase(id)
	sync()

func references() -> Array: return Array(store.current().get("draft_refs",[])).duplicate()

func schedule() -> void:
	if _pending: return
	_pending = true
	update_picker.call_deferred()

func update_picker() -> void:
	_pending = false
	if not ui.surface.visible or not editor.has_focus():
		picker.hide()
		return
	anchor_line = editor.get_caret_line()
	end_column = editor.get_caret_column()
	var prefix: String = editor.get_line(anchor_line).left(end_column)
	if prefix.begins_with("/") and "/compact".begins_with(prefix):
		anchor_column = 0
		ids = ["/compact"]
		selected = 0
		ui._clear(choices)
		choices.add_child(ui._button("/compact  ·  Сжать контекст",choose.bind(0)))
		picker.show()
		position_picker.call_deferred()
		return
	anchor_column = prefix.rfind("@")
	if anchor_column < 0 or (anchor_column > 0 and prefix[anchor_column-1] not in [" ","\t","(","["]):
		picker.hide()
		return
	var query: String = prefix.substr(anchor_column+1).to_lower()
	var signature: String = str(anchor_line)+":"+prefix
	if signature == _dismissed or query.length() > 100:
		picker.hide()
		return
	ids.clear()
	for chat: Dictionary in store.chats:
		if query == "" or query in str(chat.title).to_lower(): ids.append(str(chat.id))
		if ids.size() >= 8: break
	ui._clear(choices)
	selected = clampi(selected,0,maxi(0,ids.size()-1))
	for index: int in ids.size():
		var chat: Dictionary = store.find(str(ids[index]))
		var section: String = str(store.section(str(chat.get("section_id",""))).get("title",""))
		var button: Button = ui._button("@ "+str(chat.title)+( " · "+section if section != "" else ""),choose.bind(index))
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_color_override("font_color",Color("#8fcaff") if index == selected else Color("#e8e9ed"))
		choices.add_child(button)
	picker.visible = not ids.is_empty()
	position_picker.call_deferred()

func position_picker() -> void:
	if not picker.visible: return
	picker.custom_minimum_size.x = minf(660,editor.size.x)
	picker.reset_size()
	picker.position = Vector2(editor.global_position.x,maxf(12,editor.global_position.y-picker.size.y-8))

func choose(index: int) -> void:
	if index < 0 or index >= ids.size(): return
	var id: String = str(ids[index])
	picker.hide()
	editor.remove_text(anchor_line,anchor_column,anchor_line,end_column)
	editor.set_caret_line(anchor_line)
	editor.set_caret_column(anchor_column)
	if id == "/compact":
		editor.insert_text_at_caret("/compact ")
		editor.grab_focus()
		return
	add_reference(id)
	store.current().draft = editor.text
	_dismissed = str(anchor_line)+":"+editor.get_line(anchor_line).left(editor.get_caret_column())

func handle_key(event: InputEvent) -> bool:
	if not picker.visible or not editor.has_focus() or not event is InputEventKey or not event.pressed: return false
	if event.shift_pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER]: return false
	if event.keycode in [KEY_UP,KEY_DOWN]:
		selected = posmod(selected+(-1 if event.keycode == KEY_UP else 1),ids.size())
		update_picker()
		return true
	if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_TAB]:
		var command: bool = str(ids[selected]) == "/compact"
		choose(selected)
		if command and event.keycode != KEY_TAB: ui._send()
		return true
	if event.keycode == KEY_ESCAPE:
		_dismissed = str(anchor_line)+":"+editor.get_line(anchor_line).left(end_column)
		picker.hide()
		return true
	return false

func drag_data(_position: Vector2, id: String, button: Control) -> Variant:
	var preview := Label.new()
	preview.text = "@ "+str(store.find(id).get("title",""))
	preview.add_theme_color_override("font_color",Color("#8fcaff"))
	button.set_drag_preview(preview)
	drop_target.position = ui.composer_input.global_position
	drop_target.size = ui.composer_input.size
	drop_target.show()
	return payload(id)

func payload(id: String) -> Dictionary: return {"kind":"prompt_lab_chat","chat_id":id,"store_id":store.get_instance_id()}

func can_drop(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind") == "prompt_lab_chat" and data.get("store_id") == store.get_instance_id() and not store.find(str(data.get("chat_id",""))).is_empty()

func drop(_position: Vector2, data: Variant) -> void:
	if can_drop(_position,data): add_reference(str(data.chat_id))
	drop_target.hide()

func _process(_delta: float) -> void:
	if drop_target.visible and not ui.get_viewport().gui_is_dragging(): drop_target.hide()
	if picker.visible: position_picker()
	if not ui.surface.visible: dismiss()

func dismiss() -> void:
	picker.hide()
	drop_target.hide()
