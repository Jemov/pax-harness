extends Node
## Optional DSP adapter. Uses a real registered ship and its original hull, never a copy.
## DSP navigation is planar; this explicit local flight owns its 3D pose until a new
## native order is given. Saved progress is relative to the gate, not floating-origin coordinates.
const MOD_ID="dyson_sphere_program"
var service: Node
var flights: Dictionary={}
static func constants_of(node: Node) -> Dictionary:
	var result: Dictionary={}; var script: Script=node.get_script()
	while script!=null:
		result.merge(script.get_script_constant_map(),false); script=script.get_base_script()
	return result

static func provider(api: Node) -> Node:
	if api==null or not api.has_method("get_mod"): return null
	var mod: Variant=api.call("get_mod",MOD_ID)
	return mod if mod is Node and mod.has_method("is_ready") and mod.call("is_ready") and mod.has_method("get_ships") and mod.has_method("spawn_ship") else null
static func implementation(mod: Node) -> Node:
	if mod==null: return null
	var code: Node=mod.get_node_or_null("Code")
	return code if code!=null and code.has_method("_find_ship") and code.has_method("_star_for_body") else null
static func info(api: Node) -> Dictionary:
	var mod: Node=provider(api); var code: Node=implementation(mod)
	if mod==null or code==null: return {"available":false,"code":"creation.dyson_flight_unavailable","instruction":"Enable Dyson Sphere Program and load a campaign. This local-flight adapter also requires compatible ship scene fields; never claim a ship moved if unavailable."}
	var constants: Dictionary=constants_of(code)
	return {"available":true,"provider":MOD_ID,"ships":mod.call("get_ships","player"),"models":Array(constants.get("SHIP_MESH_MODEL_FILES",{}).keys()),"local_3d_flight":true,"actor_relocation":code.has_method("_get_platform"),"clock":"elapsed scene seconds, including while game time is paused"}
func setup(value: Node) -> void:
	service=value
	var code: Node=implementation(provider(service.api))
	process_priority=maxi(1100,code.process_priority+100) if code!=null else 1100
static func target_id(d: Dictionary) -> String:
	return str(d.get("object_id",d.get("gate_id","")))
func gate(d: Dictionary) -> MeshInstance3D:
	var id: String=target_id(d); var r: Dictionary=service.records.get(id,{})
	if r.get("kind")!="object": return null
	var body: Node3D=service.game.body_node(r.definition.body)
	return body.get_node_or_null("HarnessObject_"+id) if is_instance_valid(body) else null
func validate(d: Dictionary) -> Dictionary:
	var details: Dictionary=info(service.api)
	if not details.available: return {"ok":false,"code":"creation.dyson_flight_unavailable"}
	var g: MeshInstance3D=gate(d)
	if g==null: return {"ok":false,"code":"creation.warp_gate_required"}
	var gd: Dictionary=service.records[target_id(d)].definition
	var rings: Array=gd.model.get("shapes",[]).filter(func(s: Dictionary): return s.type=="torus")
	if not d.has("waypoints_km"):
		if gd.get("behavior")!="warp_gate" or rings.size()!=1: return {"ok":false,"code":"creation.explicit_flight_path_required"}
		var ring: Dictionary=rings[0]
		var aperture: float=2.0*(float(ring.radius)-float(ring.tube))*float(gd.size_km)/float(gd.model.size.max())
		if float(d.ship_length_km)>aperture*0.6: return {"ok":false,"code":"creation.ship_exceeds_gate_clearance"}
	var mod: Node=provider(service.api)
	var existing: Dictionary=mod.call("get_ship",d.ship_name)
	if d.has("spawn_model"):
		if not existing.is_empty(): return {"ok":false,"code":"creation.ship_name_exists"}
		if d.spawn_model not in details.models: return {"ok":false,"code":"creation.unknown_ship_model"}
	elif existing.is_empty() or not existing.get("player",false): return {"ok":false,"code":"creation.player_ship_required"}
	else:
		var unit: Variant=implementation(mod).call("_find_ship",d.ship_name)
		if not compatible(unit) or existing.state not in ["idle","orbiting"] or existing.fighting or existing.bombarding!="" or not unit.cargo.is_empty() or not unit.troops.is_empty() or str(unit.fleet)!="" or int(unit.peer)!=0: return {"ok":false,"code":"creation.ship_busy"}
		if str(unit.star)!=str(implementation(mod).call("_star_for_body",service.game,gd.body)): return {"ok":false,"code":"creation.ship_in_other_system"}
	for r: Dictionary in service.records.values():
		if r.kind=="ship_flight" and r.definition.ship_name==d.ship_name and r.get("flight",{}).get("status") in ["flying","parked"]: return {"ok":false,"code":"creation.ship_already_controlled"}
	return {"ok":true}
