extends RefCounted
const VM=preload("res://mods/pax_harness/src/creation/program_vm.gd")
var error: Dictionary={}
var nodes:=2048
static func keys(d: Dictionary,allowed: Array,required: Array=[]) -> bool:
	return required.all(func(k: String): return d.has(k)) and d.keys().all(func(k: Variant): return k is String and k in allowed)
static func id(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z][a-z0-9_]{0,47}$").search(value)!=null
static func path(value: Variant) -> bool:
	return value is String and value.length()<=200 and RegEx.create_from_string("^[a-zA-Z_][a-zA-Z0-9_]*(\\.[a-zA-Z0-9_]+)*$").search(value)!=null
func bad(at: String,detail: String) -> bool:
	if error.is_empty(): error={"ok":false,"code":"program.invalid_source","path":at,"detail":detail,"result":{"path":at,"detail":detail}}
	return false
func visit(at: String,depth: int) -> bool:
	nodes-=1
	return bad(at,"Program exceeds AST size/depth budget") if nodes<0 or depth>20 else true
static func validate(program: Variant) -> Dictionary:
	var checker:=new()
	if checker.program(program): return {"ok":true,"result":{"valid":true}}
	return checker.error
func program(p: Variant) -> bool:
	if not p is Dictionary or not VM.plain(p) or not keys(p,["version","state","events","handlers","ui"],["version","state","events","handlers"]): return bad("program","Expected version, state, events, handlers; optional ui")
	if p.version!=1 or not p.state is Dictionary or not p.events is Array or p.events.is_empty() or p.events.size()>8 or not p.handlers is Dictionary: return bad("program","Version must be 1; state/handlers objects, 1..8 events")
	var names: Array=[]; var interactions: Array=[]
	for i: int in p.events.size():
		var e: Variant=p.events[i]; var at: String="program.events."+str(i)
		if not e is Dictionary or not id(e.get("name")) or e.get("name") in names: return bad(at,"Events need unique identifier names")
		names.append(e.name)
		match e.get("type"):
			"tick":
				if not keys(e,["name","type","seconds"],["name","type","seconds"]) or not VM.numeric(e.seconds) or float(e.seconds)<0.05 or float(e.seconds)>3600: return bad(at,"tick.seconds must be 0.05..3600")
			"day_change":
				if not keys(e,["name","type"],["name","type"]): return bad(at,"Unexpected day event fields")
			"interaction":
				if not keys(e,["name","type"],["name","type"]): return bad(at,"Unexpected interaction fields")
				interactions.append(e.name)
			"plane_cross","sphere_enter":
				if not keys(e,["name","type","adapter","center_km","radius_km","normal","direction","cooldown_seconds"],["name","type","adapter","center_km","radius_km"]) or e.adapter!="dyson" or not VM.vector(e.center_km) or not VM.numeric(e.radius_km) or float(e.radius_km)<0.001 or float(e.radius_km)>1e7: return bad(at,"Sensor requires adapter dyson, center_km:[x,y,z], radius_km:0.001..1e7")
				if e.type=="plane_cross":
					if not VM.vector(e.get("normal")) or Vector3(e.normal[0],e.normal[1],e.normal[2]).length()<0.001 or e.get("direction","forward") not in ["forward","backward","both"]: return bad(at,"Plane needs nonzero normal and forward/backward/both direction")
				if not VM.numeric(e.get("cooldown_seconds",0)) or float(e.get("cooldown_seconds",0))<0 or float(e.get("cooldown_seconds",0))>3600: return bad(at,"cooldown_seconds must be 0..3600")
			_: return bad(at,"Unknown event type")
	if p.handlers.keys().any(func(k: Variant): return k not in names) or names.any(func(k: String): return not p.handlers.has(k)): return bad("program.handlers","Each event needs exactly one handler")
	for name_: String in names:
		if not block(p.handlers[name_],"program.handlers."+name_,0): return false
	var ui: Variant=p.get("ui",{})
	if not ui is Dictionary or not keys(ui,["fields","buttons"]): return bad("program.ui","Only fields and buttons are supported")
	for type_: String in ["fields","buttons"]:
		var rows: Variant=ui.get(type_,[])
		if not rows is Array or rows.size()>12: return bad("program.ui."+type_,"At most 12 rows")
		for row: Variant in rows:
			var field: String="path" if type_=="fields" else "event"
			if not row is Dictionary or not keys(row,["label",field],["label",field]) or not label(row.label): return bad("program.ui."+type_,"Each row requires label:{ru,en} and "+field)
			if type_=="fields" and (not path(row.path) or not str(row.path).begins_with("state.")): return bad("program.ui.fields","Fields can read state paths only")
			if type_=="buttons" and row.event not in interactions: return bad("program.ui.buttons","Button event must name an interaction handler")
	return true
