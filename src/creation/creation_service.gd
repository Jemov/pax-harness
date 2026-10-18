extends Node
const Surface = preload("res://mods/pax_harness/src/creation/artificial_surface.gd")
const Policy = preload("res://mods/pax_harness/src/creation/creation_policy.gd")
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
var owner_mod: Node
var api: Node
var game: RefCounted
var records: Dictionary = {}
var proposals: Array = []
var sequence := 0
var view: Node
var meshes: Array = []
var _world_id := 0
var _bus_registered := false
var _name_keys: Array=[]
var _name_language: RefCounted
signal changed

func setup(owner: Node) -> void:
	owner_mod=owner; api=owner.get_node_or_null("/root/Pax")
	if api != null and api.get("bus") != null and not _bus_registered:
		api.bus.on("resource_rows",_resource_rows,70,"pax_harness"); _bus_registered=true
func clear() -> void:
	_clear_names()
	if is_instance_valid(view): view.dispose(); view.queue_free()
	view=null
	for mesh: Node in meshes:
		if is_instance_valid(mesh): mesh.queue_free()
	meshes.clear(); records.clear(); proposals.clear(); sequence=0; game=null; _world_id=0
func restore(state: Dictionary) -> void:
	records=state.get("records",{}).duplicate(true); proposals=state.get("proposals",[]).duplicate(true); sequence=int(state.get("sequence",0))
func snapshot() -> Dictionary:
	return {"version":1,"records":records.duplicate(true),"proposals":proposals.duplicate(true),"sequence":sequence}
func world_ready(current: RefCounted) -> void:
	if _world_id==current.scene_root().get_instance_id():
		game=current; return
	game=current; _world_id=current.scene_root().get_instance_id()
	for record: Dictionary in records.values():
		if record.kind=="surface": Surface.create(game,record.definition)
	refresh_names()
	for record: Dictionary in records.values():
		if record.kind=="object": _spawn(record.definition)
	if not records.is_empty() or not proposals.is_empty(): _ensure_view()
func current() -> bool:
	return is_instance_valid(game) and is_instance_valid(owner_mod) and owner_mod._game_available(game) and game.scene_root().get_instance_id()==_world_id
func _title(d: Dictionary) -> String:
	var text: Variant=d.get("name",{})
	return str(text.get(L.language(),text.get("en",d.get("id","")))) if text is Dictionary else str(text)
func summaries() -> Array:
	var result: Array=[]
	for id: String in records:
		var r: Dictionary=records[id]; var d: Dictionary=r.definition
		result.append({"id":id,"kind":r.kind,"name":d.get("name",{}),"body":d.get("body",""),"behavior":d.get("behavior",""),"from_id":d.get("from_id",""),"to_id":d.get("to_id",""),"days":d.get("days"),"resource_key":r.get("resource_key",""),"surface_body":Surface.body_id(id) if r.kind=="surface" else ""})
	return result
func capabilities() -> Dictionary:
	return {"voxel_models":api!=null and api.get("voxel")!=null,"terrain_component_required_for_models":false,
		"resource_classes":Array(game.econ.classes().keys()),"kinds":Policy.KINDS,"player_review_required":true,"apply_tool_exists":false,"parallel_universes_supported":false,
		"artificial_surfaces":Surface.available(game),"formats":{
			"surface":"{id,name:{ru,en},body:discovered star or gas giant,altitude_km:100..1e8,provinces_count:integer 4..40,climate:{temperature,water,biomass,radiation,atmosphere,urban,magnetic}}. All climate scales 0..1; urban must be zero. Creates a native rock shell at the parent centre, radius parent radius+altitude, with real native provinces/map. Original body is preserved. No population, colony, resources or completed research are granted. This is explicitly approved scenario authoring, not a free normal terraforming order. Saved per campaign; stable body ID harness_surface_<id>. Requires player Apply. Call space.surface on parent to discover the shell.",
			"common":"id: lowercase a-z0-9_ starting with a letter, up to 48; name:{ru,en}; icon:gate/station/crystal/dust/panel or {rows:[4..16 equal strings of hex palette indices, 0 transparent],palette:[#RRGGBB]}",
			"object":"{id,name,body,icon,longitude:-180..180,latitude:-90..90,altitude_km:0..1e9,size_km:0.001..1e7,behavior:decoration|warp_gate,model:{size:[integer x,y,z up to 64],palette:[#RRGGBB],shapes:[box(from,to),sphere(center,radius),cylinder(center,radius,height),torus(center,radius,tube,axis),line(from,to,width); each has color index, 0 carves],voxels:[[x,y,z,color]]}}. Max 128 shapes/4096 explicit voxels. Existing discovered body only. Artwork is scenario content, not proof of researched/paid construction.",
			"resource_style":"{resource_id:approved resource ID,text_color:#RRGGBB or null to restore the native default}. Only on an explicit styling request; player Apply required. Changes text color only, never font size or layout. Ordinary resources should retain the native default.",
			"resource":"{id,name,body,goods_class:one returned class,unit:string,price:number>=0,icon,text_color?:#RRGGBB}. Omit text_color unless the player explicitly requests an accent. Uses native economy.create_goods; initial stock/demand/production are zero. No stock grants or automatic industry.",
			"panel":"{id,name,target_id:existing object ID,rows:[{label:{ru,en},value:string} OR {label:{ru,en},resource_id:created resource ID,body:colony}]}. Native read-only UI; no code or arbitrary actions. Separate approval required.",
			"warp_link":"{id,name,from_id:approved warp_gate ID,to_id:another approved warp_gate ID,days:integer 1..36500}. One-way, both actual bodies must be discovered; can cross existing systems/galaxies. No creation of universes. Approval adds a route only, moves no ship.",
			"warp_transit":"{link_id,ship_id:existing in-flight native ship ID}. Separate player approval reroutes a ship originating at the source gate body, preserving passengers/cargo. Arrival is handled by the native game on a later time step (minimum 1 day); it does not advance time or instantly found a colony. A changed/missing ship is rejected."}}
