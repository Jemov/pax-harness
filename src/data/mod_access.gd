extends RefCounted
## Bounded mod data/UI navigation and opt-in exported public contracts.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Interface = preload("res://mods/pax_harness/src/ui/game/mod_interface.gd")
const PublicAPI = preload("res://mods/pax_harness/src/data/mod_api.gd")
const PRIVATE := ["api_key","apikey","access_token","refresh_token","password","authorization","secret"]
const EXCLUDED := ["pax_harness","ai_tuning","prompt_lab_local"]
var api: Node
var game: RefCounted
var interface: RefCounted = Interface.new()
var documents: Dictionary={}
var public_api: RefCounted=PublicAPI.new()
func setup(p_api: Node,p_game: RefCounted) -> void:
	api=p_api; game=p_game; documents.clear(); public_api.reset(); interface.setup(api,game)
static func definitions() -> Array:
	var text := {"type":"string","minLength":1,"maxLength":160}
	var page := {"type":"integer","minimum":1,"maximum":100}
	var offset := {"type":"integer","minimum":0}
	var rows: Array = [
		["mods.api","Discover ONE enabled mod's explicitly exported public API (api_info/api_has). Search/page actual method names, ordered JSON parameter signatures and opaque refs. This includes public functions without UI controls. No arbitrary engine/private methods. Configuration APIs change mod configuration, not an individual object's operation.",{"mod":text,"offset":offset,"limit":page,"search":{"type":"string","maxLength":160}},["mod"],false],
		["mods.invoke","Invoke ONE player-requested public function using a ref observed through mods.api and ordered JSON arguments matching its signature. Ref expires after 10 minutes or a changed contract/world. May change gameplay/configuration. Never claim completion from a dispatch or boolean alone: read back the actual entity/economy/configuration. Use only your own owner ID for extension patches and never remove another mod's patches.",{"ref":text,"arguments":{"type":"array","maxItems":16,"items":{}}},["ref"],true],
		["mods.list","Discover enabled gameplay/interface mods. Read mod IDs, versions and whether campaign state is readable. No settings, files or arbitrary code.",{},[],false],
		["mods.catalogue","List ONE enabled mod's own JSON content documents: entity definitions, resource/research configurations and other static content. Paginate/search metadata; inspect an actual returned document ref with mods.inspect. No game files or arbitrary paths.",{"mod":text,"offset":offset,"limit":page,"search":{"type":"string","maxLength":160}},["mod"],false],
		["mods.inspect","Browse ONE mod's live campaign-save state by a discovered JSON path, or a document ref from mods.catalogue. Start with path=[]; follow returned child paths to entities. Array indices may be integer numbers or canonical decimal strings. Paginate arrays/dictionaries; search filters immediate children and their bounded metadata. Embedded JSON databases are expanded by default; decode_json=false reads raw strings. Units and meanings belong to that mod; do not infer absent facts. Read-only, never arbitrary methods.",{"mod":text,"document":text,"decode_json":{"type":"boolean"},"path":{"type":"array","maxItems":16,"items":{"anyOf":[{"type":"string"},{"type":"integer","minimum":0}]}},"offset":offset,"limit":page,"search":{"type":"string","maxLength":160}},["mod"],false],
		["mods.ui","Inspect actual visible controls belonging to ONE enabled mod, including navigation buttons, hover-revealed navigation and open windows. Also discovers this mod's actual game-registered windows when navigation is folded; press their RegisteredModPanel refs to toggle through native navigation. Theme hover decoration does not grant ownership of native controls. Returns expiring opaque refs, supported actions, text and values. Search/paginate to find an entity; open it with mods.act, then inspect again. Never desktop input.",{"mod":text,"offset":offset,"limit":page,"search":{"type":"string","maxLength":160}},["mod"],false],
		["mods.act","Perform ONE player-requested action on an observed mod control or game-registered mod window returned by mods.ui. Use only its advertised action and ref. RegisteredModPanel press uses the game's window navigation. MenuButton press opens its native popup: inspect again for current options, then select an observed index. hover returns immediate revealed_controls with refs: use those refs for auto-closing menus; the original trigger is reactivated before their action, for at most two minutes. For a custom canvas/card, click_at uses observed local pixel x/y inside its bounds; do not guess a target's location. Can change gameplay through normal mod callbacks. No arbitrary methods/paths or hidden/disabled controls. Reinspect: dispatch does not prove completion.",{"ref":text,"action":{"type":"string","enum":["press","toggle","set_text","submit_text","set_number","select","select_tab","click_at","hover"]},"text":{"type":"string","maxLength":4000},"number":{"type":"number"},"checked":{"type":"boolean"},"index":{"type":"integer","minimum":0},"x":{"type":"number","minimum":0},"y":{"type":"number","minimum":0}},["ref","action"],true]
	]
	var result: Array=[]
	for row: Array in rows:
		result.append({"name":row[0],"id":row[0],"description":row[1],"arguments_schema":{"type":"object","properties":row[2],"required":row[3],"additionalProperties":false},"mutates_world":row[4],"handler_kind":"mod_access","capability":"installed_mod_campaign","after_state":"Actual bounded mod data or an interface dispatch receipt; no inferred completion."})
		# A public procedural API mixes queries and repeatable commands. Preserve
		# same-ID idempotency, but new IDs must observe/execute the function anew.
		if row[0]=="mods.invoke": result[-1]["deduplicate_arguments"]=false
	return result