static func compatible(unit: Variant) -> bool:
	if not unit is Object: return false
	var names: Array=[]
	for p: Dictionary in unit.get_property_list(): names.append(str(p.name))
	return ["node","x","z","vis_x","vis_z","state","anchor_body","target_body","peer","cargo","troops","fleet","star","size","visual"].all(func(k: String): return k in names) and unit.get("node") is Node3D and unit.get("node").get_node_or_null("ShipHullRoot") is Node3D
func start(d: Dictionary) -> Dictionary:
	var valid: Dictionary=validate(d)
	if not valid.ok: return valid
	var mod: Node=provider(service.api)
	var spawned: bool=d.has("spawn_model")
	if spawned and str(mod.call("spawn_ship",service.records[target_id(d)].definition.body,{"name":d.ship_name,"model":d.spawn_model,"size":1.0}))!=d.ship_name: return {"ok":false,"code":"creation.native_ship_spawn_failed"}
	var unit: Variant=implementation(mod).call("_find_ship",d.ship_name)
	if not compatible(unit):
		if spawned: mod.call("remove_ship",d.ship_name)
		return {"ok":false,"code":"creation.dyson_ship_scene_incompatible"}
	var state: Dictionary={"status":"flying","progress":0.0,"crossed":false,"ship_name":d.ship_name,"spawned":spawned,"native_size":float(unit.size)}
	unit.state="idle"; unit.anchor_body=""; unit.target_body=""
	flights[d.id]={"definition":d.duplicate(true),"flight":state,"unit":unit}
	_pose(flights[d.id])
	return {"ok":true,"flight":state,"native_ship":mod.call("get_ship",d.ship_name)}
func restore_record(record: Dictionary) -> void:
	var mod: Node=provider(service.api)
	var code: Node=implementation(mod)
	var unit: Variant=code.call("_find_ship",record.definition.ship_name) if code!=null else null
	if not compatible(unit): record.flight.status="unavailable"; return
	if record.flight.status not in ["flying","parked"]: return
	flights[record.definition.id]={"definition":record.definition,"flight":record.flight,"unit":unit}
	_pose(flights[record.definition.id])
func replay(id: String) -> Dictionary:
	if not flights.has(id): return {"ok":false,"code":"creation.flight_unavailable"}
	var f: Dictionary=flights[id]
	if not compatible(f.unit) or f.unit.state!="idle": return {"ok":false,"code":"creation.ship_busy"}
	if is_instance_valid(service.programs): service.programs.before_move("dyson:"+str(f.unit.title))
	if f.flight.has("placement"):
		var code: Node=implementation(provider(service.api))
		if code==null or not code.has_method("_get_platform"): return {"ok":false,"code":"program.actor_adapter_unavailable"}
		f.unit.star=str(code.call("_star_for_body",service.game,service.records[target_id(f.definition)].definition.body))
		f["native_parent"]=code.call("_get_platform",f.unit.star); f.flight.erase("placement")
	f.flight.progress=0.0; f.flight.crossed=false; f.flight.status="flying"
	service.focus_object(target_id(f.definition)); _pose(f)
	if is_instance_valid(service.programs): service.programs.invalidate_actor("dyson:"+str(f.unit.title))
	service.changed.emit()
	return {"ok":true}
