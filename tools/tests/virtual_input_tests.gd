extends SceneTree
const Capture=preload("res://mods/pax_harness/src/ui/game/ui_capture.gd")
const Virtual=preload("res://mods/pax_harness/src/ui/game/virtual_input.gd")
const Registry=preload("res://mods/pax_harness/src/runtime/tools/registry.gd")
const Router=preload("res://mods/pax_harness/src/transport/provider_router.gd")
class Game extends RefCounted:
	var main: Node
	func scene_root() -> Node: return main
	func is_active() -> bool: return true
class Owner extends Node:
	var game: RefCounted
	var _source_generation:=1
	var _ui_capture: Node
	var _virtual_input: Node
	var chat_ui: CanvasLayer
	var denied: Dictionary={}
	var selected: Dictionary={"enabled":true,"base":"https://fixture.invalid/v1","model":"Vision","provider_id":1,"world_generation":1}
	func vision_context() -> Dictionary: return selected.duplicate()
	func vision_input_enabled() -> bool: return selected.enabled
	func _game_available(candidate: RefCounted=null) -> bool: return candidate==null or candidate==game
	func ui_tool(tool: String, args: Dictionary, scope: Dictionary) -> Dictionary: return _virtual_input.execute(game,tool,args,scope)
	func get_setting(_key: String, _fallback: Variant) -> Dictionary: return denied
	func mark_game_images_delivered(handles: Array, _provider: Node) -> void: _ui_capture.mark_delivered(handles,selected)
class Surface extends Control:
	var events: Array=[]
	var dragged:=Vector2.ZERO
	var wheel:=0
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouse:
			events.append(event.duplicate())
			if event is InputEventMouseMotion and event.button_mask==MOUSE_BUTTON_MASK_LEFT: dragged=event.position
			if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN: wheel+=1
var checks:=0
var failures: Array=[]
var owner: Node
var capture: Node
var virtual: Node
var game: RefCounted
var clicks:=0
func check(ok: bool, label_: String) -> void:
	checks+=1
	if not ok: failures.append(label_);print("FAIL: "+label_)
func _initialize() -> void: call_deferred("run")
func shot(observed: bool=true) -> Dictionary:
	var pending: Dictionary=capture.execute(game,"ui.screenshot",{},{})
	if pending.has("pending"):
		var job: Node=pending.pending
		if not job.finished: await job.completed
		pending=job.result;job.queue_free()
	check(pending.get("ok",false),"actual screenshot succeeded")
	var handle: Dictionary=pending.get("result",{}).get("image_attachment",{})
	if observed: capture.mark_delivered([handle],owner.selected)
	return handle
func act(tool: String, args: Dictionary) -> Dictionary:
	var value: Dictionary=virtual.execute(game,tool,args,{})
	if value.has("pending"):
		var job: Node=value.pending
		if not job.finished: await job.completed
		value=job.result.duplicate(true);job.queue_free()
	return value
