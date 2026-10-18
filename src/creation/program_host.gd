extends RefCounted
## General world primitives. There is deliberately no gate/link/portal operation.
const Flight=preload("res://mods/pax_harness/src/creation/ship_flight.gd")
const VM=preload("res://mods/pax_harness/src/creation/program_vm.gd")
var service: Node
var record: Dictionary
var owner_id: String
func setup(value: Node,current: Dictionary,object_id: String) -> void:
	service=value; record=current; owner_id=object_id
static func schema() -> Dictionary:
	return {"body.read":"{body:discovered body} -> {body,parameters:actual climate,people:actual native population,colony:bool,radius_km}. Read-only.",
		"body.set":"{body:authored body or artificial surface,parameters:{one or more climate keys temperature/water/biomass/radiation/atmosphere/urban/magnetic:number0..1}} -> actual native climate readback. Only Harness-authored bodies; no habitat-specific logic. Native consequences occur through normal simulation.",
		"actor.read":"{id:dyson:<native ship title>,body?:discovered reference body} -> observed ship data; player vessels only; default coordinates relative to owner object's body",
		"actor.spawn":"{body:discovered body,name:unique ship title,model:ID from creation.capabilities.ship_flights.models,length_km?:0.01..100,position_km?:[x,y,z],forward?:[x,y,z]}. Creates one actual native player ship through the enabled Dyson adapter, returns its observed data. Source program defines queue, resource costs and timing; no shipyard preset. At most64 spawned actors per campaign from programs. No free cargo, passengers or research.",
		"actors.list":"{body?:discovered body,offset?:0,limit?:1..64} -> {actors:[...],next_offset}; optional Dyson adapter",
		"actor.move":"{id,body:discovered body,position_km:[x,y,z],forward:[x,y,z],focus_object?:approved object}. General relocation of SAME native entity; body-centred world axes in km, NOT object-local. Cancels old navigation/combat orders, preserves cargo/troops/health/model/owner; does not grant resources or advance calendar. Converts input to a body-fixed pose that survives scene reorientation on load; holds it until next native order. No gate assumptions.",
		"actor.set":"{id,values:{hp?:number,shield?:number}} -> observed state; each value must be within actual native maxima",
		"object.read":"{id:approved object} -> {id,body,position_km,axes:{x,y,z},definition}. position is body-centred, axes unit vectors. Use vadd/vscale to calculate any offset in a destination object's frame.",
		"object.move":"{id:approved object,position_km:[x,y,z]} -> observed position; retains model/orientation, persists with campaign",
		"object.damage":"{id:approved destructible object,center:[grid x,y,z],radius:0.25..16} -> actual removed voxels",
		"resource.add":"{body:existing colony,resource:existing native goods key,delta:number} -> actual before/after stock; uses native economy, not a display-only counter",
		"resource.read":"{body:existing colony,resource?:native goods key} -> {body,stock:{...actual stocks...},value?:number}; read-only, suitable for cost checks",
		"ui.message":"{text:string up to1000} -> program event log. Does not send external messages or invent a native world action."}
func ok(result: Variant) -> Dictionary: return {"ok":true,"result":result}
func bad(code: String,detail: String="") -> Dictionary: return {"ok":false,"code":code,"detail":detail}
func unit(id: String) -> Variant:
	if not id.begins_with("dyson:"): return null
	var mod: Node=Flight.provider(service.api); var code: Node=Flight.implementation(mod)
	if code==null: return null
	var title: String=id.trim_prefix("dyson:"); var summary: Dictionary=mod.call("get_ship",title)
	if summary.is_empty() or not summary.get("player",false): return null
	var actor: Variant=code.call("_find_ship",title)
	return actor if Flight.compatible(actor) and int(actor.peer)==0 else null
