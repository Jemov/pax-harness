extends SceneTree
const Runtime=preload("res://mods/pax_harness/src/runtime/universal_runtime.gd")
const Vision=preload("res://mods/pax_harness/src/transport/vision_payload.gd")
const A={"id":"capture:retention:a","mime_type":"image/png","width":64,"height":32,"byte_size":128,"source":"game_viewport"}
const B={"id":"capture:retention:b","mime_type":"image/png","width":320,"height":160,"byte_size":512,"source":"game_viewport"}
const USER={"id":"reference:retention:user","mime_type":"image/png","width":96,"height":64,"byte_size":256,"source":"user_reference","name":"Player reference"}
class Frames extends RefCounted:
	var live:=true
	var current_id:=""
	var delivered: Dictionary={}
	var checked: Array=[]
	func current(handle: Dictionary) -> bool:
		checked.append(handle.duplicate(true))
		return live and handle.get("id")==current_id and delivered.has(current_id)
class Registry extends RefCounted:
	var frames: Frames
	var handles: Array=[A.duplicate(true),B.duplicate(true)]
	var captures:=0
	func catalogue() -> Array:return [{"name":"ui.screenshot","read_only":true},{"name":"mods.list","read_only":true},{"name":"ui.panels","read_only":true}]
	func validate_call(_name: String,_args: Dictionary,_enabled: Array) -> Dictionary:return {"ok":true}
	func dispatch(call: Dictionary,_scope: Dictionary) -> Dictionary:
		var result: Dictionary={"available":true}
		if call.name=="ui.screenshot":
			var handle: Dictionary=handles[mini(captures,handles.size()-1)].duplicate(true);captures+=1
			frames.current_id=handle.id;frames.delivered.erase(handle.id)
			result={"image_attachment":handle}
		return {"ok":true,"receipt":{"call_id":call.id,"name":call.name,"status":"complete","execution_attempted":true,"result":result,"errors":[]}}
var packets: Array=[]
var callbacks: Array=[]
var compactions: Array=[]
var finished: Dictionary={}
var failures: Array=[]
var checks:=0
var frames: Frames
var registry: Registry
var window:=65536
var budget_retained_frame:=false
var hold_read_compaction:=false
var held_compaction: Callable
var held_packet: Dictionary={}
func check(value: bool,why: String) -> void:
	checks+=1
	if not value:failures.append(why)
func send(packet: Dictionary,done: Callable) -> Dictionary:
	packets.append(packet.duplicate(true));callbacks.append(done)
	for handle: Dictionary in packet.get("request_attachments",[]):
		if handle.source=="game_viewport":frames.delivered[handle.id]=true
	return {"ok":true}
func finish(result: Dictionary) -> void:finished=result
func compact(packet: Dictionary,done: Callable,_scope: Dictionary,_force: bool) -> void:
	compactions.append(packet.duplicate(true))
	if hold_read_compaction and packet.data.round==3:
		held_compaction=done;held_packet=packet.duplicate(true);return
	if budget_retained_frame and packet.data.round==3:
		var text_tokens:=ceili((str(packet.system).length()+JSON.stringify(packet.data).length())/2.0)
		window=text_tokens+int(packet.options.max_tokens)+1024+Vision.token_reserve([A])-1
	done.call({"ok":true,"packet":packet.duplicate(true)})
func context_limit() -> int:return window
func begin(runtime: RefCounted,checker: bool=true,user_images: Array=[]) -> String:
	packets.clear();callbacks.clear();compactions.clear();finished.clear();window=65536;budget_retained_frame=false;hold_read_compaction=false;held_compaction=Callable();held_packet={}
	frames=Frames.new();registry=Registry.new();registry.frames=frames
	var scope: Dictionary={"enabled_tools":["ui.screenshot","mods.list","ui.panels"],"compact_packet":compact,"context_limit":context_limit}
	if checker:scope.game_image_current=frames.current
	return runtime.start({"user":"Inspect the current game and available controls","user_images":user_images,"options":{"max_tokens":2400}},scope,registry,send,finish)
func reply(index: int,name: String,id: String) -> void:
	callbacks[index].call({"message":"","tool_calls":[{"id":id,"name":name,"arguments":{}}],"result":null})
func complete() -> void:
	if finished.is_empty():callbacks.back().call({"message":"Observed","tool_calls":[],"result":null})
