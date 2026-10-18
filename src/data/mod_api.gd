extends RefCounted
## Opt-in public mod contracts; never reflects arbitrary Node/Object methods.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const PRIVATE := ["api_key","apikey","access_token","refresh_token","password","authorization","secret","credentials"]
const JSON_TYPES := [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_ARRAY,TYPE_DICTIONARY]
var refs: Dictionary={}
var sequence:=0

func reset() -> void: refs.clear()

func contract(mod: Node) -> Dictionary:
	if not mod.has_method("api_info") or not mod.has_method("api_has"): return {}
	if mod.get_method_argument_count("api_info")!=0 or mod.get_method_argument_count("api_has")!=1: return {}
	var info: Variant=mod.call("api_info")
	return info if info is Dictionary and info.get("methods") is Dictionary else {}

func signature(mod: Node,method: String) -> Dictionary:
	if method.begins_with("_") or not method.is_valid_identifier(): return {}
	# Only methods actually declared by this mod's script, excluding inherited
	# engine methods (free, call, set, etc.), may enter the contract.
	var script: Script=mod.get_script()
	if script==null or script.resource_path.is_empty(): return {}
	var folder: String=script.resource_path.get_base_dir()
	var prefix: String=folder if folder.ends_with("/") else folder+"/"
	while script!=null and script.resource_path.begins_with(prefix):
		for row: Dictionary in script.get_script_method_list():
			if str(row.name)!=method or int(row.get("flags",0))&METHOD_FLAG_VARARG: continue
			if row.get("args",[]).size()>16: return {}
			for arg: Dictionary in row.get("args",[]):
				if int(arg.type) not in JSON_TYPES or str(arg.name).to_lower() in PRIVATE: return {}
			return row
		script=script.get_base_script()
	return {}

func discover(id: String,mod: Node,args: Dictionary) -> Dictionary:
	var info:=contract(mod)
	if info.is_empty(): return Data.failed("mods.api_unavailable")
	var matches: Array=[]
	var names: Array=info.methods.keys(); names.sort()
	var search: String=str(args.get("search","")).to_lower()
	for key: Variant in names:
		if not key is String or (search!="" and not key.to_lower().contains(search)): continue
		if not mod.call("api_has",key): continue
		var spec:=signature(mod,key)
		if spec.is_empty(): continue
		matches.append({"method":key,"spec":spec})
	var offset:=maxi(0,int(args.get("offset",0))); var limit:=clampi(int(args.get("limit",25)),1,100)
	var rows: Array=[]
	for item: Dictionary in matches.slice(offset,offset+limit):
		sequence+=1
		var token:="mod-api:"+str(sequence)
		var exported: Variant=info.methods[item.method]
		refs[token]={"id":id,"mod":weakref(mod),"method":item.method,"spec":item.spec.duplicate(true),"level":info.get("api_level"),"version":info.get("mod_version"),"export":exported.duplicate(true) if exported is Dictionary or exported is Array else exported,"expires":Time.get_ticks_msec()+600000}
		var parameters: Array=[]
		var defaults: Array=item.spec.get("default_args",[])
		var required: int=item.spec.args.size()-defaults.size()
		for i: int in range(item.spec.args.size()):
			var arg: Dictionary=item.spec.args[i]
			var parameter:={"name":str(arg.name),"type":"json" if arg.type==TYPE_NIL else type_string(arg.type),"required":i<required}
			if i>=required: parameter["default"]=sanitize(defaults[i-required],{"nodes":1024})
			parameters.append(parameter)
		rows.append({"ref":token,"method":item.method,"parameters":parameters,"minimum_arguments":required,"maximum_arguments":item.spec.args.size(),"api_since":info.methods[item.method]})
	while refs.size()>512: refs.erase(refs.keys()[0])
	return Data.success({"mod":id,"api_level":info.get("api_level"),"mod_version":info.get("mod_version"),"config_files":sanitize(info.get("config_files",[]),{"nodes":1024}),"methods":rows,"total":matches.size(),"has_more":offset+rows.size()<matches.size(),"next_offset":offset+rows.size(),"basis":"Methods explicitly exported by this enabled mod's api_info/api_has contract; signatures from its actual script. Availability is not proof of completion. Configuration APIs change mod configuration, not an object's operational switch."})

