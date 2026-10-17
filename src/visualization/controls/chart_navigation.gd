extends RefCounted

static func resolve(game: Object, region: Dictionary) -> Dictionary:
	if not is_instance_valid(game): return {}
	var body: String = str(region.get("body",""))
	if body.is_empty(): body = game.home_body() # Legacy saved maps.
	if body != game.home_body(): return {}
	var identity: String = str(region.get("id",""))
	if not identity.is_valid_int(): return {}
	var id: int = int(identity)
	if id <= 0 or id > game.province_count(body): return {}
	var current: Dictionary = game.province(body,id)
	if current.is_empty() or str(current.get("name","")) != str(region.get("label","")): return {}
	return {"id":id,"body":body,"label":str(current.name)}
