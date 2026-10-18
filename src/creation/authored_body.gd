extends RefCounted
## General artificial rocky body with native provinces and optional authored visual.
const Surface=preload("res://mods/pax_harness/src/creation/artificial_surface.gd")
static func body_id(id: String) -> String: return "harness_body_"+id
static func create(service: Node,d: Dictionary) -> Dictionary:
	var game: RefCounted=service.game; var name: String=body_id(d.id)
	if not Surface.available(game): return {"ok":false,"code":"creation.native_surface_unavailable"}
	if name in game.body_names() and game.body(name).get("harness_body_id")!=d.id: return {"ok":false,"code":"creation.surface_name_collision"}
	if name not in game.body_names():
		var by_name: Dictionary={}
		for key: String in game.body_names(): by_name[key]=game.body(key)
		game.scene_root().sky_builder().create_body({"name":name,"genus":"rock","r":d.radius_km,"a":d.orbit_radius_km,"satellite":d.body,"period":d.period_days,"open":true,"parameters":d.climate.duplicate(true),"sid":float(absi(d.id.hash())%10000)/100.0},by_name)
		if name not in game.body_names(): return {"ok":false,"code":"creation.native_surface_refused"}
		var body: Dictionary=game.body(name); body["harness_body_id"]=d.id; body["harness_body_names"]=d.name.duplicate(true); body["provinces_count"]=int(d.provinces_count)
		var names: Array=[]
		for i: int in int(d.provinces_count): names.append({"ru":str(d.name.ru)+" · "+str(i+1),"en":str(d.name.en)+" · "+str(i+1)})
		body["provinces_names"]=names
	var count: int=game.province_count(name)
	game.scene_root().call("_разместить_тела")
	var parent: Node3D=game.body_node(name)
	if not is_instance_valid(parent): return {"ok":false,"code":"creation.body_scene_unavailable"}
	var node_name: String="HarnessObject_"+str(d.id)
	if d.has("model") and parent.get_node_or_null(node_name)==null:
		var mesh: MeshInstance3D=service.api.voxel.model(d.model)
		if mesh==null: return {"ok":false,"code":"creation.model_unavailable"}
		preload("res://mods/pax_harness/src/creation/voxel_object.gd").space_material(mesh)
		mesh.name=node_name; parent.add_child(mesh)
		var center: Vector3=mesh.get_aabb().get_center()
		mesh.scale=Vector3.ONE*2.0/maxf(mesh.get_aabb().size[mesh.get_aabb().size.max_axis_index()],0.001); mesh.position=-(mesh.basis*center); mesh.set_meta("harness_model_center",center)
		# Keep the native mesh/resource intact for climate and map services; only its
		# render layer is hidden. Child models remain ordinary visible geometry.
		if parent is VisualInstance3D: parent.layers=0
		# Clouds and distance markers are separate nodes, not children of the sphere.
		for key: String in ["clouds","ring","point"]:
			var visual: Variant=game.body(name).get(key)
			if visual is VisualInstance3D: visual.layers=0
	return {"ok":count==int(d.provinces_count),"body":name,"province_count":count,"population_granted":false,"code":"creation.surface_provinces_unverified" if count!=int(d.provinces_count) else ""}