func relocate(unit: Variant,body: String,point: Array,forward: Array,focus: String="") -> Dictionary:
	var code: Node=implementation(provider(service.api))
	if not compatible(unit) or code==null or not code.has_method("_get_platform"): return {"ok":false,"code":"program.actor_adapter_unavailable"}
	if body not in service.game.body_names() or not service.game.body(body).get("open",false): return {"ok":false,"code":"tools.unknown_or_hidden_body"}
	var star: String=str(code.call("_star_for_body",service.game,body))
	if star=="": return {"ok":false,"code":"program.destination_unavailable"}
	var f: Dictionary={}; var binding: Dictionary={}
	for candidate: Dictionary in flights.values():
		if candidate.unit==unit: f=candidate; break
	if f.is_empty():
		var hull: Node3D=unit.node.get_node("ShipHullRoot")
		var size: Vector3=bounds(hull).size*hull.global_basis.get_scale()
		var d: Dictionary={"id":"actor_"+str(unit.title).sha256_text().left(16),"object_id":focus,"ship_name":str(unit.title),"ship_length_km":size[size.max_axis_index()]*1000.0,"duration_seconds":6.0}
		var state: Dictionary={"status":"parked","progress":1.0,"crossed":false,"native_size":float(unit.size),"ship_name":str(unit.title)}
		f={"definition":d,"flight":state,"unit":unit}; flights[d.id]=f
		binding={"definition":d,"flight":state}
	var before: Dictionary=provider(service.api).call("get_ship",unit.title)
	var entity: int=unit.get_instance_id()
	unit.star=star; unit.state="idle"; unit.anchor_body=""; unit.target_body=""
	for key: String in ["gate_target","route_body","bombard_body","attack_title"]: unit.set(key,"")
	for key: String in ["route","route_point"]:
		var array: Variant=unit.get(key)
		if array is Array: array.clear()
	unit.set("attack_target",null); unit.set("attack_station",null); unit.set("fighting",false)
	f["native_parent"]=code.call("_get_platform",star)
	# Persist in the body's own frame: native scenes may re-create its orientation
	# on load. World-aligned input is converted once, without any object assumptions.
	var parent: Node3D=service.game.body_node(body)
	var local_point: Vector3=parent.global_basis.inverse()*Vector3(point[0],point[1],point[2])/1000.0
	var local_forward: Vector3=parent.global_basis.orthonormalized().inverse()*Vector3(forward[0],forward[1],forward[2]).normalized()
	f.flight["placement"]={"body":body,"position_km":point.duplicate(),"forward":forward.duplicate(),"body_local_position":[local_point.x,local_point.y,local_point.z],"body_local_forward":[local_forward.x,local_forward.y,local_forward.z],"focus_object":focus}
	f.flight.status="parked"; _pose(f)
	var after: Dictionary=provider(service.api).call("get_ship",unit.title)
	var kept: bool=["owner","cargo","troops","hp","hp_max","shield","shield_max","weapons","model","fleet"].all(func(k: String): return before.get(k)==after.get(k))
	if not kept or unit.get_instance_id()!=entity: return {"ok":false,"code":"program.actor_state_mismatch"}
	if focus!="": service.focus_object(focus)
	else: service.game.focus(body,true)
	return {"ok":true,"binding":binding,"result":{"actor":"dyson:"+str(unit.title),"entity_id":entity,"body":body,"star":star,"position_km":point.duplicate(),"same_entity":true,"cargo_passengers_health_preserved":kept,"calendar_day":service.game.day()}}
