extends ScrollContainer
## Vector canvas zoom: layout remains in logical coordinates, hit testing is
## transformed by Godot together with the drawing. No cached bitmap is scaled.
signal zoom_changed(value: float)
var plot: Control
var content: Control
var zoom := 1.0
var target_zoom := 1.0
var animation_enabled := true
var _dragging := false
var _origin := Vector2.ZERO
var _scroll_origin := Vector2.ZERO
var _zoom_tween: Tween
func setup(canvas: Control) -> void:
	plot = canvas; name = "ChartViewport"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content = Control.new(); content.name = "ZoomContent"; add_child(content); content.add_child(plot)
	plot.gui_input.connect(_plot_input)
	plot.minimum_size_changed.connect(_layout)
	resized.connect(_layout)
	clip_contents = true
	_layout.call_deferred()
func _layout() -> void:
	if not is_instance_valid(plot) or size.x < 1: return
	var width: float = maxf(220,size.x-(get_v_scroll_bar().size.x if zoom > 1.001 else 0))
	var height: float = maxf(120,plot.custom_minimum_size.y)
	custom_minimum_size.y = height
	plot.size = Vector2(width,height); plot.scale = Vector2.ONE*zoom
	content.custom_minimum_size = (plot.size*zoom).ceil()
	# AUTO keeps the child's previous minimum width from preventing a parent
	# resize; DISABLED would propagate it and lock the whole chat at that width.
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
func set_zoom(value: float) -> void:
	var previous: float = zoom
	zoom = clampf(value,1,4); _layout()
	if previous > 0:
		scroll_horizontal = roundi((scroll_horizontal+size.x/2)*zoom/previous-size.x/2)
		scroll_vertical = roundi((scroll_vertical+size.y/2)*zoom/previous-size.y/2)
	zoom_changed.emit(zoom)
func change_zoom(value: float) -> void:
	target_zoom = clampf(value,1,4)
	if _zoom_tween != null and _zoom_tween.is_valid(): _zoom_tween.kill()
	if animation_enabled: _zoom_tween = create_tween(); _zoom_tween.tween_method(set_zoom,zoom,target_zoom,0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else: set_zoom(target_zoom)
func set_animation_enabled(value: bool) -> void:
	animation_enabled = value
	if not value and _zoom_tween != null and _zoom_tween.is_valid(): _zoom_tween.kill(); set_zoom(target_zoom)
func _plot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed
		_origin = get_global_mouse_position(); _scroll_origin = Vector2(scroll_horizontal,scroll_vertical)
		plot.accept_event()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _dragging:
		if event is InputEventMouseMotion:
			var offset: Vector2 = get_global_mouse_position()-_origin
			scroll_horizontal = roundi(_scroll_origin.x-offset.x); scroll_vertical = roundi(_scroll_origin.y-offset.y)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed: _dragging = false
	if event is InputEventMouseButton and event.pressed and wheel_contains(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and (event.ctrl_pressed or is_map()):
		change_zoom(target_zoom+(0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25))
		get_viewport().set_input_as_handled()

func wheel_contains(point: Vector2) -> bool:
	if not is_visible_in_tree() or not Rect2(Vector2.ZERO,size).has_point(get_global_transform_with_canvas().affine_inverse()*point): return false
	var ancestor: Node=get_parent()
	while ancestor!=null:
		if ancestor is Control and ancestor.clip_contents and not Rect2(Vector2.ZERO,ancestor.size).has_point(ancestor.get_global_transform_with_canvas().affine_inverse()*point): return false
		ancestor=ancestor.get_parent()
	return get_viewport().get_visible_rect().has_point(point)

func is_map() -> bool:
	return is_instance_valid(plot) and plot.get("spec") is Dictionary and str(plot.spec.get("type","")) in ["choropleth","cartogram","symbol_map","flow_map"]