func enabled(id: String) -> Node:
	if id in EXCLUDED or not is_instance_valid(api) or not api.has_method("get_mod"): return null
	var value: Variant=api.call("get_mod",id)
	return value if value is Node and is_instance_valid(value) and not value.is_queued_for_deletion() else null
func execute(name: String,args: Dictionary) -> Dictionary:
	if not is_instance_valid(game): return Data.failed("mods.inactive_world")
	if api.has_method("world_busy") and api.call("world_busy"): return Data.failed("mods.world_busy")
	if name=="mods.act": return interface.act(args)
	if name=="mods.invoke": return public_api.invoke(api,args)
	if name=="mods.list":
		var rows: Array=[]
		for manifest: Dictionary in api.call("mods"):
			var id: String=str(manifest.get("id","")); var mod: Node=enabled(id)
			if mod!=null: rows.append({"id":id,"name":manifest.get("name",id),"version":manifest.get("version",""),"state_available":mod.has_method("_save_state")})
		return Data.success({"mods":rows,"scope":"Enabled mod campaign data and mod-owned visible controls. No model/API profiles or chat history."})
	var id: String=str(args.get("mod","")); var mod: Node=enabled(id)
	if mod==null: return Data.failed("mods.unavailable")
	if name=="mods.api": return public_api.discover(id,mod,args)
	if name=="mods.catalogue": return catalogue(id,mod,args)
	if name=="mods.ui": return interface.inspect(id,mod,args)
	if name!="mods.inspect": return Data.failed("mods.unknown_tool")
	if not args.has("document") and not mod.has_method("_save_state"): return Data.failed("mods.state_unavailable")
	var path: Variant=args.get("path",[])
	if not path is Array or path.size()>16: return Data.failed("mods.invalid_path")
	for key: Variant in path:
		if not (key is String or (Data.number(key) and float(key)==floorf(float(key)) and key>=0)): return Data.failed("mods.invalid_path")
		if str(key).to_lower() in PRIVATE: return Data.failed("mods.private_field")
	# This fixed callback is the public save contract. Never call model-selected methods.
	var value: Variant
	if args.has("document"):
		var ref: String=str(args.document)
		if not documents.has(ref) or documents[ref].mod.get_ref()!=mod or documents[ref].id!=id: return Data.failed("mods.document_expired")
		var raw: String=mod.call("read_text",documents[ref].path)
		if raw.to_utf8_buffer().size()>16777216: return Data.failed("mods.document_too_large")
		var parser:=JSON.new()
		if parser.parse(raw)!=OK: return Data.failed("mods.invalid_json_document")
		value=parser.data
	else: value=mod.call("_save_state",game)
	for key: Variant in path:
		value=decode(value) if args.get("decode_json",true) else value
		if value is Dictionary and value.has(key): value=value[key]
		elif value is Array and Data.number(key) and int(key)<value.size(): value=value[int(key)]
		elif value is Array and key is String and key.is_valid_int() and key==str(int(key)) and int(key)>=0 and int(key)<value.size(): value=value[int(key)]
		else: return Data.failed("mods.path_not_found")
	value=decode(value) if args.get("decode_json",true) else value
	var offset: int=maxi(0,int(args.get("offset",0))); var limit: int=clampi(int(args.get("limit",50)),1,100)
	var result := {"mod":id,"path":path.duplicate(),"basis":"Current mod campaign-save state; field meanings/units are defined by that mod.","type":kind(value)}
	if not (value is Dictionary or value is Array):
		result["value"]=preview(value); return Data.success(result)
	var matches: Array=[]; var search: String=str(args.get("search","")).to_lower()
	var keys: Array=value.keys() if value is Dictionary else range(value.size())
	for key: Variant in keys:
		if str(key).to_lower() in PRIVATE: continue
		var item: Variant=value[key]
		var brief: Variant=preview(item)
		if search!="" and not (str(key)+" "+JSON.stringify(brief)).to_lower().contains(search): continue
		var child_path: Array=path.duplicate(); child_path.append(key)
		matches.append({"key":key,"path":child_path,"type":kind(item),"preview":brief,"size":item.size() if item is Array or item is Dictionary else null})
	result.merge({"children":matches.slice(offset,offset+limit),"total":matches.size(),"offset":offset,"returned":mini(limit,maxi(0,matches.size()-offset)),"has_more":offset+limit<matches.size(),"next_offset":offset+mini(limit,maxi(0,matches.size()-offset))})
	return Data.success(result)