func attachments(index: int) -> Array:return packets[index].get("request_attachments",[])
func no_pixels(value: Variant) -> bool:
	if value is PackedByteArray or value is Image or value is Texture2D:return false
	if value is String:return not value.begins_with("data:image/") and not value.contains("base64,")
	if value is Dictionary:
		for key: Variant in value:
			if key in ["bytes","base64"] or not no_pixels(value[key]):return false
	if value is Array:
		for item: Variant in value:
			if not no_pixels(item):return false
	return true
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var runtime:=Runtime.new();var token:=begin(runtime)
	reply(0,"ui.screenshot","capture_a")
	check(attachments(1)==[A] and frames.delivered.has(A.id),"a fresh capture is delivered once before its current-frame checker can confirm delivery")
	reply(1,"mods.list","readonly_mods")
	check(attachments(2)==[A],"the current delivered game image survives one read-only mods.list step")
	reply(2,"ui.panels","readonly_panels")
	check(attachments(3)==[A],"the same current game image survives an additional read-only ui.panels step")
	check(not frames.checked.is_empty() and frames.checked.all(func(handle: Dictionary):return handle==A),"retention is validated through the supplied live-frame checker")
	check(compactions[2].get("image_token_reserve",0)==Vision.token_reserve([A]) and compactions[3].get("image_token_reserve",0)==Vision.token_reserve([A]),"retained game-image cost is reserved before each compaction")
	check(compactions.all(func(packet: Dictionary):return not packet.has("request_attachments")),"compaction receives token cost and bounded receipt metadata without actual attachments")
	check(Vision.valid_reference(runtime._sessions[token].get("last_game_image",{})) and no_pixels(runtime._sessions[token].get("last_game_image",{})),"session retention stores only a valid opaque game-image descriptor")
	frames.live=false;reply(3,"mods.list","drop_stale")
	check(attachments(4).is_empty() and packets[4].image_token_reserve==0,"a false live-frame checker drops the image and its token reservation")
	frames.live=true;reply(4,"ui.panels","do_not_resurrect")
	check(attachments(5).is_empty(),"a dropped image cannot resurrect when the checker later becomes true")
	complete();check(finished.get("ok",false) and no_pixels(finished) and no_pixels(packets),"finished results and provider packets contain references without raw pixels")
	print("VISION_RETENTION_CASE readonly attachments=",[attachments(1).size(),attachments(2).size(),attachments(3).size(),attachments(4).size(),attachments(5).size()])
	runtime=Runtime.new();begin(runtime,true,[USER])
	check(attachments(0)==[USER],"existing player-image delivery still reaches the first request")
	reply(0,"ui.screenshot","replace_a")
	check(attachments(1).size()==2 and A in attachments(1) and USER in attachments(1),"a fresh game capture coexists with the original player image")
	reply(1,"ui.screenshot","replace_b")
	check(attachments(2).size()==2 and B in attachments(2) and USER in attachments(2) and not A in attachments(2),"a new capture replaces the previous retained game image")
	reply(2,"mods.list","retain_b")
	check(attachments(3).size()==2 and B in attachments(3) and USER in attachments(3) and not A in attachments(3),"read-only work retains the new capture and unchanged player-image behavior")
	check(packets[3].image_token_reserve==Vision.token_reserve([B,USER]),"mixed player and retained-game image costs are reserved together")
	check(frames.checked.all(func(handle: Dictionary):return handle.source=="game_viewport"),"the live-game-frame checker never controls player reference images")
	complete()
	runtime=Runtime.new();begin(runtime)
	reply(0,"ui.screenshot","capture_before_compaction");hold_read_compaction=true
	reply(1,"mods.list","hold_compaction")
	check(packets.size()==2 and held_compaction.is_valid() and held_packet.get("image_token_reserve",0)==Vision.token_reserve([A]),"awaited compaction reserves the retained frame before the next provider request is sent")
	frames.live=false;held_compaction.call({"ok":true,"packet":held_packet.duplicate(true)})
	var dropped_during_compaction: bool=packets.size()==3 and attachments(2).is_empty() and packets[2].image_token_reserve==0
	frames.live=true;reply(2,"ui.panels","after_compaction_invalidation")
	check(dropped_during_compaction and attachments(3).is_empty(),"a frame invalidated during compaction is dropped before send and cannot later resurrect")
	complete()
	runtime=Runtime.new();begin(runtime,false)
	reply(0,"ui.screenshot","without_checker")
	check(attachments(1)==[A],"without a checker the fresh screenshot still reaches its immediate next request")
	reply(1,"mods.list","without_checker_read")
	check(attachments(2).is_empty() and packets[2].image_token_reserve==0,"without a live-frame checker an old game capture is not retained")
	complete()
	runtime=Runtime.new();begin(runtime)
	reply(0,"ui.screenshot","fallback_capture")
	callbacks[1].call({"error":{"message":"This model does not support image input"}})
	check(packets.size()==3 and attachments(2).is_empty() and packets[2].image_token_reserve==0,"explicit image rejection retries the same request without image or token reserve")
	reply(2,"mods.list","after_fallback")
	check(attachments(3).is_empty() and packets[3].image_token_reserve==0,"image fallback clears retention across later read-only steps despite a live checker")
	check(packets[2].data.source_user==packets[1].data.source_user and "CANNOT see" in packets[2].data.image_notice,"image fallback preserves the original request and discloses unavailable pixels")
	complete()
	runtime=Runtime.new();begin(runtime)
	reply(0,"ui.screenshot","budget_capture");budget_retained_frame=true
	reply(1,"mods.list","budget_retained_read")
	check(finished.get("code")=="context_too_large_no_compactable_span" and packets.size()==2,"retained image reserve can block an over-budget follow-up before provider send")
	var details: Dictionary=finished.get("failure",{}).get("details",{})
	print("VISION_RETENTION_BUDGET ",{"provider_packets":packets.size(),"window":window,"details":details})
	check(not details.is_empty() and int(details.get("estimated_input_tokens",0))-Vision.token_reserve([A])+2400+1024<=window and int(details.get("estimated_input_tokens",0))+2400+1024>window,"negative budget case proves the text fits and only retained-image cost exceeds the context limit")
	complete()
	runtime=Runtime.new();begin(runtime)
	registry.handles=[A.duplicate(true)];registry.handles[0]["bytes"]=PackedByteArray([1,2,3])
	reply(0,"ui.screenshot","invalid_descriptor")
	check(finished.get("code")=="vision_invalid_reference" and packets.size()==1,"raw pixel bytes in a capture receipt cannot become an image attachment or retained frame")
	print("VISION_RETENTION_TESTS ","PASS" if failures.is_empty() else failures,"; ",checks," checks");quit(0 if failures.is_empty() else 1)