static func label(value: Variant) -> bool:
	return value is Dictionary and keys(value,["ru","en"],["ru","en"]) and [value.ru,value.en].all(func(s: Variant): return s is String and not s.strip_edges().is_empty() and s.length()<=160)
func expression(value: Variant,at: String,depth: int) -> bool:
	if not visit(at,depth): return false
	if value is Array:
		for i: int in value.size():
			if not expression(value[i],at+"."+str(i),depth+1): return false
	elif value is Dictionary:
		if value.has("literal"): return true if keys(value,["literal"]) else bad(at,"literal takes one field")
		if value.has("get"):
			if not keys(value,["get","default"],["get"]) or not path(value["get"]): return bad(at,"get needs a dotted data path")
			return expression(value.default,at+".default",depth+1) if value.has("default") else true
		if value.has("call"):
			if not keys(value,["call","args"],["call"]) or value.call not in VM.QUERIES or not value.get("args",{}) is Dictionary: return bad(at,"Only read-only host queries are allowed in expressions; use a call statement for world changes")
			return expression(value.get("args",{}),at+".args",depth+1)
		if value.has("op"):
			if not keys(value,["op","args"],["op","args"]) or value.op not in VM.OPS or not value.args is Array: return bad(at,"Unknown operator or invalid args")
			var count: int=value.args.size()
			if (value.op in ["not","len"] and count!=1) or (value.op=="clamp" and count!=3) or (value.op in ["and","or","concat"] and (count<1 or count>16)) or (value.op=="at" and count not in [2,3]) or (value.op not in ["not","len","clamp","and","or","concat","at"] and count!=2): return bad(at,"Wrong operator arity")
			return expression(value.args,at+".args",depth+1)
		for key: String in value:
			if not expression(value[key],at+"."+key,depth+1): return false
	return true
func block(value: Variant,at: String,depth: int) -> bool:
	if not value is Array or value.size()>128 or not visit(at,depth): return bad(at,"Expected a block of at most 128 statements")
	for i: int in value.size():
		var s: Variant=value[i]; var p: String=at+"."+str(i)
		if not s is Dictionary or not visit(p,depth+1): return bad(p,"Expected statement object")
		if s.has("let") or s.has("set"):
			var field: String="let" if s.has("let") else "set"
			if not keys(s,[field,"value","key"],[field,"value"]) or (field=="let" and (not id(s.let) or s.let in ["state","event","self","local"])) or (field=="set" and (not path(s.set) or not str(s.set).begins_with("state."))): return bad(p,"let needs a local name; set can write state.* only")
			if not expression(s.value,p+".value",depth+1) or (s.has("key") and not expression(s.key,p+".key",depth+1)): return false
		elif s.has("if"):
			if not keys(s,["if","then","else"],["if","then"]) or not expression(s["if"],p+".if",depth+1) or not block(s["then"],p+".then",depth+1) or not block(s.get("else",[]),p+".else",depth+1): return bad(p,"Invalid if block")
		elif s.has("for") or s.has("while"):
			var field: String="for" if s.has("for") else "while"
			if not keys(s,[field,"in","do"],[field,"do"]) or (field=="for" and (not id(s["for"]) or s["for"] in ["state","event","self","local"] or not s.has("in"))): return bad(p,"Invalid loop")
			if not expression(s["in"] if field=="for" else s["while"],p+".condition",depth+1) or not block(s["do"],p+".do",depth+1): return false
		elif s.has("call"):
			if not keys(s,["call","args","store"],["call"]) or s.call not in VM.CALLS or not s.get("args",{}) is Dictionary or (s.has("store") and (not id(s.store) or s.store in ["state","event","self","local"])): return bad(p,"Unknown host operation or invalid store")
			if not expression(s.get("args",{}),p+".args",depth+1): return false
		elif s.has("return"):
			if not keys(s,["return"]) or not expression(s["return"],p+".return",depth+1): return false
		else: return bad(p,"Unknown statement")
	return true
