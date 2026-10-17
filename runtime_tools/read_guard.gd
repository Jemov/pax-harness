extends RefCounted
## Optimistic concurrency using the actual read handler, never a model assertion.
const Public = preload("res://mods/pax_harness/runtime_tools/public_handlers.gd")
const Native = preload("res://mods/pax_harness/runtime_tools/native_current.gd")
var reads: Dictionary = {}
const REQUIRED := {"orders.update":"orders.read","orders.cancel":"orders.read","research.confirm":"research.read","research.cancel":"research.read","military.order":"military.read","money.add":"money.read","resources.add":"resources.read","bodies.set_parameter":"bodies.read","provinces.set_owner":"provinces.read","diplomacy.change_relation":"diplomacy.read","diplomacy.declare_war":"diplomacy.read"}

static func key(name: String, args: Dictionary) -> String:
	var identity: Dictionary = {}
	for field: String in ["body","country","entry_id"]:
		if args.has(field): identity[field] = args[field]
	if name == "provinces.read": identity.id = args.id
	return name+JSON.stringify(identity)

func observed(name: String, args: Dictionary, executed: Dictionary) -> void:
	if not executed.get("ok",false): return
	reads[key(name,args)] = {"hash":JSON.stringify(executed.get("result",{})).sha256_text(),"revision":str(executed.get("result",{}).get("revision","")) if executed.get("result") is Dictionary else ""}

func check(game: RefCounted, name: String, args: Dictionary) -> Dictionary:
	if name in ["prompts.update","prompts.patch","plan.update","instructions.update"]:
		var read_name: String = name.get_slice(".",0)+".read"
		var read_key: String = key(read_name,args)
		if name == "instructions.update": read_key += str(args.get("scope","chat"))
		if not reads.has(read_key): return {"ok":false,"code":"tools.read_required","result":{"read_tool":read_name}}
		if reads[read_key].revision != args.expected_revision: return {"ok":false,"code":"tools.source_changed_read_again"}
	if not REQUIRED.has(name): return {"ok":true}
	var reader: String = REQUIRED[name]
	var input: Dictionary = {}
	for field: String in ["body","country"]:
		if args.has(field): input[field] = args[field]
	if reader == "provinces.read": input.id = args.id
	var read_key: String = key(reader,input)
	if not reads.has(read_key): return {"ok":false,"code":"tools.read_required","result":{"read_tool":reader,"arguments":input}}
	var current: Dictionary = Native.execute(game,reader,input) if reader in ["orders.read","research.read","military.read"] else Public.execute(game,reader,input)
	if not current.get("ok",false): return current
	if reads[read_key].hash != JSON.stringify(current.get("result",{})).sha256_text():
		reads.erase(read_key)
		return {"ok":false,"code":"tools.source_changed_read_again","result":{"read_tool":reader,"arguments":input}}
	return {"ok":true}