func actor_info(actor: Variant,relative_body: String,captured: Dictionary={}) -> Dictionary:
	var mod: Node=Flight.provider(service.api)
	var summary: Dictionary=mod.call("get_ship",actor.title) if captured.is_empty() else captured.duplicate(true)
	summary["star"]=str(actor.star)
	var hull: Node3D=actor.node.get_node("ShipHullRoot")
	var size: Vector3=Flight.bounds(hull).size*hull.global_basis.get_scale()
	var position: Vector3
	var anchor: String=str(actor.node.get_meta("harness_body",""))
	var relative: Dictionary=service.game.body(relative_body)
	if anchor!="" and is_instance_valid(service.game.body_node(anchor)):
		var parent: Node3D=service.game.body_node(anchor)
		var offset: Vector3=parent.global_basis*actor.node.position*1000.0
		var body: Dictionary=service.game.body(anchor)
		position=Vector3(float(body.kx)-float(relative.kx)+float(offset.x),float(body.get("ky",0))-float(relative.get("ky",0))+float(offset.y),float(body.kz)-float(relative.kz)+float(offset.z))
	else:
		var star: Dictionary=service.game.body(str(actor.star))
		position=Vector3(float(star.kx)+float(actor.x)*1000.0-float(relative.kx),float(star.get("ky",0))+float(actor.node.position.y)*1000.0-float(relative.get("ky",0)),float(star.kz)+float(actor.z)*1000.0-float(relative.kz))
	summary.merge({"id":"dyson:"+str(actor.title),"length_km":size[size.max_axis_index()]*1000.0,"relative_body":relative_body,"body_frame":anchor,"position_km":array(position),"entity_id":actor.get_instance_id()})
	return summary
static func array(v: Vector3) -> Array: return [v.x,v.y,v.z]
static func vector(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])
func owner_body() -> String:
	var current: Dictionary=service.records.get(owner_id,{})
	return preload("res://mods/pax_harness/src/creation/authored_body.gd").body_id(owner_id) if current.get("kind")=="body" else str(current.get("definition",{}).get("body",""))
func object_info(id: String) -> Dictionary:
	var target: Dictionary=service.records.get(id,{})
	if target.get("kind")=="body":
		var body: String=preload("res://mods/pax_harness/src/creation/authored_body.gd").body_id(id)
		var parent: Node3D=service.game.body_node(body)
		if not is_instance_valid(parent): return bad("creation.object_unavailable",id)
		var axes: Basis=parent.global_basis.orthonormalized()
		return ok({"id":id,"body":body,"position_km":[0,0,0],"axes":{"x":array(axes.x),"y":array(axes.y),"z":array(axes.z)},"definition":target.definition.duplicate(true)})
	if target.get("kind")!="object": return bad("creation.object_required",id)
	var d: Dictionary=target.definition; var body: Node3D=service.game.body_node(d.body)
	var node: Node3D=body.get_node_or_null("HarnessObject_"+id) if is_instance_valid(body) else null
	if node==null: return bad("creation.object_unavailable",id)
	var offset: Vector3=body.global_basis*(node.position+node.basis*node.get_meta("harness_model_center",Vector3.ZERO))
	var axes: Basis=node.global_basis.orthonormalized()
	return ok({"id":id,"body":d.body,"position_km":array(offset*1000.0),"axes":{"x":array(axes.x),"y":array(axes.y),"z":array(axes.z)},"definition":d.duplicate(true)})
func call_operation(name_: String,args: Dictionary) -> Dictionary:
	var result: Dictionary=execute(name_,args)
	if result.ok and name_ not in ["actor.read","actors.list","object.read","resource.read","body.read"]:
		if not record.runtime.has("receipts"): record.runtime["receipts"]=[]
		record.runtime.receipts.append({"operation":name_,"result":result.get("result"),"time":record.runtime.get("clock",0)})
		while record.runtime.receipts.size()>24: record.runtime.receipts.pop_front()
	return result
