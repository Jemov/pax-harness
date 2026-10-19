extends SceneTree
const Runtime=preload("res://mods/pax_harness/src/runtime/universal_runtime.gd")
const Access=preload("res://mods/pax_harness/src/data/mod_access.gd")
const Registry=preload("res://mods/pax_harness/src/runtime/tools/registry.gd")
class Campaign extends RefCounted:
	var world: Node
	func scene_root() -> Node:return world
	func is_active() -> bool:return true
class Mod extends Node:
	func ui_tabs() -> Array:return [{"id":"repair","caption":"Actual repair panel","fn":Callable(self,"open_panel")}]
	func open_panel() -> void:pass
class API extends Node:
	var mod: Node
	func get_mod(id: String) -> Node:return mod if id=="example" else null
	func world_busy() -> bool:return false
class Owner extends Node:
	var _mod_access: RefCounted
	func get_setting(_key: String,fallback: Variant=null) -> Variant:return fallback
var callbacks: Array=[]
var packets: Array=[]
var events: Array=[]
var finished: Dictionary={}
var failures: Array=[]
var checks:=0
func send(packet: Dictionary,done: Callable) -> Dictionary:
	packets.append(packet);callbacks.append(done);return {"ok":true}
func finish(result: Dictionary) -> void:finished=result
func trace(kind: String,payload: Dictionary) -> void:events.append({"kind":kind,"payload":payload.duplicate(true)})
func check(value: bool,why: String) -> void:
	checks+=1
	if not value:failures.append(why)
func reply(id: String,name: String,args: Dictionary) -> Dictionary:return {"message":"","tool_calls":[{"id":id,"name":name,"arguments":args}],"result":null}
func begin(runtime: RefCounted,registry: RefCounted,game: RefCounted) -> void:
	callbacks.clear();packets.clear();events.clear();finished.clear()
	runtime.start({"user":"Read the actual repair controls"},{"channel":"assistant","game":game,"enabled_tools":["mods.ui"],"trace":trace},registry,send,finish)
	callbacks[0].call(reply("load_mods","tools.load",{"groups":["mods"]}))
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var mod:=Mod.new();root.add_child(mod)
	var button:=Button.new();button.text="Repair current unit";mod.add_child(button)
	var amount:=SpinBox.new();amount.min_value=0;amount.max_value=100;amount.value=7;mod.add_child(amount)
	var api:=API.new();api.mod=mod;root.add_child(api)
	var game:=Campaign.new();game.world=mod
	var owner:=Owner.new();root.add_child(owner);owner._mod_access=Access.new();owner._mod_access.setup(api,game)
	var registry:=Registry.new();registry.setup(game,owner)
	var runtime:=Runtime.new()
	await process_frame
	begin(runtime,registry,game)
	for index: int in 20:
		if not finished.is_empty():break
		callbacks[index+1].call(reply("unchanged_"+str(index),"mods.ui",{"mod":"example"}))
	var reads: Array=finished.get("receipts",[]).filter(func(receipt: Dictionary):return receipt.name=="mods.ui")
	print("STABLE_REF_RUNTIME_UNCHANGED code=",finished.get("code")," rounds=",finished.get("rounds")," reads=",reads.size())
	check(not finished.get("receipts",[]).is_empty() and finished.receipts[0].name=="tools.load" and finished.receipts[0].status=="complete","actual assistant group discovery runs before mods.ui")
	check(finished.get("code")=="agent_loop_detected" and finished.get("rounds")==9,"real Runtime stops unchanged mods.ui after eight reads rather than exhausting twenty rounds")
	check(reads.size()==8 and reads.all(func(receipt: Dictionary):return receipt.status=="complete" and receipt.execution_attempted and not receipt.get("deduplicated",false)),"the no-progress guard observes eight real Registry/ModAccess handler executions")
	var identical: bool=not reads.is_empty()
	for receipt: Dictionary in reads:
		if receipt.result!=reads[0].result:identical=false
	check(identical,"opaque refs stay identical inside actual tool receipt result signatures")
	var repetitions: Array=[]
	for event: Dictionary in events:
		if event.kind=="loop.warning" and event.payload.name=="mods.ui":repetitions.append(event.payload.repetitions)
	check(repetitions==[3,5,8],"real unchanged UI reads emit loop warnings at repetitions three, five and eight")
	check(packets.any(func(packet: Dictionary):return packet.data.get("loop_feedback",{}).get("name")=="mods.ui" and packet.data.loop_feedback.repetitions==3),"the fake provider receives actual no-progress feedback in the following request")
	begin(runtime,registry,game)
	for index: int in 10:
		amount.value=10+index
		callbacks[index+1].call(reply("moving_"+str(index),"mods.ui",{"mod":"example"}))
	callbacks[11].call({"message":"Observed the changed values","tool_calls":[],"result":null})
	reads=finished.get("receipts",[]).filter(func(receipt: Dictionary):return receipt.name=="mods.ui")
	check(finished.get("ok",false) and finished.get("code")=="text_complete" and not events.any(func(event: Dictionary):return event.kind=="loop.warning"),"actual changing UI values remain progress and can finish normally")
	var observed_values: Array=[]
	for receipt: Dictionary in reads:
		for control: Dictionary in receipt.result.controls:
			if control.kind=="SpinBox":observed_values.append(control.value)
	print("STABLE_REF_RUNTIME_VALUES ",observed_values)
	check(observed_values==[10.0,11.0,12.0,13.0,14.0,15.0,16.0,17.0,18.0,19.0],"reused refs do not memoize changed native values in real receipts")
	check(reads.size()==10 and reads.all(func(receipt: Dictionary):return receipt.execution_attempted and not receipt.get("deduplicated",false)),"each fresh read call ID still invokes the current handler")
	owner.queue_free();api.queue_free();mod.queue_free();await process_frame
	print("STABLE_REF_RUNTIME_TESTS ","PASS" if failures.is_empty() else failures,"; ",checks," checks");quit(0 if failures.is_empty() else 1)