func _process(delta: float) -> void:
	if not is_instance_valid(service) or not service.current(): return
	for id: String in flights.keys():
		var f: Dictionary=flights[id]
		if not compatible(f.unit) or not is_instance_valid(f.unit.node) or (not f.flight.has("placement") and gate(f.definition)==null):
			_release(f); f.flight.status="unavailable"; flights.erase(id); service.changed.emit(); continue
		if f.unit.state!="idle" or f.unit.anchor_body!="" or f.unit.target_body!="":
			f.flight.status="released"; _release(f)
			flights.erase(id); service.changed.emit(); continue
		if f.flight.status=="flying":
			f.flight.progress=minf(1.0,float(f.flight.progress)+minf(delta,0.25)/float(f.definition.duration_seconds))
			f.flight.crossed=not f.definition.has("waypoints_km") and float(f.flight.progress)>=0.5
			if f.flight.progress>=1.0: f.flight.status="parked"; service.changed.emit()
		_pose(f)
func _release(f: Dictionary) -> void:
	if not is_instance_valid(f.unit) or not is_instance_valid(f.unit.node): return
	if is_instance_valid(f.get("native_parent")):
		f.unit.node.reparent(f.native_parent,false)
		f.unit.node.position=Vector3(float(f.unit.x),float(f.get("native_y",0)),float(f.unit.z))
	var hull: Node3D=f.unit.node.get_node_or_null("ShipHullRoot")
	if hull!=null: hull.scale=Vector3.ONE*float(f.flight.native_size)
	if is_instance_valid(f.unit.visual): f.unit.visual.show()
	if f.unit.node.has_meta("harness_body"): f.unit.node.remove_meta("harness_body")
func _exit_tree() -> void:
	for f: Dictionary in flights.values(): _release(f)
static func bounds(node: Node3D, to_root: Transform3D=Transform3D.IDENTITY) -> AABB:
	var out:=AABB()
	if node is MeshInstance3D and node.mesh!=null: out=to_root*node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var b: AABB=bounds(child,to_root*child.transform)
			if b.size!=Vector3.ZERO: out=b if out.size==Vector3.ZERO else out.merge(b)
	return out
static func flight_basis(direction: Vector3, forward_axis: String="-z") -> Basis:
	var yaw: float={"-z":0.0,"+z":PI,"+x":PI*0.5,"-x":-PI*0.5}.get(forward_axis,0.0)
	return Basis.looking_at(direction,Vector3.RIGHT if absf(direction.y)>0.99 else Vector3.UP)*Basis(Vector3.UP,yaw)
static func path_pose(points: Array, progress: float) -> Dictionary:
	var total:=0.0
	for i: int in range(1,points.size()): total+=Vector3(points[i][0]-points[i-1][0],points[i][1]-points[i-1][1],points[i][2]-points[i-1][2]).length()
	var left: float=clampf(progress,0,1)*total
	for i: int in range(1,points.size()):
		var a:=Vector3(points[i-1][0],points[i-1][1],points[i-1][2]); var b:=Vector3(points[i][0],points[i][1],points[i][2])
		var length_: float=a.distance_to(b)
		if length_<=0.000001: continue
		if left<=length_ or i==points.size()-1: return {"position":a.lerp(b,clampf(left/length_,0,1)),"direction":(b-a).normalized()}
		left-=length_
	return {"position":Vector3.ZERO,"direction":Vector3.FORWARD}