func execute(name: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	if not current(): return {"ok":false,"code":"creation.inactive_world"}
	if name=="creation.capabilities": return {"ok":true,"result":capabilities()}
	if name=="creation.list":
		var pending: Array=[]
		for p: Dictionary in proposals: pending.append({"id":p.id,"kind":p.kind,"name":p.definition.get("name",{}),"status":p.status,"error":p.get("error","")})
		return {"ok":true,"result":{"created":summaries(),"projects":pending,"review_panel":"harness.creations"}}
	if scope.get("analysis_child",false): return {"ok":false,"code":"creation.not_available_in_analysis"}
	var request: String=_player_request(scope)
	if request=="": return {"ok":false,"code":"creation.direct_player_request_required"}
	for forbidden: String in ["только чтение","ничего не создавай","не добавляй","read-only","read only","do not create","don't create"]:
		if request.to_lower().contains(forbidden): return {"ok":false,"code":"creation.player_requested_read_only"}
	return propose(str(args.get("kind","")),args.get("definition",{}),request)
func _player_request(scope: Dictionary) -> String:
	if owner_mod.chat_store==null: return ""
	var chat: Dictionary=owner_mod.chat_store.find(str(scope.get("chat_id","")))
	var preceding: Dictionary={}
	for message: Dictionary in chat.get("messages",[]):
		if message.get("id")==scope.get("message_id"):
			return str(preceding.get("text","")) if preceding.get("origin",{}).is_empty() else ""
		if message.get("role")=="user": preceding=message
	return ""
func propose(kind: String, definition: Dictionary, request: String) -> Dictionary:
	var checked: Dictionary=Policy.validate(kind,definition)
	if not checked.ok: return checked
	if not current(): return {"ok":false,"code":"creation.inactive_world"}
	var valid: Dictionary=_references(kind,definition)
	if not valid.ok: return valid
	var fingerprint: String=JSON.stringify({"kind":kind,"definition":definition}).sha256_text()
	for p: Dictionary in proposals:
		if p.fingerprint==fingerprint and p.status in ["pending","applied"]: return _proposal_receipt(p)
	if proposals.filter(func(p: Dictionary): return p.status=="pending").size()>=20: return {"ok":false,"code":"creation.pending_limit"}
	sequence+=1
	var p: Dictionary={"id":"project:"+str(sequence),"kind":kind,"definition":definition.duplicate(true),"request":request.left(4000),"status":"pending","fingerprint":fingerprint}
	if kind=="warp_transit": p["ship_before"]=_ship(int(definition.ship_id)).duplicate(true)
	proposals.append(p); _ensure_view(); changed.emit()
	while proposals.size()>100:
		var index: int=proposals.find(proposals.filter(func(row: Dictionary): return row.status!="pending")[0])
		proposals.remove_at(index)
	return _proposal_receipt(p)
func _proposal_receipt(p: Dictionary) -> Dictionary:
	return {"ok":true,"result":{"proposal_id":p.id,"status":p.status,"kind":p.kind,"name":p.definition.get("name",{}),"world_changed":p.status=="applied","review_panel":"harness.creations","instruction":"Pending means NOT created. Ask the player to review and click Apply. There is no model-callable approval or apply tool."}}
func _references(kind: String, d: Dictionary) -> Dictionary:
	if kind not in ["warp_transit","resource_style"] and records.has(d.id): return {"ok":false,"code":"creation.id_exists"}
	if records.size()>=128: return {"ok":false,"code":"creation.content_limit"}
	if kind in ["object","resource","surface"]:
		if d.body not in game.body_names() or not game.body(d.body).get("open",false): return {"ok":false,"code":"tools.unknown_or_hidden_body"}
	if kind=="surface":
		if not Surface.available(game): return {"ok":false,"code":"creation.native_surface_unavailable"}
		if game.body(d.body).get("genus") not in ["star","gas"]: return {"ok":false,"code":"creation.star_or_gas_required"}
		if Surface.body_id(d.id) in game.body_names(): return {"ok":false,"code":"creation.surface_name_collision"}
		if records.values().any(func(r: Dictionary): return r.kind=="surface" and r.definition.body==d.body): return {"ok":false,"code":"creation.surface_already_exists"}
		if records.values().filter(func(r: Dictionary): return r.kind=="surface").size()>=8: return {"ok":false,"code":"creation.surface_limit"}
	if kind=="object":
		if records.values().filter(func(r: Dictionary): return r.kind=="object").size()>=32: return {"ok":false,"code":"creation.object_limit"}
		if not is_instance_valid(game.body_node(d.body)): return {"ok":false,"code":"creation.body_scene_unavailable"}
	if kind=="resource":
		if d.body not in game.colonies(): return {"ok":false,"code":"tools.colony_not_found"}
		if d.goods_class not in game.econ.classes(): return {"ok":false,"code":"creation.unknown_goods_class"}
		if game.econ.goods().has("harness_"+str(d.id)): return {"ok":false,"code":"creation.goods_key_exists"}
	if kind=="resource_style":
		if not records.has(d.resource_id) or records[d.resource_id].kind!="resource": return {"ok":false,"code":"creation.resource_row_unavailable"}
	if kind=="panel":
		if not records.has(d.target_id) or records[d.target_id].kind!="object": return {"ok":false,"code":"creation.object_required"}
		for row: Dictionary in d.rows:
			if row.has("resource_id") and (not records.has(row.resource_id) or records[row.resource_id].kind!="resource" or row.body not in game.colonies()): return {"ok":false,"code":"creation.resource_row_unavailable"}
	if kind=="warp_link":
		for id: String in [d.from_id,d.to_id]:
			if not records.has(id) or records[id].kind!="object" or records[id].definition.get("behavior")!="warp_gate": return {"ok":false,"code":"creation.warp_gate_required"}
			var body: String=records[id].definition.body
			if body not in game.body_names() or not game.body(body).get("open",false): return {"ok":false,"code":"tools.unknown_or_hidden_body"}
	if kind=="warp_transit":
		if not records.has(d.link_id) or records[d.link_id].kind!="warp_link": return {"ok":false,"code":"creation.warp_link_required"}
		var link: Dictionary=records[d.link_id].definition; var ship: Dictionary=_ship(int(d.ship_id))
		if records[link.to_id].definition.body not in game.body_names(): return {"ok":false,"code":"tools.unknown_or_hidden_body"}
		if ship.is_empty() or ship.get("origin")!=records[link.from_id].definition.body or float(ship.get("until_day",-1))<=game.day(): return {"ok":false,"code":"creation.ship_not_at_source_route"}
	return {"ok":true}
func _ship(id: int) -> Dictionary:
	for ship: Dictionary in game.ships():
		if int(ship.get("id",-1))==id: return ship
	return {}

# This method has NO executable-tool entry. Only the bound player review button uses it.
func apply_from_player(id: String) -> Dictionary:
	if not current(): return {"ok":false,"code":"creation.inactive_world"}
	for p: Dictionary in proposals:
		if p.id!=id: continue
		if p.status!="pending": return {"ok":false,"code":"creation.project_not_pending"}
		var valid: Dictionary=_references(p.kind,p.definition)
		if not valid.ok: p["error"]=valid.code; changed.emit(); return valid
		var d: Dictionary=p.definition; var result: Dictionary={"ok":true}
		match p.kind:
			"surface": result=Surface.create(game,d)
			"resource_style": records[d.resource_id].definition["text_color"]=d.text_color
			"object":
				if not _spawn(d): result={"ok":false,"code":"creation.voxel_model_unavailable"}
			"resource":
				var key: String="harness_"+str(d.id)
				game.econ.create_goods(key,d.goods_class,{"unit":d.unit,"price":d.price,"people":0.0,"flow":false})
				if not game.econ.goods().has(key): result={"ok":false,"code":"creation.native_goods_refused"}
				else: game.add_resource(d.body,key,0.0)
			"warp_transit":
				var ship: Dictionary=_ship(int(d.ship_id))
				if ship!=p.ship_before: result={"ok":false,"code":"creation.ship_changed_review_again"}
				else:
					var link: Dictionary=records[d.link_id].definition
					ship["where_to"]=records[link.to_id].definition.body; ship["s_day"]=game.day(); ship["until_day"]=game.day()+int(link.days)
					if ship.get("data") is Dictionary: ship.data["harness_warp_link"]=d.link_id
					var readback: Dictionary=_ship(int(d.ship_id))
					if readback.get("where_to")!=ship.where_to or readback.get("until_day")!=ship.until_day: result={"ok":false,"code":"creation.native_ship_write_unavailable"}
					else: result["ship_after"]=readback.duplicate(true)
		if not result.ok: p["error"]=result.code; changed.emit(); return result
		if p.kind not in ["warp_transit","resource_style"]:
			var record: Dictionary={"kind":p.kind,"definition":d.duplicate(true)}
			if p.kind=="resource": record["resource_key"]="harness_"+str(d.id)
			records[d.id]=record
		refresh_names()
		if p.kind in ["resource","resource_style"] and game.scene_root().has_method("resources_panel"):
			var panel: Variant=game.scene_root().call("resources_panel")
			if panel is Object and panel.has_method("fill"): panel.call("fill")
		p.status="applied"; p.erase("error"); p["result"]=result; changed.emit()
		return {"ok":true,"result":{"proposal_id":id,"status":"applied","kind":p.kind,"ship_after":result.get("ship_after",{})}}
	return {"ok":false,"code":"creation.project_not_found"}
func reject_from_player(id: String) -> void:
	for p: Dictionary in proposals:
		if p.id==id and p.status=="pending": p.status="rejected"; changed.emit(); return
func _ensure_view() -> void:
	if is_instance_valid(view): return
	view=preload("res://mods/pax_harness/src/creation/creation_view.gd").new(); add_child(view); view.setup(self)
func open_review() -> bool:
	if not current(): return false
	_ensure_view(); view.open(); return true
func _spawn(d: Dictionary) -> bool:
	if api==null or api.get("voxel")==null: return false
	var parent: Node3D=game.body_node(d.body)
	if not is_instance_valid(parent): return false
	var mesh: Variant=api.voxel.model(d.model)
	if not mesh is MeshInstance3D: return false
	if mesh.mesh==null or mesh.mesh.get_surface_count()==0: mesh.free(); return false
	var radius: float=1.0
	if parent is MeshInstance3D and parent.mesh!=null: radius=parent.get_aabb().size[parent.get_aabb().size.max_axis_index()]*0.5
	var r_km: float=maxf(0.001,float(game.body(d.body).get("r_km",1)))
	var lon: float=deg_to_rad(float(d.longitude)); var lat: float=deg_to_rad(float(d.latitude))
	var direction:=Vector3(cos(lat)*sin(lon),sin(lat),cos(lat)*cos(lon))
	mesh.name="HarnessObject_"+str(d.id); parent.add_child(mesh)
	var grid_size: float=maxf(d.model.size[0],maxf(d.model.size[1],d.model.size[2]))
	var scale_: float=radius*float(d.size_km)/r_km/grid_size
	mesh.basis=Basis.looking_at(-direction,Vector3.RIGHT if absf(direction.dot(Vector3.UP))>0.99 else Vector3.UP).scaled(Vector3.ONE*scale_)
	mesh.position=direction*radius*(1.0+float(d.altitude_km)/r_km)-mesh.basis*mesh.get_aabb().get_center()
	meshes.append(mesh); return true
func _resource_rows(panel: Variant, body: Variant) -> void:
	if current() and panel is Object: preload("res://mods/pax_harness/src/creation/resource_presentation.gd").update(self,panel,str(body))

func _clear_names() -> void:
	if is_instance_valid(_name_language) and _name_language.get("dictionary") is Dictionary:
		for key: String in _name_keys: _name_language.dictionary.erase(key)
	_name_keys.clear(); _name_language=null
func refresh_names() -> void:
	_clear_names()
	if not is_instance_valid(game): return
	var root: Node=game.scene_root()
	var lang: Variant=root.get("lang")
	if not lang is RefCounted or not lang.get("dictionary") is Dictionary: return
	_name_language=lang
	for record: Dictionary in records.values():
		var d: Dictionary=record.definition; var keys: Array=[]
		if record.kind=="surface": keys=["body_"+Surface.body_id(d.id),"тело_"+Surface.body_id(d.id)]
		if record.kind=="resource": keys=["рес_"+str(record.resource_key),"resource_"+str(record.resource_key)]
		for key: String in keys:
			if not lang.dictionary.has(key): lang.dictionary[key]=_title(d); _name_keys.append(key)