func execute(name_: String,a: Dictionary) -> Dictionary:
	match name_:
		"body.read","body.set":
			var body: String=str(a.get("body",""))
			if body not in service.game.body_names() or not service.game.body(body).get("open",false): return bad("tools.unknown_or_hidden_body")
			if name_=="body.set":
				var owned: bool=service.records.values().any(func(r: Dictionary): return (r.kind=="body" and preload("res://mods/pax_harness/src/creation/authored_body.gd").body_id(r.definition.id)==body) or (r.kind=="surface" and preload("res://mods/pax_harness/src/creation/artificial_surface.gd").body_id(r.definition.id)==body))
				if not owned: return bad("program.authored_body_required")
				if not a.get("parameters") is Dictionary or a.parameters.is_empty() or a.parameters.keys().any(func(k: Variant): return k not in ["temperature","water","biomass","radiation","atmosphere","urban","magnetic"]) or a.parameters.values().any(func(v: Variant): return not VM.numeric(v) or float(v)<0 or float(v)>1): return bad("program.invalid_climate")
				for key: String in a.parameters: service.game.set_body_param(body,key,float(a.parameters[key]))
			return ok({"body":body,"parameters":service.game.body_params(body).duplicate(true),"people":service.game.colony_people(body) if body in service.game.colonies() else 0,"colony":body in service.game.colonies(),"radius_km":service.game.body(body).r_km})
		"actor.spawn": return spawn(a)
		"resource.read":
			if not a.get("body") is String or a.body not in service.game.colonies(): return bad("tools.colony_not_found")
			var stock: Dictionary=service.game.resources(a.body).duplicate(true)
			if a.has("resource") and (not a.resource is String or not service.game.econ.goods().has(a.resource)): return bad("program.invalid_resource_change")
			return ok({"body":a.body,"stock":stock,"value":float(stock.get(a.resource,0))} if a.has("resource") else {"body":a.body,"stock":stock})
		"object.read": return object_info(str(a.get("id","")))
		"ui.message":
			if not a.get("text") is String or a.text.length()>1000: return bad("program.invalid_message")
			return ok({"text":a.text})
		"actors.list":
			var mod: Node=Flight.provider(service.api)
			if mod==null: return bad("program.actor_adapter_unavailable")
			var body: String=str(a.get("body",owner_body()))
			if body not in service.game.body_names() or not service.game.body(body).get("open",false): return bad("tools.unknown_or_hidden_body")
			var offset: int=int(a.get("offset",0)); var limit: int=int(a.get("limit",64))
			if offset<0 or limit<1 or limit>64: return bad("program.invalid_page")
			var ships: Array=mod.call("get_ships","player"); var rows: Array=[]
			for summary: Dictionary in ships.slice(offset,offset+limit):
				var actor: Variant=unit("dyson:"+str(summary.title))
				if actor!=null: rows.append(actor_info(actor,body))
			return ok({"actors":rows,"next_offset":offset+limit if offset+limit<ships.size() else -1})
		"actor.read","actor.move","actor.set":
			var actor: Variant=unit(str(a.get("id","")))
			if actor==null: return bad("program.actor_unavailable",str(a.get("id","")))
			if name_=="actor.read":
				var body: String=str(a.get("body",owner_body()))
				if body not in service.game.body_names() or not service.game.body(body).get("open",false): return bad("tools.unknown_or_hidden_body")
				return ok(actor_info(actor,body))
			if name_=="actor.move":
				if not a.get("body") is String or not VM.vector(a.get("position_km")) or not VM.vector(a.get("forward")) or vector(a.forward).length()<0.001 or a.position_km.any(func(x: Variant): return absf(float(x))>1e9): return bad("program.invalid_actor_position")
				if a.get("focus_object","")!="" and (not service.records.has(a.focus_object) or service.records[a.focus_object].kind!="object" or service.records[a.focus_object].definition.body!=a.body): return bad("program.invalid_focus_object")
				service._programs().before_move(str(a.id))
				var result: Dictionary=service._flights().relocate(actor,a.body,a.position_km,a.forward,str(a.get("focus_object","")))
				if result.ok: service._programs().invalidate_actor(str(a.id))
				if result.ok and not result.get("binding",{}).is_empty():
					if not record.runtime.has("placements"): record.runtime["placements"]={}
					record.runtime.placements[str(a.id)]=result.binding
				return result
			if not a.get("values") is Dictionary or a.values.is_empty() or a.values.keys().any(func(k: Variant): return k not in ["hp","shield"]): return bad("program.invalid_actor_fields")
			var before: Dictionary=Flight.provider(service.api).call("get_ship",actor.title)
			for key: String in a.values:
				if not VM.numeric(a.values[key]) or float(a.values[key])<0 or float(a.values[key])>float(before.get(key+"_max",0)): return bad("program.actor_value_out_of_range",key)
			for key: String in a.values: actor.set(key,float(a.values[key]))
			return ok(actor_info(actor,owner_body()))
		"object.move":
			if not VM.vector(a.get("position_km")) or a.position_km.any(func(x: Variant): return absf(float(x))>1e9): return bad("program.invalid_object_position")
			var id: String=str(a.get("id","")); var current: Dictionary=object_info(id)
			if not current.ok: return current
			if service.records[id].kind!="object": return bad("program.body_motion_unsupported")
			var body: Node3D=service.game.body_node(current.result.body); var node: Node3D=body.get_node("HarnessObject_"+id)
			node.position=body.global_basis.inverse()*vector(a.position_km)/1000.0-node.basis*node.get_meta("harness_model_center",Vector3.ZERO)
			service.records[id]["transform"]={"position_km":a.position_km.duplicate()}
			return object_info(id)
		"object.damage":
			if not VM.vector(a.get("center")) or not VM.numeric(a.get("radius")): return bad("creation.invalid_damage")
			return service.damage_from_player(str(a.get("id","")),a.center,float(a.radius),false)
		"resource.add":
			if not a.get("body") is String or a.body not in service.game.colonies() or not a.get("resource") is String or not service.game.econ.goods().has(a.resource) or not VM.numeric(a.get("delta")) or absf(float(a.delta))>1e15: return bad("program.invalid_resource_change")
			var before: float=float(service.game.resources(a.body).get(a.resource,0))
			service.game.add_resource(a.body,a.resource,float(a.delta))
			return ok({"body":a.body,"resource":a.resource,"before":before,"after":service.game.resources(a.body).get(a.resource,0)})
	return bad("program.unknown_host_operation",name_)