static func schema() -> Dictionary:
	return {"version":1,"format":"program:{version:1,state:{...plain data},events:[...],handlers:{event_name:[statements]},ui?:{fields:[{label:{ru,en},path:state.x}],buttons:[{label:{ru,en},event:interaction_name}]}} attached to object.program; separate behavior project {id,name:{ru,en},object_id,program,preserve_state?:true} installs/revises logic on any approved object",
		"events":{"tick":"{name,type:tick,seconds:0.05..3600}","plane_cross":"{name,type:plane_cross,adapter:dyson,center_km:[x,y,z],normal:[x,y,z],radius_km:number,direction:forward|backward|both,cooldown_seconds?:number}","sphere_enter":"{name,type:sphere_enter,adapter:dyson,center_km:[x,y,z],radius_km:number,cooldown_seconds?:number}","interaction":"{name,type:interaction}; requires a UI button to trigger","day_change":"{name,type:day_change}"},
		"coordinates":"Sensors use kilometres relative to owner object's centre and oriented local axes; +Z points away from parent body for original authored placement. radius is sensor range, NOT automatic hull clearance: write your own condition using event.radial_km and event.actor.length_km.",
		"expressions":{"literal":"JSON primitives/arrays/objects recursively evaluate; {literal:any_plain_JSON} prevents interpretation","get":"{get:state.charge} or {get:local.body} or {get:event.actor.id}; optional default. let/store names are available both directly and under local.*","query":"{call:object.read|actor.read|actors.list,args:{...expressions}}; mutating calls are statements only","op":"{op:one_of_operators,args:[expressions]}","operators":VM.OPS},
		"statements":["{let:local_name,value:expression}","{set:state.path,value:expression}; optional key:expression writes a string key in that state dictionary","{if:expression,then:[statements],else?:[statements]}","{for:local_name,in:array_expression,do:[statements]} (at most 64 items)","{while:expression,do:[statements]} (shared instruction budget)","{call:host_operation,args:{...expressions},store?:local_name}","{return:expression}"],
		"context":"self:{id,body}, state:campaign-persistent variables, event:{name,time,dt?,actor?,radial_km?,day?,days?}. Locals last one invocation. Calls store their observed result, not the receipt envelope.",
		"limits":"4096 shared instructions per handler, AST depth20/nodes2048, program/state64KiB, 8 events, at most12 UI fields/buttons each. Errors stop this program, preserving partial effects and exact error path; never automatically replay mutations. No filesystem/network/code-loading/native reflection.",
		"counter_example":{"version":1,"state":{"count":0},"events":[{"name":"pulse","type":"tick","seconds":1}],"handlers":{"pulse":[{"set":"state.count","value":{"op":"+","args":[{"get":"state.count"},1]}}]},"ui":{"fields":[{"label":{"ru":"Счётчик","en":"Counter"},"path":"state.count"}]}}}
