extends Node
## One bounded action followed by actual framebuffer readback, with player-input priority.
signal completed
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Panels = preload("res://mods/pax_harness/src/ui/game/ui_panels.gd")
const DEVICE := 10071
var service: Node
var game: RefCounted
var selected: Dictionary
var scope: Dictionary
var args: Dictionary
var tool: String
var frame: Dictionary
var viewport: Viewport
var result: Dictionary={}
var finished:=false
var _hidden: Array=[]
var _old_focus: WeakRef
var _button:=0
var _at:=Vector2.ZERO
var _sent:=0
var _capture_job: Node
var _deadline:=0
var _control_connections: Array=[]
var _hover_seen: Dictionary={}
var physical_input_unchanged:=true
func _control_input(event: InputEvent, control: Control) -> void:
	if event.device!=DEVICE or not event is InputEventMouse or not is_instance_valid(control): return
	# Native hit-testing routed this event here. Root Window hover otherwise uses
	# the physical pointer; retain a separate notification chain until next input.
	if Rect2(Vector2.ZERO,control.size).has_point(event.position): service.hover_control(control,_hover_seen)
func _watch_controls(node: Node) -> void:
	if node is Control and node.get_viewport()==viewport:
		var callback:=_control_input.bind(node)
		node.gui_input.connect(callback);_control_connections.append({"node":weakref(node),"callback":callback})
	for child: Node in node.get_children(): _watch_controls(child)

func _hover_at(at: Vector2) -> void:
	# Root Window computes idle hover from the physical pointer. Reproduce only
	# hover notifications using the visible Control paint order, without warping it.
	var best: Control
	var best_score: Array=[]
	for index: int in _control_connections.size():
		var node: Variant=_control_connections[index].node.get_ref()
		if not is_instance_valid(node) or not node.is_visible_in_tree() or node.mouse_filter==Control.MOUSE_FILTER_IGNORE: continue
		var local: Vector2=node.get_global_transform_with_canvas().affine_inverse()*at
		if not Rect2(Vector2.ZERO,node.size).has_point(local): continue
		if node.has_method("_has_point") and not node.call("_has_point",local): continue
		var layer:=0;var z: int=node.z_index;var clipped:=false;var parent: Node=node.get_parent()
		while parent!=null and not parent is Viewport:
			if parent is CanvasLayer: layer=parent.layer
			if parent is Control and parent.clip_contents and not Rect2(Vector2.ZERO,parent.size).has_point(parent.get_global_transform_with_canvas().affine_inverse()*at): clipped=true;break
			if parent is CanvasItem and node.z_as_relative: z+=parent.z_index
			parent=parent.get_parent()
		if clipped: continue
		var score: Array=[layer,z,index]
		if best==null or layer>best_score[0] or (layer==best_score[0] and (z>best_score[1] or (z==best_score[1] and index>best_score[2]))): best=node;best_score=score
	_hover_seen.clear()
	if best!=null: service.hover_control(best,_hover_seen)

func setup(owner: Node, facade: RefCounted, name_: String, command: Dictionary, task_scope: Dictionary, context: Dictionary, image_frame: Dictionary) -> void:
	service=owner; game=facade; tool=name_;args=command;scope=task_scope;selected=context;frame=image_frame;viewport=frame.viewport
	process_mode=Node.PROCESS_MODE_ALWAYS;_deadline=Time.get_ticks_msec()+6000
	_run.call_deferred()
func alive() -> bool:
	if finished or not is_instance_valid(service) or not service.capture.current(game,selected) or service.capture.input_epoch!=frame.epoch: return false
	if Input.is_anything_pressed() or not is_instance_valid(viewport): return false
	var main: Node=Panels.main_node(game)
	if main==null or main.get_viewport()!=viewport or viewport.get_visible_rect().size!=frame.size: return false
	var check: Variant=scope.get("is_current")
	return bool(check.call()) if check is Callable and check.is_valid() else true
