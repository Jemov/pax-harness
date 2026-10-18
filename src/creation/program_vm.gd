extends RefCounted
## Small interpreted language: programs are authored by the agent, native methods
## are supplied by the host. No dynamic GDScript, reflection or external process.
const Data=preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const OPS=["+","-","*","/","%","==","!=",">",">=","<","<=","and","or","not","min","max","clamp","len","concat","vadd","vscale","dot","distance","at"]
const CALLS=["body.read","body.set","actor.read","actors.list","actor.spawn","actor.move","actor.set","object.read","object.move","object.damage","resource.read","resource.add","ui.message"]
const QUERIES=["body.read","actor.read","actors.list","object.read","resource.read"]
var host: Callable
var context: Dictionary
var remaining:=4096
var error: Dictionary={}
var returned:=false
func fail(code: String,path: String,detail: String="") -> Variant:
	if error.is_empty(): error={"code":code,"path":path,"detail":detail}
	return null
func spend(path: String) -> bool:
	remaining-=1
	if remaining<0: fail("program.instruction_limit",path); return false
	return error.is_empty() and not returned
static func plain(value: Variant) -> bool:
	return Data.plain(value) and JSON.stringify(value).length()<=65536
func run(statements: Array, state: Dictionary,event: Dictionary, self_info: Dictionary, callback: Callable) -> Dictionary:
	host=callback; context={"state":state.duplicate(true),"event":event.duplicate(true),"self":self_info.duplicate(true),"local":{}}
	remaining=4096; error={}; returned=false
	block(statements,"handlers."+str(event.get("name","")))
	return {"ok":error.is_empty(),"state":context.state,"error":error,"instructions":4096-remaining}
func read(path: String, fallback: Variant=null, has_default: bool=false) -> Variant:
	var value: Variant=context
	for part: String in path.split("."):
		if value is Dictionary and value.has(part): value=value[part]
		elif value is Array and part.is_valid_int() and int(part)>=0 and int(part)<value.size(): value=value[int(part)]
		elif has_default: return fallback
		else: return fail("program.missing_value",path)
	return value
func write(path: String,value: Variant) -> void:
	var parts: PackedStringArray=path.split("."); var target: Dictionary=context
	for i: int in range(parts.size()-1):
		if not target.has(parts[i]) or not target[parts[i]] is Dictionary: fail("program.invalid_assignment",path); return
		target=target[parts[i]]
	target[parts[-1]]=value
	if not plain(context.state): fail("program.state_limit",path)
