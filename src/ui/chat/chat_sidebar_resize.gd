extends Control
## A narrow drag handle; width is a UI preference, independent of campaign data.
const DEFAULT_WIDTH := 230.0
var ui: Node
var sidebar: Control
var preferred_width := DEFAULT_WIDTH
var minimum_width := 180.0
var dragging := false
var _start_x := 0.0
var _start_width := 0.0
var _hovered := false

func setup(value: Node, side: Control) -> void:
	ui = value
	sidebar = side
	name = "SidebarResizeHandle"
	custom_minimum_size.x = 8
	mouse_default_cursor_shape = Control.CURSOR_HSPLIT
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Потяните, чтобы изменить ширину списка чатов"
	sidebar.custom_minimum_size.x = minimum_width
	minimum_width = maxf(minimum_width,sidebar.get_combined_minimum_size().x)
	if ui.owner_mod.has_method("get_setting"):
		var saved: Variant = ui.owner_mod.get_setting("sidebar_width",DEFAULT_WIDTH)
		if saved is float or saved is int:
			if is_finite(float(saved)): preferred_width = clampf(float(saved),minimum_width,1200)
	ui.surface.resized.connect(_fit_width)
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; queue_redraw())
	_fit_width.call_deferred()

func _fit_width() -> void:
	var maximum: float = maxf(minimum_width,ui.surface.size.x-620)
	sidebar.custom_minimum_size.x = clampf(preferred_width,minimum_width,maximum)

func _draw() -> void:
	if dragging or _hovered:
		draw_line(Vector2(size.x/2,0),Vector2(size.x/2,size.y),Color("#6699bf"),1.0,true)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if event.pressed and event.double_click:
		preferred_width = DEFAULT_WIDTH
		_fit_width()
		_save_width()
	elif event.pressed:
		dragging = true
		_start_x = (get_global_transform()*event.position).x
		_start_width = sidebar.size.x
		queue_redraw()
	else: finish_drag()
	accept_event()

func _input(event: InputEvent) -> void:
	if not dragging: return
	if event is InputEventMouseMotion:
		preferred_width = clampf(_start_width+event.position.x-_start_x,minimum_width,maxf(minimum_width,ui.surface.size.x-620))
		_fit_width()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		finish_drag()
		get_viewport().set_input_as_handled()

func finish_drag() -> void:
	if not dragging: return
	dragging = false
	_save_width()
	queue_redraw()

func _save_width() -> void:
	if ui.owner_mod.has_method("set_setting"): ui.owner_mod.set_setting("sidebar_width",preferred_width)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		finish_drag()
