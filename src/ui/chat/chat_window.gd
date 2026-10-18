extends Node
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Layout = preload("res://mods/pax_harness/src/ui/chat/chat_layout.gd")
const Icons = preload("res://mods/pax_harness/src/ui/components/chat_icons.gd")
## Move the same workspace between the game viewport and a native OS window.
var ui: Node
var home: Node
var viewport: Viewport
var external: Window
var maximized := false
var floating := Rect2()
var dragging := false
var drag_start := Vector2.ZERO
var drag_origin := Vector2.ZERO
var maximize_button: Button
var detach_button: Button

func setup(value: Node, header: Control, handle: Control, buttons: HBoxContainer, detach_control: Button = null) -> void:
	ui = value
	home = ui.get_parent()
	viewport = ui.get_viewport()
	header.gui_input.connect(_header_input)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.tooltip_text = L.text("Перетащить окно · двойной щелчок — развернуть")
	handle.gui_input.connect(_header_input)
	maximize_button = Layout.icon_button(ui,"expand",toggle_maximize,L.text("Развернуть"))
	maximize_button.name = "MaximizeChats"
	maximize_button.tooltip_text = L.text("Развернуть")
	buttons.add_child(maximize_button)
	detach_button = detach_control if detach_control != null else ui._button(L.text("Отдельное окно"),toggle_external)
	detach_button.name = "DetachChats"
	detach_button.tooltip_text = L.text("Открыть в отдельном окне")
	if detach_control == null: buttons.add_child(detach_button)
	viewport.size_changed.connect(ui._fit)

func fit() -> void:
	var available: Vector2 = ui.get_viewport().get_visible_rect().size
	ui.backdrop.size = available
	if is_instance_valid(external) or maximized:
		ui.surface.position = Vector2.ZERO
		ui.surface.size = available
	else:
		if floating.size == Vector2.ZERO:
			floating.size = Vector2(minf(1320,available.x-36),minf(920,available.y-80))
			floating.position = (available-floating.size)/2
		floating.size = floating.size.min((available-Vector2(24,24)).max(Vector2(1,1)))
		ui.surface.size = floating.size
		move_to(floating.position)
	maximize_button.icon = Icons.make("restore" if maximized else "expand")
	maximize_button.tooltip_text = L.text("Восстановить размер") if maximized else L.text("Развернуть")
	ui.backdrop.visible = ui.surface.visible and not is_instance_valid(external)

func move_to(point: Vector2) -> void:
	var available: Vector2 = ui.get_viewport().get_visible_rect().size
	var maximum: Vector2 = (available-ui.surface.size).max(Vector2.ZERO)
	ui.surface.position = point.clamp(Vector2.ZERO,maximum).floor()
	floating.position = ui.surface.position

func _header_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if event.pressed and event.double_click:
		toggle_maximize()
	elif event.pressed:
		if is_instance_valid(external): external.start_drag()
		elif not maximized:
			dragging = true
			drag_start = ui.get_viewport().get_mouse_position()
			drag_origin = ui.surface.position
	ui.get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not dragging: return
	if event is InputEventMouseMotion:
		move_to(drag_origin+event.position-drag_start)
		ui.get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false

func toggle_maximize() -> void:
	dragging = false
	maximized = not maximized
	if is_instance_valid(external): external.mode = Window.MODE_MAXIMIZED if maximized else Window.MODE_WINDOWED
	fit()

func _prepare_move() -> void:
	dragging = false
	if ui.scroll_motion != null: ui.scroll_motion.cancel()
	if ui.sidebar_resize != null: ui.sidebar_resize.finish_drag()
	ui.mentions.dismiss()
	ui.chat_menu.dismiss()
	ui.delete_dialog.hide()
	ui._stat_panel.hide()
	if viewport.size_changed.is_connected(ui._fit): viewport.size_changed.disconnect(ui._fit)

func toggle_external() -> void:
	if is_instance_valid(external):
		return_to_game()
		return
	_prepare_move()
	external = Window.new()
	external.visible = false
	external.name = "PaxHarnessWindow"
	external.title = "Pax Harness"
	external.force_native = DisplayServer.get_name() != "headless"
	external.gui_embed_subwindows = true
	external.transient = false
	external.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	external.size = Vector2i(1360,900)
	external.min_size = Vector2i(1280,600)
	home.add_child(external)
	external.close_requested.connect(_external_close)
	ui.reparent(external)
	viewport = external
	viewport.size_changed.connect(ui._fit)
	maximized = false
	detach_button.text = L.text("Вернуть в игру")
	detach_button.icon = Icons.make("return",ui.QUIET,16)
	detach_button.tooltip_text = L.text("Вернуть в игру")
	external.show()
	fit()
	ui.input.grab_focus.call_deferred()

func return_to_game() -> void:
	if not is_instance_valid(external): return
	_prepare_move()
	var old: Window = external
	ui.reparent(home)
	external = null
	viewport = ui.get_viewport()
	viewport.size_changed.connect(ui._fit)
	maximized = false
	detach_button.text = L.text("Отдельное окно")
	detach_button.icon = Icons.make("external",ui.QUIET,16)
	detach_button.tooltip_text = L.text("Открыть в отдельном окне")
	old.hide()
	old.queue_free()
	fit()
	ui.input.grab_focus.call_deferred()

func _external_close() -> void:
	return_to_game()
	ui.close()

func show_workspace() -> void:
	if is_instance_valid(external):
		external.show()
		external.grab_focus()
	fit()

func hide_workspace() -> void:
	dragging = false
	if ui.sidebar_resize != null: ui.sidebar_resize.finish_drag()
	if is_instance_valid(external): external.hide()

func dispose() -> void:
	# Release the viewport only after moving its controls and embedded popups out.
	if is_instance_valid(external): return_to_game()