func spawn(a: Dictionary) -> Dictionary:
	var caps: Dictionary=Flight.info(service.api)
	if not caps.get("available",false): return bad("program.actor_adapter_unavailable")
	if not a.get("body") is String or a.body not in service.game.body_names() or not service.game.body(a.body).get("open",false): return bad("tools.unknown_or_hidden_body")
	if not a.get("name") is String or a.name.strip_edges().is_empty() or a.name.length()>160 or a.get("model","") not in caps.models: return bad("program.invalid_actor_definition")
	if a.has("length_km") and (not VM.numeric(a.length_km) or float(a.length_km)<0.01 or float(a.length_km)>100): return bad("program.invalid_actor_definition")
	var point: Variant=a.get("position_km",[float(service.game.body(a.body).r_km)+10,0,0]); var forward: Variant=a.get("forward",[0,0,1])
	if not VM.vector(point) or not VM.vector(forward) or vector(forward).length()<0.001 or point.any(func(x: Variant): return absf(float(x))>1e9): return bad("program.invalid_actor_position")
	var total:=0
	for r: Dictionary in service.records.values(): total+=r.get("runtime",{}).get("spawned_actors",[]).size()
	if total>=64: return bad("program.spawn_limit")
	var mod: Node=Flight.provider(service.api)
	if not mod.call("get_ship",a.name).is_empty(): return bad("creation.ship_name_exists")
	if str(mod.call("spawn_ship",a.body,{"name":a.name,"model":a.model,"size":1.0}))!=a.name: return bad("creation.native_ship_spawn_failed")
	var actor: Variant=unit("dyson:"+str(a.name))
	if actor==null: mod.call("remove_ship",a.name); return bad("creation.dyson_ship_scene_incompatible")
	var result: Dictionary=service._flights().relocate(actor,a.body,point,forward)
	if not result.ok: mod.call("remove_ship",a.name); return result
	if a.has("length_km"):
		for f: Dictionary in service._flights().flights.values():
			if f.unit!=actor: continue
			f.definition.ship_length_km=float(a.length_km); f.erase("hull_scale"); service._flights()._pose(f)
	if not record.runtime.has("placements"): record.runtime["placements"]={}
	record.runtime.placements["dyson:"+str(a.name)]=result.binding
	if not record.runtime.has("spawned_actors"): record.runtime["spawned_actors"]=[]
	record.runtime.spawned_actors.append("dyson:"+str(a.name))
	return ok(actor_info(actor,a.body))
