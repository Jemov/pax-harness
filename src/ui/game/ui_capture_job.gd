extends Node
## Frame-delayed capture. Only the captured game viewport is read, never DisplayServer screen pixels.
signal completed
const Panels = preload("res://mods/pax_harness/src/ui/game/ui_panels.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
var service: Node
var game: RefCounted
var selected: Dictionary
var scope: Dictionary
var result: Dictionary = {}
var finished := false
var _hidden: Array = []
var _deadline := 0

func setup(owner: Node, facade: RefCounted, context: Dictionary, task_scope: Dictionary) -> void:
	service=owner; game=facade; selected=context.duplicate(); scope=task_scope.duplicate()
	process_mode=Node.PROCESS_MODE_ALWAYS
	_deadline=Time.get_ticks_msec()+4000
	_run.call_deferred()

func alive() -> bool:
	if finished or not is_instance_valid(service) or not service.current(game,selected): return false
	var check: Variant = scope.get("is_current")
	return bool(check.call()) if check is Callable and check.is_valid() else true

func _hide(node: Variant) -> void:
	if not node is Node or not is_instance_valid(node): return
	if not node is CanvasLayer and not node is CanvasItem and not node is Window: return
	_hidden.append({"node":weakref(node),"visible":node.visible})
	node.hide()

func _restore() -> void:
	for item: Dictionary in _hidden:
		var node: Variant = item.node.get_ref()
		if node is Node and is_instance_valid(node) and not node.is_queued_for_deletion(): node.visible=item.visible
	_hidden.clear()

func _run() -> void:
	if not alive(): _finish({"ok":false,"code":"ui.capture_cancelled"}); return
	var main: Node = Panels.main_node(game)
	if main==null or not main.is_inside_tree(): _finish({"ok":false,"code":"ui.game_viewport_unavailable"}); return
	var viewport: Viewport = main.get_viewport()
	if viewport==null or DisplayServer.get_name()=="headless": _finish({"ok":false,"code":"ui.rendered_framebuffer_unavailable"}); return
	var chat: Variant = Data.property(service.owner_mod,"chat_ui")
	_hide(chat)
	_hide(Data.property(chat,"native"))
	# The visible panel behind Harness is rendered on the next frame.
	await get_tree().process_frame
	if not alive(): _finish({"ok":false,"code":"ui.capture_cancelled"}); return
	await RenderingServer.frame_post_draw
	if not alive(): _finish({"ok":false,"code":"ui.capture_cancelled"}); return
	if not is_instance_valid(main) or not main.is_inside_tree() or not is_instance_valid(viewport) or viewport!=main.get_viewport(): _finish({"ok":false,"code":"ui.game_viewport_changed"}); return
	var texture: Texture2D = viewport.get_texture()
	if texture==null: _finish({"ok":false,"code":"ui.empty_framebuffer"}); return
	var image: Image = texture.get_image()
	_finish(service.retain(image,game,selected))

func _process(_delta: float) -> void:
	if finished: return
	if not alive(): _finish({"ok":false,"code":"ui.capture_cancelled"})
	elif Time.get_ticks_msec()>=_deadline: _finish({"ok":false,"code":"ui.capture_timeout"})

func cancel() -> void:
	if not finished: _finish({"ok":false,"code":"ui.capture_cancelled"})
	else: _restore()

func _finish(value: Dictionary) -> void:
	if finished: return
	_restore(); result=value; finished=true; set_process(false); completed.emit()

func _exit_tree() -> void: _restore()
