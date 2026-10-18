extends Node
const Body=preload("res://mods/pax_harness/src/creation/authored_body.gd")
const Surface = preload("res://mods/pax_harness/src/creation/artificial_surface.gd")
const Policy = preload("res://mods/pax_harness/src/creation/creation_policy.gd")
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const VoxelObject = preload("res://mods/pax_harness/src/creation/voxel_object.gd")
var owner_mod: Node
var api: Node
var game: RefCounted
var records: Dictionary = {}
var proposals: Array = []
var sequence := 0
var view: Node
var meshes: Array = []
var programs: Node
var ship_flight: Node
var object_navigation: Node
var _world_id := 0
var _bus_registered := false
var _name_keys: Array=[]
var _name_language: RefCounted
var _surface_window: PanelContainer
var _program_windows: Dictionary={}
var _validated_programs: Dictionary={}
signal changed

func setup(owner: Node) -> void:
	owner_mod=owner; api=owner.get_node_or_null("/root/Pax")
	if api != null and api.get("bus") != null and not _bus_registered:
		api.bus.on("resource_rows",_resource_rows,70,"pax_harness"); _bus_registered=true
func clear() -> void:
	_validated_programs.clear()
	for window: Node in _program_windows.values():
		if is_instance_valid(window): window.queue_free()
	_program_windows.clear()
	if is_instance_valid(_surface_window): _surface_window.queue_free()
	_surface_window=null
	if is_instance_valid(programs): programs.queue_free()
	programs=null
	if is_instance_valid(ship_flight): ship_flight.queue_free()
	ship_flight=null
	if is_instance_valid(object_navigation): object_navigation.queue_free()
	object_navigation=null
	_clear_names()
	if is_instance_valid(view): view.dispose(); view.queue_free()
	view=null
	for mesh: Node in meshes:
		if is_instance_valid(mesh): mesh.queue_free()
	meshes.clear(); records.clear(); proposals.clear(); sequence=0; game=null; _world_id=0
func restore(state: Dictionary) -> void:
	_validated_programs.clear()
	records=state.get("records",{}).duplicate(true); proposals=state.get("proposals",[]).duplicate(true); sequence=int(state.get("sequence",0))
func snapshot() -> Dictionary:
	if current() and game.has_method("body_params"):
		for record: Dictionary in records.values():
			if record.kind in ["body","surface"]:
				var name_: String=Body.body_id(record.definition.id) if record.kind=="body" else Surface.body_id(record.definition.id)
				if name_ in game.body_names(): record["body_state"]={"parameters":game.body_params(name_).duplicate(true)}
	return {"version":1,"records":records.duplicate(true),"proposals":proposals.duplicate(true),"sequence":sequence}
func world_ready(current: RefCounted) -> void:
	if _world_id==current.scene_root().get_instance_id():
		game=current; return
	_validated_programs.clear()
	game=current; _world_id=current.scene_root().get_instance_id()
	for record: Dictionary in records.values():
		if record.kind=="body": Body.create(self,record.definition)
		if record.kind=="surface": Surface.create(game,record.definition)
		if record.kind in ["body","surface"] and game.has_method("set_body_param"):
			var name_: String=Body.body_id(record.definition.id) if record.kind=="body" else Surface.body_id(record.definition.id)
			if name_ in game.body_names():
				for key: String in record.get("body_state",{}).get("parameters",{}):
					var value: Variant=record.body_state.parameters[key]
					if key in ["temperature","water","biomass","radiation","atmosphere","urban","magnetic"] and Data.number(value) and float(value)>=0 and float(value)<=1: game.set_body_param(name_,key,float(value))
	refresh_names()
	for record: Dictionary in records.values():
		if record.kind=="object": _spawn(record.definition,record.get("damage",[]),true)
	for record: Dictionary in records.values():
		if record.kind=="ship_flight": _flights().restore_record(record)
	for id: String in records:
		var record: Dictionary=records[id]
		if record.kind=="object" and record.has("transform"):
			var node: Node3D=game.body_node(record.definition.body).get_node_or_null("HarnessObject_"+id)
			if node!=null: node.position=game.body_node(record.definition.body).global_basis.inverse()*Vector3(record.transform.position_km[0],record.transform.position_km[1],record.transform.position_km[2])/1000.0-node.basis*node.get_meta("harness_model_center",Vector3.ZERO)
		if record.definition.has("program"): _programs().install(id,true)
	if not records.is_empty() or not proposals.is_empty(): _ensure_view()
