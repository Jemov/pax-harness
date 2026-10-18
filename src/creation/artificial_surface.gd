extends RefCounted
## Bounded adapter to the native body builder. No player-supplied scripts or paths.
## The rock shell is a separate body: the original star/giant keeps its kind and climate.
static func body_id(id: String) -> String:
	return "harness_surface_"+id
static func available(game: RefCounted) -> bool:
	var root: Node=game.scene_root()
	return root.has_method("sky_builder") and root.has_method("scouting") and root.has_method("_разместить_тела")
static func create(game: RefCounted, d: Dictionary) -> Dictionary:
	if not available(game): return {"ok":false,"code":"creation.native_surface_unavailable"}
	var name: String=body_id(d.id)
	if name in game.body_names():
		return {"ok":true,"body":name} if game.body(name).get("harness_surface_id")==d.id else {"ok":false,"code":"creation.surface_name_collision"}
	var root: Node=game.scene_root(); var builder: Variant=root.sky_builder()
	if not builder.has_method("create_body"): return {"ok":false,"code":"creation.native_surface_unavailable"}
	var parent: Dictionary=game.body(d.body)
	var by_name: Dictionary={}
	for key: String in game.body_names(): by_name[key]=game.body(key)
	var spec: Dictionary={"name":name,"genus":"rock","r":float(parent.r_km)+float(d.altitude_km),"a":0.0,"satellite":d.body,"period":0.0,"open":true,"parameters":d.climate.duplicate(true),"sid":float(d.id.hash()%10000)/100.0}
	builder.create_body(spec,by_name)
	var body: Dictionary=game.body(name)
	if body.is_empty(): return {"ok":false,"code":"creation.native_surface_refused"}
	body["harness_surface_id"]=d.id; body["harness_surface_parent"]=d.body
	body["harness_surface_names"]=d.name.duplicate(true)
	body["provinces_count"]=int(d.provinces_count)
	var names: Array=[]
	for i: int in int(d.provinces_count): names.append({"ru":str(d.name.ru)+" · "+str(i+1),"en":str(d.name.en)+" · "+str(i+1)})
	body["provinces_names"]=names
	# Native generated provinces are cached and saved by Scouting, just like other mod bodies.
	var count: int=game.province_count(name)
	root.call("_разместить_тела")
	return {"ok":count==int(d.provinces_count),"body":name,"province_count":count,"code":"creation.surface_provinces_unverified" if count!=int(d.provinces_count) else ""}
