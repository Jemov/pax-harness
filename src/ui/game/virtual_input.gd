extends Node
## Viewport-local input fallback. No Input singleton injection, system pointer or clipboard.
const Panels = preload("res://mods/pax_harness/src/ui/game/ui_panels.gd")
const Job = preload("res://mods/pax_harness/src/ui/game/virtual_input_job.gd")
const Cursor = preload("res://mods/pax_harness/src/ui/game/virtual_cursor.gd")
const DEVICE := 10071
var owner_mod: Node
var capture: Node
var cursor: CanvasLayer
var pointer: Node2D
var focus: WeakRef
var active: Node
var suspended:=false
var _session_input:=false
var _hovered: Dictionary={}


func setup(owner: Node, images: Node) -> void:
	owner_mod=owner; capture=images; process_mode=Node.PROCESS_MODE_ALWAYS
	capture.player_input.connect(_player_took_control)
	cursor=CanvasLayer.new(); cursor.name="HarnessVirtualCursor"; cursor.layer=1000; add_child(cursor)
	pointer=Cursor.new(); cursor.add_child(pointer); pointer.hide()

func execute(game: RefCounted, tool: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	if suspended: return {"ok":false,"code":"ui.player_input_active","result":{"instruction":"The player took control. Do not retry virtual input in this task. Wait for a new player message."}}
	if scope.get("analysis_child",false): return {"ok":false,"code":"ui.input_unavailable_in_analysis"}
	if is_instance_valid(active) and not active.finished: return {"ok":false,"code":"ui.input_busy"}
	if Input.is_anything_pressed(): return {"ok":false,"code":"ui.player_input_active"}
	var selected: Dictionary=capture.context()
	var frame: Dictionary=capture.input_frame(args.get("image_id",""),game,selected,false)
	if not frame.get("ok",false): return frame
	var viewport: Viewport=frame.viewport
	var command: Dictionary=args.duplicate(true)
	if tool=="ui.pointer":
		for pair: Array in [["x","y"],["to_x","to_y"]] if args.get("action")=="drag" else [["x","y"]]:
			if not args.has(pair[0]) or not args.has(pair[1]): return {"ok":false,"code":"ui.input_coordinates_required"}
			var x: float=float(args[pair[0]]); var y: float=float(args[pair[1]])
			if not is_finite(x) or not is_finite(y) or x<0 or y<0 or x>=frame.width or y>=frame.height: return {"ok":false,"code":"ui.input_outside_image"}
			var session: Variant=owner_mod.get("_screen_session") if "_screen_session" in owner_mod else null
			if is_instance_valid(session) and session.owns_point(viewport,Vector2(x/float(frame.width)*frame.size.x,y/float(frame.height)*frame.size.y)): return {"ok":false,"code":"ui.agent_controls_reserved"}
			command[pair[0]]=x/float(frame.width)*frame.size.x
			command[pair[1]]=y/float(frame.height)*frame.size.y
	elif tool=="ui.keyboard":
		if args.get("action")=="text" and (not args.has("text") or args.text==""): return {"ok":false,"code":"ui.input_text_required"}
		if args.get("action")=="key" and not keycodes().has(args.get("key","")): return {"ok":false,"code":"ui.input_key_not_allowed"}
		var target: Variant=focus.get_ref() if focus!=null else null
		if not target is Control or not is_instance_valid(target) or not target.is_visible_in_tree() or target.get_viewport()!=viewport: return {"ok":false,"code":"ui.input_focus_required","result":{"instruction":"Click the target input field using a fresh game screenshot before typing. system clipboard shortcuts are unavailable."}}
	else: return {"ok":false,"code":"ui.unknown_tool"}
	# Consume only after all preflight checks; every subsequent action needs a new frame.
	frame=capture.input_frame(args.get("image_id",""),game,selected,true)
	if not frame.get("ok",false): return frame
	_session_input=true
	active=Job.new(); add_child(active); active.setup(self,game,tool,command,scope,selected,frame)
	return {"pending":active}

static func keycodes() -> Dictionary:
	return {"Enter":KEY_ENTER,"Escape":KEY_ESCAPE,"Tab":KEY_TAB,"Backspace":KEY_BACKSPACE,"Delete":KEY_DELETE,"Left":KEY_LEFT,"Right":KEY_RIGHT,"Up":KEY_UP,"Down":KEY_DOWN,"Home":KEY_HOME,"End":KEY_END,"PageUp":KEY_PAGEUP,"PageDown":KEY_PAGEDOWN,"Space":KEY_SPACE,"Ctrl+A":KEY_A,"Ctrl+Z":KEY_Z,"Ctrl+Y":KEY_Y}

func _process(_delta: float) -> void:
	if suspended: return
	var session: Variant=owner_mod.get("_screen_session") if is_instance_valid(owner_mod) and "_screen_session" in owner_mod else null
	if is_instance_valid(session) and session.active and is_instance_valid(pointer) and pointer.visible: pointer.until=Time.get_ticks_msec()+1000
	for reference: WeakRef in _hovered.values():
		var node: Variant=reference.get_ref()
		if node is BaseButton and is_instance_valid(node) and node.is_visible_in_tree() and not node.is_hovered():
			_notify_hover(node,true)
func resume_for_player_task() -> void: suspended=false;_session_input=false
static func _notify_hover(node: Control, entered: bool) -> void:
	# Some game/engine builds dispatch these signals in Viewport, not notification.
	var emitted: Array=[false]
	var observe:=func():emitted[0]=true
	var event: String="mouse_entered" if entered else "mouse_exited"
	node.connect(event,observe)
	node.notification(Control.NOTIFICATION_MOUSE_ENTER if entered else Control.NOTIFICATION_MOUSE_EXIT)
	if not emitted[0]: node.emit_signal(event)
	if is_instance_valid(node) and node.is_connected(event,observe): node.disconnect(event,observe)
func hover_control(control: Control, seen: Dictionary) -> void:
	var chain: Array=[]
	var parent: Node=control
	while parent!=null and not parent is Viewport:
		if parent is Control: chain.push_front(parent)
		parent=parent.get_parent()
	for node: Control in chain:
		var id: int=node.get_instance_id();seen[id]=true
		if not _hovered.has(id):
			_hovered[id]=weakref(node);_notify_hover(node,true)
		elif node is BaseButton and not node.is_hovered(): _notify_hover(node,true)
func release_hover(seen: Dictionary={}) -> void:
	for id: int in _hovered.keys():
		if seen.has(id): continue
		var node: Variant=_hovered[id].get_ref();_hovered.erase(id)
		if not is_instance_valid(node) or not node.is_inside_tree(): continue
		var physical: Control=node.get_viewport().gui_get_hovered_control()
		if physical==null or (physical!=node and not node.is_ancestor_of(physical)): _notify_hover(node,false)
func _player_took_control() -> void:
	release_hover()
	if _session_input: suspended=true
	if is_instance_valid(active) and not active.finished: active.cancel();pointer.hide()
func cancel_all() -> void:
	release_hover()
	if is_instance_valid(active):
		active.cancel()
		active.queue_free()
	active=null; focus=null
	if is_instance_valid(pointer): pointer.hide()
func clear() -> void: cancel_all();suspended=false;_session_input=false
func _exit_tree() -> void: cancel_all()