func current() -> bool:
	return is_instance_valid(game) and is_instance_valid(owner_mod) and owner_mod._game_available(game) and game.scene_root().get_instance_id()==_world_id
func _title(d: Dictionary) -> String:
	var text: Variant=d.get("name",{})
	return str(text.get(L.language(),text.get("en",d.get("id","")))) if text is Dictionary else str(text)
func body_title(id: String) -> String:
	var language: Variant=game.scene_root().get("lang") if is_instance_valid(game) else null
	return str(language.call("body",id)) if language is Object and language.has_method("body") else id
func summaries() -> Array:
	var result: Array=[]
	for id: String in records:
		var r: Dictionary=records[id]; var d: Dictionary=r.definition
		result.append({"id":id,"kind":r.kind,"name":d.get("name",{}),"body":d.get("body",""),"behavior":d.get("behavior",""),"from_id":d.get("from_id",""),"to_id":d.get("to_id",""),"days":d.get("days"),"resource_key":r.get("resource_key",""),"surface_body":Body.body_id(id) if r.kind=="body" else (Surface.body_id(id) if r.kind=="surface" else "")})
		if r.kind=="object":
			result[-1].merge({"destructible":d.get("destructible",false),"voxel_grid_size":d.model.size.duplicate(),"damage_count":r.get("damage",[]).size(),"altitude_km":d.altitude_km,"size_km":d.size_km,"focus_tool":"creation.focus"})
		if r.kind=="ship_flight": result[-1]["flight"]=r.get("flight",{}).duplicate(true)
		if d.has("program"): result[-1]["program"]={"enabled":r.get("runtime",{}).get("enabled",false),"runs":r.get("runtime",{}).get("runs",0),"last_error":r.get("runtime",{}).get("last_error",{}),"receipts":r.get("runtime",{}).get("receipts",[]).slice(-2)}
	return result
