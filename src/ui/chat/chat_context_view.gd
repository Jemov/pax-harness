extends Control
## Embedded menus use the same coordinate space and typography as the chat.
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
const Icons = preload("res://mods/pax_harness/src/ui/components/chat_icons.gd")
var root_panel: PanelContainer
var child_panel: PanelContainer
var root_rows: Array[Button] = []
var child_rows: Array[Button] = []
var _root_model: PopupMenu
var _root_action: Callable
var _children: Dictionary
var _previous_focus: WeakRef
var _submenu_index := -1
var _viewport_size := Vector2.ZERO

func _ready() -> void:
	name = "ChatContextView"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	set_process(false)

func show_menu(model: PopupMenu, action: Callable, children: Dictionary, point: Vector2) -> void:
	dismiss()
	_previous_focus = weakref(get_viewport().gui_get_focus_owner())
	_root_model = model
	_root_action = action
	_children = children
	size = get_viewport().get_visible_rect().size
	_viewport_size = size
	root_rows.clear()
	root_panel = _panel(model,action,false)
	root_panel.position = _bounded(point,root_panel.size)
	show()
	set_process(true)

func _process(_delta: float) -> void:
	if get_viewport().get_visible_rect().size != _viewport_size: dismiss()

func _bounded(point: Vector2, extent: Vector2) -> Vector2:
	return Vector2(clampf(point.x,6,maxf(6,size.x-extent.x-6)),clampf(point.y,6,maxf(6,size.y-extent.y-6))).floor()

func _panel(model: PopupMenu, action: Callable, child: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ChatSubmenu" if child else "ChatMenuPanel"
	var style: StyleBoxFlat = Style.box(Color("#202226"),6,Color("#393c43"),6)
	style.shadow_color = Color(0,0,0,0.25)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",0)
	scroll.add_child(column)
	var height := 12
	for index: int in model.item_count:
		if model.is_item_separator(index):
			var divider := HSeparator.new()
			divider.custom_minimum_size.y = 13
			var line := StyleBoxLine.new()
			line.color = Color("#35383f")
			line.thickness = 1
			divider.add_theme_stylebox_override("separator",line)
			column.add_child(divider)
			height += 13
			continue
		var button := Button.new()
		button.name = "MenuItem_"+str(model.get_item_id(index))
		button.custom_minimum_size.y = 34
		button.focus_mode = Control.FOCUS_ALL
		button.disabled = model.is_item_disabled(index)
		var danger: bool = not child and model == _root_model and model.get_item_id(index) == 5
		for state: String in ["normal","hover","pressed","focus","disabled"]:
			var highlighted: bool = state in ["hover","pressed","focus"]
			button.add_theme_stylebox_override(state,Style.box(Color("#38292e") if danger and highlighted else Color("#2c3037") if highlighted else Color.TRANSPARENT,4,Color.TRANSPARENT,6))
		column.add_child(button)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation",8)
		button.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6
		row.offset_right = -6
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(14,14)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.texture = model.get_item_icon(index)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		if model.is_item_checked(index):
			icon.texture = Icons.make("check",Color("#9ba1ab"),14)
		var text := Label.new()
		text.text = model.get_item_text(index)
		text.clip_text = true
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_font_size_override("font_size",14)
		text.add_theme_color_override("font_color",Color("#60656e") if button.disabled else Color("#d5979e") if danger else Color("#d0d1d3"))
		row.add_child(text)
		var nested: bool = not child and _children.has(model.get_item_id(index))
		if nested:
			var arrow := TextureRect.new()
			arrow.texture = Icons.make("chevron",Color("#949ba7"),12)
			arrow.custom_minimum_size = Vector2(12,12)
			arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(arrow)
		elif model.get_item_accelerator(index) != 0:
			var shortcut := Label.new()
			shortcut.text = "Ctrl+Alt+R" if model.get_item_id(index) == 1 else "Ctrl+Alt+P"
			shortcut.add_theme_font_size_override("font_size",11)
			shortcut.add_theme_color_override("font_color",Color("#949ba7"))
			shortcut.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(shortcut)
		button.pressed.connect(func():
			if nested: _open_child(index,true)
			else: _activate(action,model.get_item_id(index)))
		if not child:
			button.mouse_entered.connect(func():
				if nested: _open_child(index,false)
				else: _close_child())
			root_rows.append(button)
		else: child_rows.append(button)
		height += 34
	panel.size = Vector2(minf(float(model.get_meta("preferred_width",268 if not child else 248)),size.x-12),mini(height,int(size.y)-12))
	return panel

func _open_child(index: int, focus: bool) -> void:
	if _submenu_index != index:
		_close_child()
		_submenu_index = index
		var spec: Array = _children[_root_model.get_item_id(index)]
		child_panel = _panel(spec[0],spec[1],true)
		var origin: Vector2 = root_panel.position
		for button: Button in root_rows:
			if button.name == "MenuItem_"+str(_root_model.get_item_id(index)): origin = button.global_position
		var x: float = root_panel.position.x+root_panel.size.x-1
		if x+child_panel.size.x > size.x-6: x = root_panel.position.x-child_panel.size.x+1
		child_panel.position = _bounded(Vector2(x,origin.y-6),child_panel.size)
	if focus and not child_rows.is_empty(): child_rows[0].grab_focus()

func _close_child() -> void:
	if is_instance_valid(child_panel):
		child_panel.hide()
		child_panel.queue_free()
	child_panel = null
	child_rows.clear()
	_submenu_index = -1

func _activate(action: Callable, id: int) -> void:
	dismiss()
	action.call(id)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = get_global_mouse_position()
		if not root_panel.get_global_rect().has_point(point) and (child_panel == null or not child_panel.get_global_rect().has_point(point)):
			dismiss()
			accept_event()

func handle_key(event: InputEventKey) -> bool:
	if not visible: return false
	if event.keycode == KEY_ESCAPE:
		dismiss()
		return true
	for index: int in _root_model.item_count:
		if _root_model.get_item_accelerator(index) == event.get_keycode_with_modifiers() and not _root_model.is_item_disabled(index):
			_activate(_root_action,_root_model.get_item_id(index))
			return true
	var focused: Control = get_viewport().gui_get_focus_owner()
	var rows: Array[Button] = child_rows if focused in child_rows else root_rows
	if event.keycode in [KEY_UP,KEY_DOWN]:
		var index: int = rows.find(focused)
		for attempt: int in rows.size():
			index = posmod(index+(-1 if event.keycode == KEY_UP else 1),rows.size())
			if not rows[index].disabled:
				rows[index].grab_focus()
				break
		return true
	if event.keycode == KEY_RIGHT and focused in root_rows:
		var id: int = int(str(focused.name).trim_prefix("MenuItem_"))
		if _children.has(id): _open_child(_root_model.get_item_index(id),true)
		return true
	if event.keycode == KEY_LEFT and focused in child_rows:
		var index: int = _submenu_index
		_close_child()
		# Root model separators are not focusable rows.
		var id: int = _root_model.get_item_id(index)
		for button: Button in root_rows:
			if button.name == "MenuItem_"+str(id): button.grab_focus()
		return true
	return false

func dismiss() -> void:
	hide()
	set_process(false)
	_close_child()
	if is_instance_valid(root_panel):
		root_panel.hide()
		root_panel.queue_free()
	root_panel = null
	root_rows.clear()
	var previous: Control = _previous_focus.get_ref() if _previous_focus != null else null
	if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