func _pose(f: Dictionary) -> void:
	var d: Dictionary=f.definition
	var placed: Dictionary=f.flight.get("placement",{})
	var actual_id: String=target_id(d)
	var g: MeshInstance3D=gate({"object_id":actual_id}) if placed.is_empty() else null
	if placed.is_empty() and g==null: return
	var gd: Dictionary=service.records[actual_id].definition if placed.is_empty() else {"body":placed.body,"model":{"size":[1,1,1]}}
	var grid_size:=Vector3(float(gd.model.size[0]),float(gd.model.size[1]),float(gd.model.size[2]))
	var unit: Variant=f.unit; var node: Node3D=unit.node
	var km_unit: float=float(service.game.scene_root().get_script().get_script_constant_map().get("UNIT",1000.0))
	var parent: Node3D=service.game.body_node(gd.body)
	if not f.has("native_parent"):
		f["native_parent"]=node.get_parent(); f["native_y"]=node.position.y
		# A star-relative float transform loses kilometres at planetary distances.
		# Keep the actual vessel near the gate's body in the rebased render tree.
	if node.get_parent()!=parent: node.reparent(parent,false)
	var span: float=(g.global_basis*grid_size).length()/sqrt(3.0) if g!=null else 0.0
	var offset: float=(float(f.flight.progress)*2.0-1.0)*span*1.2
	var position: Vector3; var normal: Vector3
	if not placed.is_empty():
		position=parent.global_position+Vector3(placed.position_km[0],placed.position_km[1],placed.position_km[2])/km_unit
		normal=Vector3(placed.forward[0],placed.forward[1],placed.forward[2]).normalized()
		if placed.has("body_local_forward"):
			normal=parent.global_basis.orthonormalized()*Vector3(placed.body_local_forward[0],placed.body_local_forward[1],placed.body_local_forward[2])
	elif d.has("waypoints_km"):
		var pose: Dictionary=path_pose(d.waypoints_km,float(f.flight.progress))
		var orientation: Basis=g.global_basis.orthonormalized()
		position=g.to_global(g.get_meta("harness_model_center",g.get_aabb().get_center()))+orientation*pose.position/km_unit
		normal=orientation*pose.direction
	else:
		var ring: Dictionary=gd.model.shapes.filter(func(s: Dictionary): return s.type=="torus")[0]
		var center: Vector3=g.to_global(Vector3(float(ring.center[0]),float(ring.center[1]),float(ring.center[2]))-grid_size*0.5)
		var axis: int={"x":0,"y":1,"z":2}.get(str(ring.get("axis","y")),1)
		normal=g.global_basis[axis].normalized(); position=center+normal*offset
	# Native models need an explicit nose convention: Godot forward is -Z.
	# Keep trajectory direction independent of mesh orientation, rather than
	# silently assuming the hull's +Z points toward the nose.
	if not placed.is_empty():
		node.global_basis=flight_basis(normal,str(d.get("forward_axis","-z")))
		node.position=Vector3(placed.body_local_position[0],placed.body_local_position[1],placed.body_local_position[2]) if placed.has("body_local_position") else parent.global_basis.inverse()*Vector3(placed.position_km[0],placed.position_km[1],placed.position_km[2])/km_unit
		var current_point: Vector3=parent.global_basis*node.position*km_unit
		placed.position_km=[current_point.x,current_point.y,current_point.z]; placed.forward=[normal.x,normal.y,normal.z]
	else: node.global_transform=Transform3D(flight_basis(normal,str(d.get("forward_axis","-z"))),position)
	node.set_meta("harness_body",str(gd.body))
	f.flight["forward_axis"]=str(d.get("forward_axis","-z"))
	var hull: Node3D=node.get_node("ShipHullRoot")
	if not f.has("hull_scale"):
		hull.scale=Vector3.ONE
		var box: AABB=bounds(hull)
		f["hull_scale"]=float(d.ship_length_km)/km_unit/maxf(0.000001,box.size[box.size.max_axis_index()])
	hull.scale=Vector3.ONE*float(f.hull_scale)
	# Logical x/z follow the same registered native entity. Local y is owned by this
	# adapter because DSP's normal navigation constrains it to a fixed plane.
	var body_data: Dictionary=service.game.body(gd.body); var star_data: Dictionary=service.game.body(str(unit.star))
	var local_offset: Vector3=parent.global_basis*node.position
	unit.x=(float(body_data.get("kx",0))-float(star_data.get("kx",0)))/km_unit+float(local_offset.x)
	unit.z=(float(body_data.get("kz",0))-float(star_data.get("kz",0)))/km_unit+float(local_offset.z)
	unit.vis_x=unit.x; unit.vis_z=unit.z
	node.show(); node.get_parent().show()
	if unit.visual is Node3D: unit.visual.hide()