func _hide(node: Variant) -> void:
	if not node is CanvasItem and not node is CanvasLayer and not node is Window: return
	_hidden.append({"node":weakref(node),"visible":node.visible}); node.hide()
func _send(event: InputEvent) -> void:
	event.device=DEVICE;event.set_meta("pax_harness_virtual",true)
	if event is InputEventMouse:
		var modifiers: Array=args.get("modifiers",[])
		event.shift_pressed="Shift" in modifiers;event.ctrl_pressed="Ctrl" in modifiers
		event.alt_pressed="Alt" in modifiers;event.meta_pressed="Meta" in modifiers
	var physical: Array=[Input.get_mouse_button_mask(),DisplayServer.mouse_get_position()]
	_hover_seen.clear()
	_sent+=1; viewport.push_input(event,true)
	physical_input_unchanged=physical_input_unchanged and physical==[Input.get_mouse_button_mask(),DisplayServer.mouse_get_position()]
	if event is InputEventMouseMotion and event.button_mask==0: _hover_at(event.position)
	if event is InputEventMouse: service.release_hover(_hover_seen)
func _motion(at: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.relative=at-_at;event.button_mask=_mask()
	_at=at;service.pointer.point(at,_button!=0);_send(event)
func _mask() -> int: return 1<<(_button-1) if _button>0 else 0
func _click(button: int, down: bool, twice: bool=false) -> void:
	_button=button if down else 0
	var event:=InputEventMouseButton.new();event.position=_at;event.global_position=_at;event.button_index=button;event.pressed=down;event.button_mask=_mask();event.double_click=twice
	service.pointer.point(_at,down);_send(event)
func _remember_focus() -> void:
	var target: Control=viewport.gui_get_focus_owner()
	service.focus=weakref(target) if target!=null else null
func _run() -> void:
	if not alive(): cancel();return
	var previous: Control=viewport.gui_get_focus_owner()
	if previous!=null: _old_focus=weakref(previous)
	var chat: Variant=Data.property(service.owner_mod,"chat_ui")
	var session: Variant=Data.property(service.owner_mod,"_screen_session")
	var stable_view: bool=session is Node and is_instance_valid(session) and session.begin()
	if not stable_view:_hide(chat);_hide(Data.property(chat,"native"))
	_watch_controls(viewport)
	# Show the separate cursor before delivering input. Never manipulate system focus.
	if tool=="ui.pointer": service.pointer.point(Vector2(args.x,args.y))
	await get_tree().create_timer(0.15,true).timeout
	if not alive(): cancel();return
	if tool=="ui.pointer":
		_motion(Vector2(args.x,args.y))
		if not alive(): cancel();return
		var button: int={"left":MOUSE_BUTTON_LEFT,"right":MOUSE_BUTTON_RIGHT,"middle":MOUSE_BUTTON_MIDDLE}.get(args.get("button","left"),MOUSE_BUTTON_LEFT)
		match args.action:
			"click","double_click":
				_click(button,true);_click(button,false)
				if args.action=="double_click" and alive(): _click(button,true,true);_click(button,false,true)
			"drag":
				_click(button,true)
				var start:=_at
				for step: int in range(1,9):
					await get_tree().create_timer(0.025,true).timeout
					if not alive(): cancel();return
					_motion(start.lerp(Vector2(args.to_x,args.to_y),float(step)/8.0))
				_click(button,false)
			"scroll":
				var wheel: int={"up":MOUSE_BUTTON_WHEEL_UP,"down":MOUSE_BUTTON_WHEEL_DOWN,"left":MOUSE_BUTTON_WHEEL_LEFT,"right":MOUSE_BUTTON_WHEEL_RIGHT}.get(args.get("direction","down"),MOUSE_BUTTON_WHEEL_DOWN)
				for i: int in int(args.get("amount",1)):
					if not alive(): cancel();return
					_click(wheel,true);_click(wheel,false)
		_remember_focus()
	else:
		var target: Variant=service.focus.get_ref() if service.focus!=null else null
		if not target is Control or not is_instance_valid(target) or not target.is_visible_in_tree(): cancel();return
		target.grab_focus()
		if args.action=="text":
			viewport.push_text_input(args.text);_sent+=1
		else:
			for down: bool in [true,false]:
				var event:=InputEventKey.new();event.keycode=service.keycodes()[args.key];event.pressed=down;event.ctrl_pressed=str(args.key).begins_with("Ctrl+")
				_send(event)
		_remember_focus()
	if not alive(): cancel();return
	await get_tree().create_timer(0.25,true).timeout
	if not alive(): cancel();return
	# Capture is mandatory; event delivery alone is never a gameplay success receipt.
	var next: Dictionary=service.capture.execute(game,"ui.screenshot",{},scope)
	if next.has("pending"):
		_capture_job=next.pending
		if not _capture_job.finished: await _capture_job.completed
		next=_capture_job.result.duplicate(true)
	if finished: return
	if not alive(): cancel();return
	if not next.get("ok",false):
		_finish({"ok":false,"code":"ui.input_readback_failed","result":{"input_dispatched":_sent>0,"capture_error":next.get("code","unknown"),"instruction":"Input may have changed the game. Take a fresh screenshot and inspect before retrying."}});return
	next.result.merge({"dispatched":true,"completed":false,"input":{"tool":tool,"action":args.action,"events_delivered":_sent,"system_mouse_used":false,"physical_input_unchanged":physical_input_unchanged},"instruction":"Inspect the attached NEW game image to verify the actual effect. Dispatched input is not proof that a deal/order/game action succeeded."})
	if tool=="ui.pointer":next.result.input["modifiers"]=args.get("modifiers",[]).duplicate()
	_finish(next)
func _process(_delta: float) -> void:
	if finished: return
	if not alive() or Time.get_ticks_msec()>=_deadline: cancel()
func cancel() -> void:
	if not finished: _finish({"ok":false,"code":"ui.input_interrupted","result":{"input_dispatched":_sent>0,"instruction":"Player input, cancellation or a changed view interrupted virtual input. Inspect a fresh screenshot before continuing."}})
func _finish(value: Dictionary) -> void:
	if finished: return
	finished=true;set_process(false)
	if _button!=0 and is_instance_valid(viewport) and viewport.is_inside_tree():
		_motion(Vector2(-100,-100));_click(_button,false)
	if is_instance_valid(_capture_job):
		if not _capture_job.finished:_capture_job.cancel()
		if is_instance_valid(_capture_job) and not _capture_job.is_queued_for_deletion():_capture_job.queue_free()
	_capture_job=null
	for item: Dictionary in _hidden:
		var node: Variant=item.node.get_ref()
		if is_instance_valid(node) and not node.is_queued_for_deletion() and not service.suspended: node.visible=item.visible
	_hidden.clear()
	# Restoring focus only if the player has not acted avoids stealing their input.
	if is_instance_valid(viewport) and is_instance_valid(service) and service.capture.input_epoch==frame.epoch:
		var target: Control=viewport.gui_get_focus_owner()
		var preserve_selection: bool=target!=null and "deselect_on_focus_loss_enabled" in target
		var old_deselect: bool=target.deselect_on_focus_loss_enabled if preserve_selection else false
		if preserve_selection: target.deselect_on_focus_loss_enabled=false
		var previous: Variant=_old_focus.get_ref() if _old_focus!=null else null
		if previous is Control and is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
		else: viewport.gui_release_focus()
		if preserve_selection and is_instance_valid(target): target.deselect_on_focus_loss_enabled=old_deselect
	for connection: Dictionary in _control_connections:
		var node: Variant=connection.node.get_ref()
		if is_instance_valid(node) and node.is_connected("gui_input",connection.callback): node.disconnect("gui_input",connection.callback)
	_control_connections.clear()
	value["_handler_invoked"]=_sent>0;result=value;completed.emit()
func _exit_tree() -> void:
	if not finished: cancel()