func expr(value: Variant,path: String) -> Variant:
	if not spend(path): return null
	if value is Array:
		var rows: Array=[]
		for i: int in value.size(): rows.append(expr(value[i],path+"."+str(i)))
		return rows
	if not value is Dictionary: return value
	if value.has("literal"): return value.literal.duplicate(true) if value.literal is Dictionary or value.literal is Array else value.literal
	if value.has("get"):
		var current: Variant=context; var found:=true
		for part: String in str(value["get"]).split("."):
			if current is Dictionary and current.has(part): current=current[part]
			elif current is Array and part.is_valid_int() and int(part)>=0 and int(part)<current.size(): current=current[int(part)]
			else: found=false; break
		if found: return current
		return expr(value.default,path+".default") if value.has("default") else fail("program.missing_value",str(value["get"]))
	if value.has("call"):
		var arguments: Variant=expr(value.get("args",{}),path+".args")
		if not error.is_empty(): return null
		if value.call not in QUERIES: return fail("program.query_required",path)
		var receipt: Dictionary=host.call(str(value.call),arguments)
		return receipt.get("result") if receipt.get("ok",false) else fail(str(receipt.get("code","program.host_error")),path,str(receipt.get("detail","")))
	if not value.has("op"):
		var result: Dictionary={}
		for key: String in value: result[key]=expr(value[key],path+"."+key)
		return result
	var op: String=str(value.op); var inputs: Array=value.args
	if op in ["and","or"]:
		for item: Variant in inputs:
			var flag: bool=bool(expr(item,path+".args"))
			if flag==(op=="or"): return flag
		return op=="and"
	var evaluated: Variant=expr(inputs,path+".args")
	if not error.is_empty(): return null
	var args: Array=evaluated
	if op=="not": return not bool(args[0])
	if op=="==": return args[0]==args[1]
	if op=="!=": return args[0]!=args[1]
	if op=="at":
		var fallback: Variant=args[2] if args.size()>2 else null
		if args[0] is Dictionary and args[1] is String: return args[0].get(args[1],fallback)
		if args[0] is Array and numeric(args[1]) and float(args[1])==floorf(float(args[1])): return args[0][int(args[1])] if int(args[1])>=0 and int(args[1])<args[0].size() else fallback
		return fail("program.type_error",path,"at needs a map/string key or array/integer index")
	if op=="concat":
		var result: String=""
		for item: Variant in args: result+=str(item)
		return result if result.length()<=65536 else fail("program.value_limit",path)
	if op=="len":
		if args[0] is Array or args[0] is Dictionary: return args[0].size()
		if args[0] is String: return args[0].length()
		return fail("program.type_error",path,"len needs an array, object or string")
	if op in ["vadd","vscale","dot","distance"]:
		if not vector(args[0]) or (op!="vscale" and not vector(args[1])) or (op=="vscale" and not numeric(args[1])): return fail("program.type_error",path,"Expected 3D arrays")
		var a:=Vector3(args[0][0],args[0][1],args[0][2]); var b:=Vector3.ZERO
		if op!="vscale": b=Vector3(args[1][0],args[1][1],args[1][2])
		if op=="dot": return a.dot(b)
		if op=="distance": return a.distance_to(b)
		var v: Vector3=a+b if op=="vadd" else a*float(args[1])
		if not v.is_finite(): return fail("program.nonfinite",path)
		return [v.x,v.y,v.z]
	if not args.all(numeric): return fail("program.type_error",path,"Expected numbers")
	var a: float=float(args[0]); var b: float=float(args[1]) if args.size()>1 else 0
	var result: Variant
	match op:
		"+": result=a+b
		"-": result=a-b
		"*": result=a*b
		"/","%":
			if b==0: return fail("program.division_by_zero",path)
			result=a/b if op=="/" else fmod(a,b)
		">": return a>b
		">=": return a>=b
		"<": return a<b
		"<=": return a<=b
		"min": result=minf(a,b)
		"max": result=maxf(a,b)
		"clamp": result=clampf(a,b,float(args[2]))
		_: return fail("program.unknown_operator",path,op)
	return result if not result is float or is_finite(result) else fail("program.nonfinite",path)
static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
static func vector(value: Variant) -> bool:
	return value is Array and value.size()==3 and value.all(func(x: Variant): return numeric(x) and absf(float(x))<=1e15)
func block(statements: Array,path: String) -> void:
	for i: int in statements.size():
		var at: String=path+"."+str(i)
		if not spend(at): return
		var s: Dictionary=statements[i]
		if s.has("let"):
			var value: Variant=expr(s.value,at+".value"); context[str(s.let)]=value; context.local[str(s.let)]=value
		elif s.has("set"):
			var value: Variant=expr(s.value,at+".value")
			if not error.is_empty(): return
			if s.has("key"):
				var target: Variant=read(str(s["set"])); var key: Variant=expr(s.key,at+".key")
				if not target is Dictionary or not key is String: fail("program.type_error",at,"Dynamic assignment needs a dictionary and string key"); return
				target[key]=value
				if not plain(context.state): fail("program.state_limit",at)
			else: write(str(s["set"]),value)
		elif s.has("if"):
			if bool(expr(s["if"],at+".if")): block(s["then"],at+".then")
			else: block(s.get("else",[]),at+".else")
		elif s.has("for"):
			var items: Variant=expr(s["in"],at+".in")
			if not items is Array or items.size()>64: fail("program.iteration_limit",at); return
			for item: Variant in items:
				if not spend(at): return
				context[str(s["for"])]=item; context.local[str(s["for"])]=item; block(s["do"],at+".do")
		elif s.has("while"):
			while error.is_empty() and not returned and bool(expr(s["while"],at+".while")):
				if not spend(at): return
				block(s["do"],at+".do")
		elif s.has("return"): expr(s["return"],at+".return"); returned=true; return
		elif s.has("call"):
			var args: Variant=expr(s.get("args",{}),at+".args")
			if not error.is_empty(): return
			var receipt: Dictionary=host.call(str(s.call),args)
			if not receipt.get("ok",false): fail(str(receipt.get("code","program.host_error")),at,str(receipt.get("detail",""))); return
			if s.has("store"): context[str(s.store)]=receipt.get("result"); context.local[str(s.store)]=receipt.get("result")