func invoke(api: Node,args: Dictionary) -> Dictionary:
	var token: String=str(args.get("ref",""))
	if not refs.has(token): return Data.failed("mods.api_ref_expired")
	var entry: Dictionary=refs[token]; var mod: Variant=entry.mod.get_ref()
	if not is_instance_valid(mod) or api.call("get_mod",entry.id)!=mod or Time.get_ticks_msec()>entry.expires: return Data.failed("mods.api_ref_expired")
	var info:=contract(mod)
	if info.is_empty() or not info.methods.has(entry.method) or not mod.call("api_has",entry.method) or info.get("api_level")!=entry.level or info.get("mod_version")!=entry.version or info.methods[entry.method]!=entry.export or signature(mod,entry.method)!=entry.spec: return Data.failed("mods.api_contract_changed")
	var values: Variant=args.get("arguments",[])
	if not values is Array or not Data.plain(values): return Data.failed("mods.api_invalid_arguments")
	var parameters: Array=entry.spec.args
	var required: int=parameters.size()-entry.spec.get("default_args",[]).size()
	if values.size()<required or values.size()>parameters.size(): return Data.failed("mods.api_argument_count")
	values=values.duplicate(true)
	for i: int in range(values.size()):
		var expected: int=parameters[i].type
		if expected==TYPE_NIL: continue
		if expected==TYPE_INT and values[i] is int: continue
		if expected==TYPE_INT and Data.number(values[i]) and float(values[i])==floorf(float(values[i])):
			if float(values[i])>=9223372036854775808.0 or float(values[i])< -9223372036854775808.0: return Data.failed("mods.api_argument_type")
			values[i]=int(values[i])
		elif expected==TYPE_FLOAT and Data.number(values[i]): values[i]=float(values[i])
		elif typeof(values[i])!=expected: return Data.failed("mods.api_argument_type")
	var returned: Variant=mod.callv(entry.method,values)
	var budget:={"nodes":4096,"characters":65536,"truncated":false}
	var result: Variant=sanitize(returned,budget)
	var bindings: Dictionary={}
	var defaults: Array=entry.spec.get("default_args",[])
	for i: int in range(parameters.size()): bindings[str(parameters[i].name)]=values[i] if i<values.size() else defaults[i-required]
	var response:=Data.success({"mod":entry.id,"method":entry.method,"argument_values":sanitize(bindings,{"nodes":2048}),"returned":result,"observed_return":true,"truncated":budget.truncated,"dispatched":true,"completed":false,"instruction":"returned is the actual observed method result at invocation time. argument_values are CALLER INPUTS/defaults, not measurements: never describe a supplied formula/test base as an observed world value. A query's returned state is valid evidence; do not repeatedly reread merely because this conservative receipt says dispatched. Use a NEW call ID for a fresh invocation/readback; the same ID replays its recorded result. Each new ID really invokes this API, so never blindly retry a mutation. For a MUTATION, a boolean alone may indicate rejection or pending work: read actual entity/configuration/economy afterward before claiming completed gameplay. Callbacks may defer work until a later frame: put readback in the NEXT batch/round. Configuration changes must be described as configuration changes; use your own patch owner and never remove another mod's patches."})
	response["evidence"]="Actual return value of the observed declared public method; gameplay completion requires independent readback."
	return response

static func sanitize(value: Variant,budget: Dictionary,depth: int=0) -> Variant:
	budget.nodes-=1
	if budget.nodes<0 or depth>16:
		budget["truncated"]=true; return null
	if value is String:
		var length:=mini(4000,int(budget.get("characters",65536)))
		if value.length()>length: budget["truncated"]=true
		var text: String=value.left(length)
		budget["characters"]=maxi(0,int(budget.get("characters",65536))-text.length())
		return text
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:
			if budget.nodes<0: budget["truncated"]=true; break
			if key is String and key.to_lower() not in PRIVATE: out[key]=sanitize(value[key],budget,depth+1)
		return out
	if value is Array or value is PackedStringArray:
		var out: Array=[]
		for item: Variant in value:
			if budget.nodes<0: budget["truncated"]=true; break
			out.append(sanitize(item,budget,depth+1))
		return out
	if value==null or value is bool or Data.number(value): return value
	budget["truncated"]=true
	return null