func capabilities() -> Dictionary:
	return {"programmable_entities":{"schema_tool":"creation.program_schema","validate_tool":"creation.validate_program","status_tool":"creation.program_status","language":"versioned interpreted JSON AST; variables, conditions, bounded loops, events and general world API operations"},"ship_flights":preload("res://mods/pax_harness/src/creation/ship_flight.gd").info(api),"voxel_models":api!=null and api.get("voxel")!=null,"terrain_component_required_for_models":false,
		"destructible_objects":VoxelObject.supported(api),"destructible_component":"voxel",
		"missing_component_message":"Ordinary models work without Voxel Tools. Destructible objects need the optional voxel component; if missing, report that destruction is unavailable and do not claim to create a destructible object.",
		"resource_classes":Array(game.econ.classes().keys()),"kinds":Policy.KINDS,"player_review_required":true,"apply_tool_exists":false,"parallel_universes_supported":false,
		"artificial_surfaces":Surface.available(game),"formats":{
			"body":"{id,name:{ru,en},body:discovered parent,radius_km:0.1..10000,orbit_radius_km:parent radius + own radius or greater,period_days:0..1e8 (0 fixed),provinces_count:integer4..40,climate:{temperature,water,biomass,radiation,atmosphere,magnetic:0..1,urban:0},icon,model?:voxel format,program?:source}. Creates a separate real rocky body with native map/provinces, no free people or resources. Optional model replaces only its native sphere visual. Returned surface_body is its stable native ID. Native colonization and economic simulation remain available; no habitat-specific behavior preset.",
			"ship_flight":"{id,name:{ru,en},object_id:approved object ID (gate_id accepted as an alias; provide exactly one),waypoints_km?:2..16 [x,y,z] points in the object-oriented frame, in km relative to its centre, each coordinate -100000..100000, adjacent points at least .001km apart, total path at most 1e6km; when omitted a single-ring warp_gate gets an automatic central crossing,ship_name:string,spawn_model?:one model ID from ship_flights.models,ship_length_km:0.01..100 (must fit aperture),duration_seconds:5..120,forward_axis?:-z (default)|+z|-x|+x: actual hull nose axis after provider model transforms}. Verify nose-first travel across multiple scene frames, not one still. Read ship_flights availability/fleet first. Omit spawn_model for an idle, unladen, ungrouped player ship in the same system; include it ONLY if player explicitly authorized creating a test ship. Player Apply starts a real registered Dyson ship along the local 3D route. Any approved object, any discovered body; no specific object/body/model IDs are assumed. Use creation.inspect to read geometry first. Paths use constant speed along segments; corners change direction instantly, so add points for gentler turns. This route moves a registered actor; arbitrary gameplay mechanics must be authored separately in object.program. Collision/damage/teleportation are NOT simulated by this route alone; do not claim passage through solid geometry is physically verified. Scene seconds continue while calendar time is paused. This is local flight, NOT interstellar teleportation or paid construction. Progress and endpoint persist; a new native order releases pose control. Missing mod/unsupported ship scene reports a specific error. Replay button starts the same ship again, never duplicates it.",
			"surface":"{id,name:{ru,en},body:discovered star or gas giant,altitude_km:100..1e8,provinces_count:integer 4..40,climate:{temperature,water,biomass,radiation,atmosphere,urban,magnetic}}. All climate scales 0..1; urban must be zero. Creates a native rock shell at the parent centre, radius parent radius+altitude, with real native provinces/map. Original body is preserved. No population, colony, resources or completed research are granted. This is explicitly approved scenario authoring, not a free normal terraforming order. Saved per campaign; stable body ID harness_surface_<id>. Requires player Apply. Call space.surface on parent to discover the shell.",
			"common":"id: lowercase a-z0-9_ starting with a letter, up to 48; name:{ru,en}; icon:gate/station/crystal/dust/panel or {rows:[4..16 equal strings of hex palette indices, 0 transparent],palette:[#RRGGBB]}",
			"behavior":"{id,name:{ru,en},object_id:approved object,program:source per creation.program_schema OR program_ref:from creation.validate_program OR program_patch:[{path:ui.workspace|handlers.event_name|state.key|events,value:replacement}],preserve_state?:true}. Installs or revises an agent-authored program after player Apply. Reusing a behavior ID updates its program; id==object_id updates that object's attached program without replacing geometry; prior state is retained unless preserve_state=false. A revision restarts a faulted/paused behavior. No arbitrary native code. Faults expose exact code/path and stop only that program.",
			"object":"{id,name,body,icon,program?:agent-authored source from creation.program_schema,longitude:-180..180,latitude:-90..90,altitude_km:0..1e9,size_km:0.001..1e7,behavior?:arbitrary identifier tag (no automatic functionality),destructible?:boolean (requires voxel component),model:{size:[integer x,y,z up to 64],palette:[#RRGGBB],shapes:[box(from,to),sphere(center,radius),cylinder(center,radius,height),torus(center,radius,tube,axis),line(from,to,width); each has color index STARTING AT 1, 0 carves. Do NOT insert a black/transparent placeholder in palette. For space gates use a floating ring without a pedestal unless explicitly requested; altitude_km must place it above the body],voxels:[[x,y,z,color]]}}. Max 128 shapes/4096 explicit voxels. Existing discovered body only. Artwork is scenario content, not proof of researched/paid construction.",
			"object_damage":"{object_id:approved destructible object ID,center:[x,y,z] within its voxel grid,radius:0.25..16}. Player-reviewed removal of a sphere of voxels. Damage persists with the campaign; does not advance time. No terrain changes.",
			"resource_style":"{resource_id:approved resource ID,text_color:#RRGGBB or null to restore the native default}. Only on an explicit styling request; player Apply required. Changes text color only, never font size or layout. Ordinary resources should retain the native default.",
			"resource":"{id,name,body,goods_class:one returned class,unit:string,price:number>=0,icon,text_color?:#RRGGBB}. Omit text_color unless the player explicitly requests an accent. Uses native economy.create_goods; initial stock/demand/production are zero. No stock grants or automatic industry.",
			"panel":"{id,name,target_id:existing object ID,rows:[{label:{ru,en},value:string} OR {label:{ru,en},resource_id:created resource ID,body:colony}]}. Native read-only UI; no code or arbitrary actions. Separate approval required.",
			"warp_link":"Legacy native passenger-transport route {id,name,from_id,to_id,days:1..36500}; does not implement authored game-object behavior. Use object.program or a behavior project for new working mechanics, not this legacy route.",
			"warp_transit":"{link_id,ship_id:existing in-flight native ship ID}. Separate player approval reroutes a ship originating at the source gate body, preserving passengers/cargo. Arrival is handled by the native game on a later time step (minimum 1 day); it does not advance time or instantly found a colony. A changed/missing ship is rejected."}}
