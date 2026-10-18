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
	return {"actor.read":"{id:dyson:<native ship title>,body?:discovered reference body} -> observed ship data; player vessels only; default coordinates relative to owner object's body",
		"actors.list":"{body?:discovered body,offset?:0,limit?:1..64} -> {actors:[...],next_offset}; optional Dyson adapter",
		"actor.move":"{id,body:discovered body,position_km:[x,y,z],forward:[x,y,z],focus_object?:approved object}. General relocation of SAME native entity; body-centred world axes in km, NOT object-local. Cancels old navigation/combat orders, preserves cargo/troops/health/model/owner; does not grant resources or advance calendar. Converts input to a body-fixed pose that survives scene reorientation on load; holds it until next native order. No gate assumptions.",
		"actor.set":"{id,values:{hp?:number,shield?:number}} -> observed state; each value must be within actual native maxima",
		"object.read":"{id:approved object} -> {id,body,position_km,axes:{x,y,z},definition}. position is body-centred, axes unit vectors. Use vadd/vscale to calculate any offset in a destination object's frame.",
		"object.move":"{id:approved object,position_km:[x,y,z]} -> observed position; retains model/orientation, persists with campaign",
		"object.damage":"{id:approved destructible object,center:[grid x,y,z],radius:0.25..16} -> actual removed voxels",
		"resource.add":"{body:existing colony,resource:existing native goods key,delta:number} -> actual before/after stock; uses native economy, not a display-only counter",
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
func object_info(id: String) -> Dictionary:
	var target: Dictionary=service.records.get(id,{})
	if target.get("kind")!="object": return bad("creation.object_required",id)
	var d: Dictionary=target.definition; var body: Node3D=service.game.body_node(d.body)
	var node: Node3D=body.get_node_or_null("HarnessObject_"+id) if is_instance_valid(body) else null
	if node==null: return bad("creation.object_unavailable",id)
	var offset: Vector3=body.global_basis*(node.position+node.basis*node.get_meta("harness_model_center",Vector3.ZERO))
	var axes: Basis=node.global_basis.orthonormalized()
	return ok({"id":id,"body":d.body,"position_km":array(offset*1000.0),"axes":{"x":array(axes.x),"y":array(axes.y),"z":array(axes.z)},"definition":d.duplicate(true)})
func call_operation(name_: String,args: Dictionary) -> Dictionary:
	var result: Dictionary=execute(name_,args)
	if result.ok and name_ not in ["actor.read","actors.list","object.read"]:
		if not record.runtime.has("receipts"): record.runtime["receipts"]=[]
		record.runtime.receipts.append({"operation":name_,"result":result.get("result"),"time":record.runtime.get("clock",0)})
		while record.runtime.receipts.size()>24: record.runtime.receipts.pop_front()
	return result
func execute(name_: String,a: Dictionary) -> Dictionary:
	match name_:
		"object.read": return object_info(str(a.get("id","")))
		"ui.message":
			if not a.get("text") is String or a.text.length()>1000: return bad("program.invalid_message")
			return ok({"text":a.text})
		"actors.list":
			var mod: Node=Flight.provider(service.api)
			if mod==null: return bad("program.actor_adapter_unavailable")
			var body: String=str(a.get("body",service.records.get(owner_id,{}).get("definition",{}).get("body","")))
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
				var body: String=str(a.get("body",service.records.get(owner_id,{}).get("definition",{}).get("body","")))
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
			return ok(actor_info(actor,service.records[owner_id].definition.body))
		"object.move":
			if not VM.vector(a.get("position_km")) or a.position_km.any(func(x: Variant): return absf(float(x))>1e9): return bad("program.invalid_object_position")
			var id: String=str(a.get("id","")); var current: Dictionary=object_info(id)
			if not current.ok: return current
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