func run() -> void:
	root.size=Vector2i(800,600)
	var main:=Control.new();main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(main)
	var button:=Button.new();button.text="Native button";button.position=Vector2(20,20);button.size=Vector2(160,50);main.add_child(button);button.pressed.connect(func():clicks+=1)
	var surface:=Surface.new();surface.position=Vector2(220,20);surface.size=Vector2(240,200);main.add_child(surface)
	var field:=LineEdit.new();field.position=Vector2(20,260);field.size=Vector2(300,40);main.add_child(field)
	var player:=LineEdit.new();player.position=Vector2(20,350);player.size=Vector2(300,40);main.add_child(player)
	game=Game.new();game.main=main
	owner=Owner.new();root.add_child(owner);owner.game=game
	owner.chat_ui=CanvasLayer.new();owner.add_child(owner.chat_ui)
	capture=Capture.new();owner.add_child(capture);capture.setup(owner);owner._ui_capture=capture
	virtual=Virtual.new();owner.add_child(virtual);virtual.setup(owner,capture);owner._virtual_input=virtual
	await process_frame
	var registry:=Registry.new();registry.setup(game,owner,1)
	check(registry.catalogue().filter(func(row):return row.name=="ui.pointer")[0].mutates_world,"pointer changes are never readonly delegate tools")
	owner.selected.enabled=false
	check(not registry.catalogue().any(func(row):return row.name in ["ui.pointer","ui.keyboard"]),"no virtual input schemas for text-only profile")
	var gate:=registry.dispatch({"id":"gate","name":"ui.pointer","arguments":{"image_id":"no","action":"click","x":40,"y":40}},{"game":game,"world_generation":1,"enabled_tools":["ui.pointer"]})
	check(not gate.ok and not gate.receipt.execution_attempted,"stale tool grant cannot bypass model gate")
	owner.selected.enabled=true;owner.denied={"ui.pointer":false}
	check(not registry.validate_call("ui.pointer",{"image_id":"x","action":"click","x":40,"y":40},["ui.pointer"]).ok,"per-tool player checkbox enforced")
	owner.denied={}
	check(not registry.validate_call("ui.keyboard",{"image_id":"x","action":"key","key":"Ctrl+V"},["ui.keyboard"]).ok,"OS clipboard shortcuts rejected by schema")
	check(not registry.validate_call("ui.pointer",{"image_id":"x","action":"scroll","x":1,"y":1,"amount":999},["ui.pointer"]).ok,"scroll amount bounded")
	var unseen:=await shot(false)
	check(virtual.execute(game,"ui.pointer",{"image_id":unseen.id,"action":"click","x":40,"y":40},{}).code=="ui.image_not_observed","cannot click until actual model response accepted image")
	var router:=Router.new();router.setup(owner)
	router._mark_images_seen({"provider":owner,"request_attachments":[unseen]},{"error":"image unsupported"})
	check(not capture.input_frame(unseen.id,game,owner.selected,false).ok,"unsupported-image fallback never authorizes clicks")
	router._mark_images_seen({"provider":owner,"request_attachments":[unseen]},{"answer":"accepted"})
	check(capture.input_frame(unseen.id,game,owner.selected,false).ok,"successful transport response marks this image observed")
	check(virtual.execute(game,"ui.pointer",{"image_id":unseen.id,"action":"click","x":800,"y":1},{}).code=="ui.input_outside_image","outside image denied before input")
	check(virtual.execute(game,"ui.pointer",{"image_id":unseen.id,"action":"drag","x":1,"y":1},{}).code=="ui.input_coordinates_required","drag needs endpoint")
	var before:=[Input.get_mouse_button_mask(),DisplayServer.mouse_get_position()]
	player.grab_focus()
	var result_: Dictionary=await act("ui.pointer",{"image_id":unseen.id,"action":"click","x":60,"y":40})
	check(result_.get("ok",false) and result_.result.has("image_attachment"),"native button action returns actual next image")
	check(clicks==1 and result_.result.dispatched and not result_.result.completed,"button really pressed; delivery not declared gameplay completion")
	check(root.gui_get_focus_owner()==player and owner.chat_ui.visible,"player focus/chat restored")
	check(result_.result.input.physical_input_unchanged,"physical mouse state and OS position unchanged")
	await process_frame
	check(capture.get_child_count()==0,"automatic readback capture is freed after each virtual action")
	check(virtual.execute(game,"ui.pointer",{"image_id":unseen.id,"action":"click","x":60,"y":40},{}).code=="ui.image_view_changed","replay of consumed frame rejected")
	var handle:=await shot()
	result_=await act("ui.pointer",{"image_id":handle.id,"action":"drag","x":250,"y":60,"to_x":400,"to_y":180})
	check(result_.get("ok",false) and surface.dragged.distance_to(Vector2(180,160))<1,"custom no-API canvas receives complete drag with button mask")
	check(surface.events.all(func(event):return event.device==10071),"only distinct virtual device events delivered")
	handle=await shot();result_=await act("ui.pointer",{"image_id":handle.id,"action":"scroll","x":300,"y":80,"direction":"down","amount":3})
	check(result_.get("ok",false) and surface.wheel==3,"custom canvas receives bounded wheel events")
	handle=await shot();result_=await act("ui.pointer",{"image_id":handle.id,"action":"click","x":60,"y":280})
	check(result_.get("ok",false) and virtual.focus.get_ref()==field and root.gui_get_focus_owner()==player,"virtual field focus separate from player focus")
	handle=await shot();result_=await act("ui.keyboard",{"image_id":handle.id,"action":"text","text":"Привет Test"})
	check(result_.get("ok",false) and field.text=="Привет Test" and player.text=="","Unicode enters only the virtually selected field")
	handle=await shot();result_=await act("ui.keyboard",{"image_id":handle.id,"action":"key","key":"Ctrl+A"})
	check(result_.get("ok",false) and root.gui_get_focus_owner()==player,"editing shortcut dispatch restores player focus")
	handle=await shot();result_=await act("ui.keyboard",{"image_id":handle.id,"action":"text","text":"Заменено"})
	check(result_.get("ok",false) and field.text=="Заменено","selection survives player-focus restoration and next text replaces it")
	virtual.resume_for_player_task()
	handle=await shot();capture._input(InputEventMouseMotion.new())
	check(virtual.execute(game,"ui.pointer",{"image_id":handle.id,"action":"click","x":60,"y":40},{}).code=="ui.image_view_changed","human activity invalidates source frame")
	handle=await shot();var pending: Dictionary=virtual.execute(game,"ui.pointer",{"image_id":handle.id,"action":"click","x":60,"y":40},{})
	capture._input(InputEventKey.new())
	if not pending.pending.finished: await pending.pending.completed
	check(not pending.pending.result.ok and clicks==1 and not pending.pending.result.result.input_dispatched,"player priority cancels delayed click before dispatch")
	check(virtual.execute(game,"ui.pointer",{"image_id":handle.id,"action":"click","x":60,"y":40},{}).code=="ui.player_input_active","agent cannot fight player with automatic retries")
	virtual.resume_for_player_task()
	pending.pending.queue_free();await process_frame
	handle=await shot();pending=virtual.execute(game,"ui.pointer",{"image_id":handle.id,"action":"drag","x":250,"y":60,"to_x":400,"to_y":180},{})
	await create_timer(0.23).timeout;capture._input(InputEventMouseMotion.new())
	if not pending.pending.finished: await pending.pending.completed
	check(not pending.pending.result.ok and pending.pending.result.result.input_dispatched and pending.pending._button==0,"interrupted drag reports partial effects and releases synthetic button")
	virtual.resume_for_player_task()
	pending.pending.queue_free();await process_frame
	virtual.resume_for_player_task()
	handle=await shot();root.window_input.emit(InputEventMouseMotion.new())
	check(not capture.input_frame(handle.id,game,owner.selected,false).ok,"native Window input invalidates frames before GUI consumption")
	handle=await shot();owner.selected.model="Another"
	check(not virtual.execute(game,"ui.pointer",{"image_id":handle.id,"action":"click","x":60,"y":40},{}).ok,"switching exact model invalidates vision authorization")
	owner.selected.model="Vision"
	check(virtual.execute(game,"ui.pointer",{"image_id":handle.id,"action":"click","x":60,"y":40},{"analysis_child":true}).code=="ui.input_unavailable_in_analysis","analysis delegates cannot control UI")
	virtual.resume_for_player_task()
	var image:=Image.create(1600,1200,false,Image.FORMAT_RGB8);image.fill(Color.BLACK)
	var scaled: Dictionary=capture.retain(image,game,owner.selected).result.image_attachment;capture.mark_delivered([scaled],owner.selected)
	result_=await act("ui.pointer",{"image_id":scaled.id,"action":"click","x":120,"y":80})
	check(result_.get("ok",false) and clicks==2,"image-pixel coordinates map to logical viewport after scaling")
	virtual.release_hover()
	var popup:=Label.new();popup.text="Hover menu";popup.position=Vector2(500,100);main.add_child(popup);popup.hide()
	button.mouse_entered.connect(func():popup.show());button.mouse_exited.connect(func():popup.hide())
	handle=await shot();result_=await act("ui.pointer",{"image_id":handle.id,"action":"move","x":60,"y":40})
	check(result_.get("ok",false) and popup.visible,"hover-revealed UI remains open across model requests")
	root.window_input.emit(InputEventMouseMotion.new())
	check(virtual._hovered.is_empty() and virtual.suspended,"player priority releases virtual hover between actions too")
	virtual.clear();capture.clear()
	check(virtual.focus==null and not virtual.pointer.visible and capture._images.is_empty(),"teardown clears focus/cursor/frame authorization")
	owner.queue_free();main.queue_free();await process_frame
	print("VIRTUAL_INPUT_TESTS "+("PASS" if failures.is_empty() else str(failures))+"; "+str(checks)+" checks")
	quit(0 if failures.is_empty() else 1)
