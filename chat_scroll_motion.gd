extends Node
## Intercept wheel input before native ScrollContainer jumps. No idle processing.
const WHEEL_STEP := 64.0
const RESPONSE := 22.0
var ui: Node
var containers: Array[ScrollContainer] = []
var revision := 0
var _states: Dictionary = {}

func setup(value: Node, targets: Array) -> void:
	ui = value
	name = "SmoothChatScroll"
	containers.assign(targets)
	set_process(false)

func _maximum(container: ScrollContainer) -> float:
	var bar: VScrollBar = container.get_v_scroll_bar()
	return maxf(0,bar.max_value-bar.page)

func is_animating(container: ScrollContainer) -> bool:
	return _states.has(container)

func cancel() -> void:
	_states.clear()
	set_process(false)

func nudge(container: ScrollContainer, distance: float) -> void:
	var current: float = container.scroll_vertical
	var state: Dictionary = _states.get(container,{"current":current,"target":current})
	# A scrollbar drag, selection or programmatic jump supersedes the animation.
	if absf(current-roundf(float(state.current))) > 1:
		state = {"current":current,"target":current}
	state.target = clampf(float(state.target)+distance,0,_maximum(container))
	_states[container] = state
	revision += 1
	set_process(true)

func _blocked(point: Vector2) -> bool:
	if not ui.surface.visible: return true
	if ui.get_node_or_null("InstructionsDialog") != null: return true
	if ui.chat_menu.view.visible or ui.chat_menu.form.visible or ui.delete_dialog.visible: return true
	return ui._stat_panel.visible and ui._stat_panel.get_global_rect().has_point(point)

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: return
	if event.ctrl_pressed or event.shift_pressed or event.alt_pressed or event.meta_pressed: return
	if _blocked(event.position): return
	for container: ScrollContainer in containers:
		if not container.is_visible_in_tree() or not container.get_global_rect().has_point(event.position): continue
		if _maximum(container) <= 0: return
		var factor: float = event.factor if event.factor > 0 else 1.0
		nudge(container,WHEEL_STEP*factor*(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
		get_viewport().set_input_as_handled()
		return

func _process(delta: float) -> void:
	var factor: float = 1.0-exp(-RESPONSE*delta)
	for container: ScrollContainer in _states.keys():
		if not is_instance_valid(container) or not container.is_visible_in_tree():
			_states.erase(container)
			continue
		var state: Dictionary = _states[container]
		if absf(float(container.scroll_vertical)-roundf(float(state.current))) > 1:
			_states.erase(container)
			continue
		state.target = clampf(float(state.target),0,_maximum(container))
		state.current = lerpf(float(state.current),float(state.target),factor)
		if absf(float(state.target)-float(state.current)) < 0.5:
			container.scroll_vertical = roundi(float(state.target))
			_states.erase(container)
		else: container.scroll_vertical = roundi(float(state.current))
	if _states.is_empty(): set_process(false)