func catalogue(id: String,mod: Node,args: Dictionary) -> Dictionary:
	if not mod.has_method("list_files") or not mod.has_method("read_text"): return Data.failed("mods.catalogue_unavailable")
	var pending: Array=[""]; var files: Array=[]; var visited:=0
	while not pending.is_empty() and visited<256 and files.size()<4000:
		var folder: String=pending.pop_front(); visited+=1
		for entry: String in mod.call("list_files",folder):
			if entry.contains("..") or entry.contains(":") or entry.begins_with(".") or entry.begins_with("/"): continue
			var path: String=folder.path_join(entry) if folder!="" else entry
			if path.get_extension().to_lower()=="json": files.append(path)
			elif entry.get_extension()=="" and path.count("/")<12: pending.append(path)
	files.sort()
	var search: String=str(args.get("search","")).to_lower()
	if search!="": files=files.filter(func(path: String): return path.to_lower().contains(search))
	var offset: int=maxi(0,int(args.get("offset",0))); var limit: int=clampi(int(args.get("limit",50)),1,100)
	var rows: Array=[]
	for path: String in files.slice(offset,offset+limit):
		var ref: String="mod-doc:"+id+":"+path
		documents[ref]={"mod":weakref(mod),"id":id,"path":path}
		rows.append({"document":ref,"name":path})
	return Data.success({"mod":id,"documents":rows,"total":files.size(),"has_more":offset+rows.size()<files.size(),"next_offset":offset+rows.size(),"scan_truncated":not pending.is_empty(),"basis":"Static mod content/configuration, not proof of an existing campaign asset."})
static func decode(value: Variant) -> Variant:
	if not value is String or value.length()>16777216: return value
	var raw: String=value.trim_prefix("json:").strip_edges()
	if not raw.begins_with("{") and not raw.begins_with("["): return value
	var parser:=JSON.new()
	return parser.data if parser.parse(raw)==OK else value
static func kind(value: Variant) -> String:
	if value is Dictionary: return "object"
	if value is Array: return "array"
	if value is String: return "string"
	if value is bool: return "boolean"
	if Data.number(value): return "number"
	return "null" if value==null else "unavailable_non_json"
static func preview(value: Variant, depth: int=0) -> Variant:
	if value is String:
		if value.begins_with("json:"): return {"encoding":"json","characters":value.length(),"use_decode_json":true}
		return value.left(1000)
	if value is bool or value==null or Data.number(value): return value
	if value is Dictionary:
		var out: Dictionary={}
		for key: Variant in value:
			if str(key).to_lower() in PRIVATE: continue
			var item: Variant=value[key]
			if item is String: out[str(key)]=item.left(200)
			elif item is bool or item==null or Data.number(item): out[str(key)]=item
			elif item is Dictionary and depth<1: out[str(key)]=preview(item,depth+1)
			if out.size()>=8: break
		return out
	return {"items":value.size()} if value is Array else null