func execute(name: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	if name=="creation.open_controls": return open_controls(str(args.get("object_id","")))
	if not current(): return {"ok":false,"code":"creation.inactive_world"}
	if name=="creation.actors":
		var host:=preload("res://mods/pax_harness/src/creation/program_host.gd").new(); host.setup(self,{"runtime":{}},"")
		return host.execute("actor.read" if args.has("id") else "actors.list",args)
	if name=="creation.program_schema":
		var schema: Dictionary=preload("res://mods/pax_harness/src/creation/program_spec.gd").schema()
		schema["operations"]=preload("res://mods/pax_harness/src/creation/program_host.gd").schema(); schema["actor_adapter"]=preload("res://mods/pax_harness/src/creation/ship_flight.gd").info(api)
		return {"ok":true,"result":schema}
	if name=="creation.validate_program": return validate_program(args.get("program"))
	if name=="creation.program_status": return _programs().status(str(args.get("id","")))
	if name=="creation.inspect":
		var id: String=str(args.get("object_id",""))
		if not records.has(id): return {"ok":false,"code":"creation.object_required"}
		return {"ok":true,"result":records[id].duplicate(true)}
	if name=="creation.capabilities": return {"ok":true,"result":capabilities()}
	if name=="creation.list":
		var pending: Array=[]
		for p: Dictionary in proposals: pending.append({"id":p.id,"kind":p.kind,"name":p.definition.get("name",{}),"status":p.status,"error":p.get("error","")})
		return {"ok":true,"result":{"created":summaries(),"projects":pending,"review_panel":"harness.creations"}}
	if scope.get("analysis_child",false): return {"ok":false,"code":"creation.not_available_in_analysis"}
	if name=="creation.focus": return focus_object(str(args.get("object_id","")))
	var request: String=_player_request(scope)
	if request=="": return {"ok":false,"code":"creation.direct_player_request_required"}
	for forbidden: String in ["только чтение","ничего не создавай","ничего не добавляй","read-only","read only","do not create","don't create"]:
		if request.to_lower().contains(forbidden): return {"ok":false,"code":"creation.player_requested_read_only"}
	var result: Dictionary=propose(str(args.get("kind","")),args.get("definition",{}),request)
	if result.ok:
		for proposal: Dictionary in proposals:
			if proposal.id==result.result.proposal_id: proposal["chat_id"]=str(scope.get("chat_id",""))
	return result
func _player_request(scope: Dictionary) -> String:
	if owner_mod.chat_store==null: return ""
	var chat: Dictionary=owner_mod.chat_store.find(str(scope.get("chat_id","")))
	var preceding: Dictionary={}
	for message: Dictionary in chat.get("messages",[]):
		if message.get("id")==scope.get("message_id"):
			return str(preceding.get("text","")) if preceding.get("origin",{}).is_empty() else ""
		if message.get("role")=="user": preceding=message
	return ""
func validate_program(source: Variant) -> Dictionary:
	var result: Dictionary=preload("res://mods/pax_harness/src/creation/program_spec.gd").validate(source)
	if not result.ok: return result
	var reference: String="program:"+JSON.stringify(source).sha256_text()
	_validated_programs.erase(reference); _validated_programs[reference]=source.duplicate(true)
	while _validated_programs.size()>16: _validated_programs.erase(_validated_programs.keys()[0])
	result.result["program_ref"]=reference
	result.result["next"]="Reuse this program_ref in creation.propose definition instead of repeating program. It is a temporary immutable source reference; player review and normal validation still apply."
	return result
func resolve_program(kind: String,definition: Dictionary) -> Dictionary:
	if not definition.has("program_ref"): return {"ok":true,"definition":definition}
	if kind not in ["behavior","object","body"] or definition.has("program") or definition.has("program_patch"): return {"ok":false,"code":"program.reference_conflict","detail":"Use one of program, program_ref or program_patch on an object/body/behavior"}
	var reference: Variant=definition.program_ref
	if not reference is String or not _validated_programs.has(reference): return {"ok":false,"code":"program.reference_expired","detail":"Source reference is unavailable; validate the program again"}
	var expanded: Dictionary=definition.duplicate(true); expanded.erase("program_ref"); expanded["program"]=_validated_programs[reference].duplicate(true)
	return {"ok":true,"definition":expanded}
func propose(kind: String, definition: Dictionary, request: String) -> Dictionary:
	var resolved: Dictionary=resolve_program(kind,definition)
	if not resolved.ok: return resolved
	definition=resolved.definition
	if kind=="behavior" and definition.has("program_patch"):
		var id: String=str(definition.get("object_id",""))
		if definition.has("program") or not records.has(id): return {"ok":false,"code":"program.patch_target_required"}
		var merged: Dictionary=preload("res://mods/pax_harness/src/creation/program_patch.gd").merge(records[id].definition.get("program",{}),definition.program_patch)
		if not merged.ok: return merged
		definition=definition.duplicate(true); definition.erase("program_patch"); definition["program"]=merged.program
	var checked: Dictionary=Policy.validate(kind,definition)
	if not checked.ok: return checked
	if not current(): return {"ok":false,"code":"creation.inactive_world"}
	var valid: Dictionary=_references(kind,definition)
	if not valid.ok: return valid
	var fingerprint: String=JSON.stringify({"kind":kind,"definition":definition}).sha256_text()
	for p: Dictionary in proposals:
		if p.fingerprint==fingerprint and p.status in ["pending","applied"]: return _proposal_receipt(p)
	if definition.has("id"):
		for prior: Dictionary in proposals:
			if prior.status!="pending" or prior.kind!=kind: continue
			if prior.definition.get("id")==definition.id or (kind=="ship_flight" and prior.definition.get("ship_name")==definition.get("ship_name")): prior.status="superseded"
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
	if kind not in ["warp_transit","resource_style","object_damage","behavior"] and records.has(d.id): return {"ok":false,"code":"creation.id_exists"}
	if kind=="behavior":
		if not records.has(d.object_id) or records[d.object_id].kind not in ["object","body"]: return {"ok":false,"code":"creation.object_required"}
		if records.has(d.id) and records[d.id].kind!="behavior" and not (records[d.id].kind in ["object","body"] and d.id==d.object_id): return {"ok":false,"code":"creation.id_exists"}
	if definition_program_count(kind,d)>=64: return {"ok":false,"code":"program.instance_limit"}
	if kind=="ship_flight": return _flights().validate(d)
	if kind=="object_damage":
		if not records.has(d.object_id) or records[d.object_id].kind not in ["object","body"] or not records[d.object_id].definition.get("destructible",false): return {"ok":false,"code":"creation.object_not_destructible"}
		for axis: int in 3:
			if float(d.center[axis])>=float(records[d.object_id].definition.model.size[axis]): return {"ok":false,"code":"creation.damage_outside_object"}
		if not VoxelObject.supported(api): return {"ok":false,"code":"creation.voxel_component_required"}
		if records[d.object_id].get("damage",[]).size()>=128: return {"ok":false,"code":"creation.damage_limit"}
	if records.size()>=128: return {"ok":false,"code":"creation.content_limit"}
	if kind in ["object","resource","surface","body"]:
		if d.body not in game.body_names() or not game.body(d.body).get("open",false): return {"ok":false,"code":"tools.unknown_or_hidden_body"}
	if kind=="body":
		if not Surface.available(game): return {"ok":false,"code":"creation.native_surface_unavailable"}
		if Body.body_id(d.id) in game.body_names(): return {"ok":false,"code":"creation.surface_name_collision"}
		if float(d.orbit_radius_km)<=float(game.body(d.body).r_km)+float(d.radius_km): return {"ok":false,"code":"creation.body_orbit_intersects_parent"}
		if records.values().filter(func(r: Dictionary): return r.kind=="body").size()>=8: return {"ok":false,"code":"creation.surface_limit"}
	if kind=="surface":
		if not Surface.available(game): return {"ok":false,"code":"creation.native_surface_unavailable"}
		if game.body(d.body).get("genus") not in ["star","gas"]: return {"ok":false,"code":"creation.star_or_gas_required"}
		if Surface.body_id(d.id) in game.body_names(): return {"ok":false,"code":"creation.surface_name_collision"}
		if records.values().any(func(r: Dictionary): return r.kind=="surface" and r.definition.body==d.body): return {"ok":false,"code":"creation.surface_already_exists"}
		if records.values().filter(func(r: Dictionary): return r.kind=="surface").size()>=8: return {"ok":false,"code":"creation.surface_limit"}
	if kind=="object":
		if d.get("destructible",false) and not VoxelObject.supported(api): return {"ok":false,"code":"creation.voxel_component_required"}
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
			"ship_flight": result=_flights().start(d)
			"object_damage": result=damage_from_player(d.object_id,d.center,float(d.radius),false)
			"surface": result=Surface.create(game,d)
			"body": result=Body.create(self,d)
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
		if p.kind not in ["warp_transit","resource_style","object_damage"]:
			var record: Dictionary={"kind":p.kind,"definition":d.duplicate(true)}
			if p.kind=="behavior" and records.get(d.id,{}).get("kind") in ["object","body"]:
				record=records[d.id].duplicate(true); record.definition["program"]=d.program.duplicate(true)
				if not d.get("preserve_state",true): record.erase("runtime")
			if p.kind=="ship_flight": record["flight"]=result.flight
			if p.kind=="resource": record["resource_key"]="harness_"+str(d.id)
			if d.has("program"):
				var previous: Dictionary=records.get(d.id,{}).get("runtime",{}).duplicate(true)
				if d.get("preserve_state",true) and not previous.is_empty(): record["runtime"]=previous; record.runtime.enabled=true; record.runtime.last_error={}
				record["chat_id"]=p.get("chat_id","")
			records[d.id]=record
			if d.has("program"): _programs().install(d.id,record.has("runtime"))
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
func _spawn(d: Dictionary, cuts: Array=[], restoring: bool=false) -> bool:
	if api==null or api.get("voxel")==null: return false
	var parent: Node3D=game.body_node(d.body)
	if not is_instance_valid(parent): return false
	var mesh: Variant=VoxelObject.create(api,d,cuts)
	if mesh==null and restoring: mesh=VoxelObject.static_snapshot(api,d,cuts)
	if not mesh is MeshInstance3D: return false
	if mesh.mesh==null or (mesh.mesh.get_surface_count()==0 and cuts.is_empty()): mesh.free(); return false
	VoxelObject.space_material(mesh)
	var radius: float=1.0
	if parent is MeshInstance3D and parent.mesh!=null: radius=parent.get_aabb().size[parent.get_aabb().size.max_axis_index()]*0.5
	var r_km: float=maxf(0.001,float(game.body(d.body).get("r_km",1)))
	var lon: float=deg_to_rad(float(d.longitude)); var lat: float=deg_to_rad(float(d.latitude))
	var direction:=Vector3(cos(lat)*sin(lon),sin(lat),cos(lat)*cos(lon))
	mesh.name="HarnessObject_"+str(d.id); parent.add_child(mesh)
	var grid_size: float=maxf(d.model.size[0],maxf(d.model.size[1],d.model.size[2]))
	var scale_: float=radius*float(d.size_km)/r_km/grid_size
	mesh.basis=Basis.looking_at(-direction,Vector3.RIGHT if absf(direction.dot(Vector3.UP))>0.99 else Vector3.UP).scaled(Vector3.ONE*scale_)
	var center: Vector3=mesh.get_aabb().get_center()
	if not cuts.is_empty():
		var intact: MeshInstance3D=api.voxel.model(d.model); center=intact.get_aabb().get_center(); intact.free()
	mesh.position=direction*radius*(1.0+float(d.altitude_km)/r_km)-mesh.basis*center
	mesh.set_meta("harness_model_center",center)
	meshes.append(mesh); return true
func focus_object(id: String) -> Dictionary:
	if current() and records.get(id,{}).get("kind")=="body":
		focus_body(id)
		return {"ok":true,"result":{"object_id":id,"body":Body.body_id(id),"camera_target":"body","physical_travel":false}}
	if not is_instance_valid(object_navigation):
		object_navigation=preload("res://mods/pax_harness/src/creation/object_navigation.gd").new(); game.scene_root().add_child(object_navigation); object_navigation.setup(self)
	return object_navigation.focus(id)
func damage_from_player(id: String, center: Array, radius: float, notify: bool=true) -> Dictionary:
	var checked: Dictionary=Policy.validate("object_damage",{"object_id":id,"center":center,"radius":radius})
	if not checked.ok or not current(): return {"ok":false,"code":"creation.invalid_damage"}
	var d: Dictionary={"object_id":id,"center":center,"radius":radius}
	checked=_references("object_damage",d)
	if not checked.ok: return checked
	var record: Dictionary=records[id]
	var cuts: Array=record.get("damage",[]).duplicate(true); cuts.append({"center":center.duplicate(),"radius":radius})
	var replacement: MeshInstance3D=VoxelObject.create(api,record.definition,cuts)
	if replacement==null: return {"ok":false,"code":"creation.voxel_component_required"}
	var target: MeshInstance3D=game.body_node(record.definition.body).get_node_or_null("HarnessObject_"+id)
	if target==null: replacement.free(); return {"ok":false,"code":"creation.object_unavailable"}
	var removed: int=VoxelObject.occupied(target)-VoxelObject.occupied(replacement)
	if removed<=0: replacement.free(); return {"ok":false,"code":"creation.no_voxels_at_target"}
	target.mesh=replacement.mesh
	target.set_meta("harness_voxel_buffer",replacement.get_meta("harness_voxel_buffer"))
	target.set_meta("harness_voxel_channel",replacement.get_meta("harness_voxel_channel")); replacement.free()
	record["damage"]=cuts
	if notify: changed.emit()
	return {"ok":true,"result":{"object_id":id,"cuts":cuts.size(),"removed_voxels":removed,"world_changed":true}}
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
		if record.kind=="body": keys=["body_"+Body.body_id(d.id),"тело_"+Body.body_id(d.id)]
		if record.kind=="surface": keys=["body_"+Surface.body_id(d.id),"тело_"+Surface.body_id(d.id)]
		if record.kind=="resource": keys=["рес_"+str(record.resource_key),"resource_"+str(record.resource_key)]
		for key: String in keys:
			if not lang.dictionary.has(key): lang.dictionary[key]=_title(d); _name_keys.append(key)

func _flights() -> Node:
	if not is_instance_valid(ship_flight):
		ship_flight=preload("res://mods/pax_harness/src/creation/ship_flight.gd").new(); game.scene_root().add_child(ship_flight); ship_flight.setup(self)
	return ship_flight

func _programs() -> Node:
	if not is_instance_valid(programs):
		programs=preload("res://mods/pax_harness/src/creation/program_runtime.gd").new(); game.scene_root().add_child(programs); programs.setup(self)
	return programs
func definition_program_count(kind: String,d: Dictionary) -> int:
	if kind!="behavior" and not d.has("program"): return 0
	return records.values().filter(func(r: Dictionary): return r.definition.has("program") and r.definition.id!=d.get("id")).size()
func focus_flight(id: String) -> Dictionary:
	if not records.has(id): return {"ok":false,"code":"creation.flight_unavailable"}
	var r: Dictionary=records[id]; var placement: Dictionary=r.get("flight",{}).get("placement",{})
	if not placement.is_empty():
		if placement.get("focus_object","")!="": return focus_object(str(placement.focus_object))
		game.focus(str(placement.body),true); return {"ok":true}
	return focus_object(str(r.definition.get("object_id",r.definition.get("gate_id",""))))

func open_controls(id: String) -> Dictionary:
	if not current() or not records.has(id) or not records[id].get("definition",{}).get("program",{}).get("ui",{}).has("workspace"): return {"ok":false,"code":"creation.controls_unavailable"}
	var ui: Variant=game.scene_root().get("ui")
	if ui is Object and ui.get("menu_node") is Object and ui.menu_node.has_method("закрыть"): ui.menu_node.call("закрыть")
	if is_instance_valid(owner_mod.chat_ui): owner_mod.chat_ui.close()
	if is_instance_valid(view): view.window.hide()
	if not is_instance_valid(_program_windows.get("active")):
		var content:=preload("res://mods/pax_harness/src/creation/program_workspace.gd").new(); content.setup(self,id)
		var window: PanelContainer=game.add_window(L.text("Управление объектом"),content,Vector2(1000,720)); window.name="AuthoredObjectControls"; window.set_meta("controls_view",content); _program_windows["active"]=window
		for node: Node in game.hud_layer().find_children("*","Button",true,false):
			if node.text==L.text("Управление объектом"): window.set_meta("controls_button",node)
		content.close_requested.connect(window.hide)
	var active: PanelContainer=_program_windows.active
	if active.get_meta("controls_view").identity!=id: active.get_meta("controls_view").setup(self,id)
	active.show()
	return {"ok":true,"result":{"object_id":id,"controls_open":true,"world_changed":false}}
func focus_body(id: String,map_: bool=false) -> void:
	if is_instance_valid(object_navigation): object_navigation.active=false
	if is_instance_valid(owner_mod.chat_ui): owner_mod.chat_ui.close()
	if is_instance_valid(view): view.window.hide()
	var ui: Variant=game.scene_root().get("ui")
	if ui is Object and ui.get("menu_node") is Object and ui.menu_node.has_method("закрыть"): ui.menu_node.call("закрыть")
	var body: String=Body.body_id(id)
	if not map_: game.focus(body,true); return
	game.province_count(body)
	var result: Dictionary=preload("res://mods/pax_harness/src/visualization/maps/chart_map_data.gd").execute(game,{"body":body,"title":L.text("Провинции · ")+body_title(body),"source":L.text("Текущие данные провинций · ")+body_title(body)+", "+game.date_text()})
	if is_instance_valid(_surface_window): _surface_window.queue_free()
	var content:=VBoxContainer.new()
	if result.ok:
		var chart:=preload("res://mods/pax_harness/src/visualization/views/chat_chart_view.gd").new(); content.add_child(chart); chart.setup(result.result.chart)
	else:
		var error:=Label.new(); error.text=str(result.get("code","charts.geometry_unavailable")); error.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; content.add_child(error)
	_surface_window=game.add_window(body_title(body),content,Vector2(900,620)); _surface_window.name="AuthoredBodyMap"; _surface_window.show()
