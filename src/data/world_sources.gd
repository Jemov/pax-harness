extends RefCounted
## Detached instant sources from the existing public game facade. No AI/dispatch.
## Non-home province reads require an already-loaded map guard supplied by the
## isolated native adapter: the public province API otherwise loads/generates it.

const BODY_FIELDS := {"name":"name", "genus":"kind", "r_km":"radius_km", "a_km":"orbit_km", "description":"description", "open":"discovered"}
const FACTION_FIELDS := ["name", "type", "ours", "capital", "description", "relations", "treaty", "alive"]
const PARAMETERS := ["temperature", "water", "biomass", "radiation", "atmosphere", "urban", "magnetic"]
const CATALOGUE := [
	["player", "player", "player", "The player's current faction, home, camera focus and laws. Camera focus is not physical location."],
	["countries", "countries", "world", "Current faction records from the game, including the player's own faction."],
	["bodies", "bodies", "space", "Discovered bodies currently loaded in this world. Hidden and unbuilt bodies are excluded."],
	["provinces", "provinces", "territories", "All provinces of discovered bodies whose maps were already loaded. Preview never generates a map."],
	["resources", "resources", "world", "Actual current stocks by colony body and canonical resource name. Reports are not a stock source."],
	["systems", "systems", "space", "Loaded systems containing a discovered body, with positions in light years."],
	["discovered_bodies", "discovered_bodies", "space", "Discovered body names; discovery does not establish that the player visited them."],
	["colonized_bodies", "colonized_bodies", "space", "Body names with a current resource stock entry; not a travel history."],
	["charted_stars", "charted_stars", "space", "Canonical keys of built/charted systems, not physical visits."],
	["visited_bodies", "visited_bodies", "space", "An exact player visit history is not exposed by this version's public facade."]
]
const ROW_FIELDS := {
	"player":{"country":"string", "home_body":"string", "focused_body":"string", "faction":"object", "laws":"array", "government_form":"string"},
	"countries":{"name":"string", "type":"string", "ours":"boolean", "capital":"string", "description":"string", "relations":"number", "treaty":"string", "alive":"boolean"},
	"bodies":{"name":"string", "kind":"string", "radius_km":"number", "orbit_km":"number", "description":"string", "discovered":"boolean", "parameters":"object", "system":"string"},
	"provinces":{"id":"integer", "body":"string", "name":"string", "owner":"string", "area_km2":"number", "coastal":"boolean", "neighbours":"array", "direction":"object"},
	"systems":{"name":"string", "star":"string", "position_ly":"object", "mass":"number", "description":"string"}
}


static func collect(game: Object, loaded_maps: Array = []) -> Dictionary:
	if not active(game):
		return {"ok":false, "world":{}, "diagnostics":[{"code":"world_sources.inactive"}]}
	var world: Dictionary = {"authoritative":true, "completeness":"public_current_visible_sources", "sources":{}}
	var diagnostics: Array = []
	for method: String in ["day", "date"]:
		if game.has_method(method):
			world["elapsed_day" if method == "day" else "date"] = _json(game.call(method))
	var home: String = str(game.home_body()) if game.has_method("home_body") else ""
	var player: Dictionary = {}
	for method: String in ["country", "home_body", "focused_body", "government_form"]:
		if game.has_method(method):
			player[method] = str(game.call(method))
	if game.has_method("player_faction"):
		player["faction"] = _fields(game.player_faction(), FACTION_FIELDS)
	if game.has_method("laws"):
		player["laws"] = _json(game.laws())
	world["player"] = player
	world.sources["player"] = _source(not player.is_empty(), "public_player_state", ["country", "home_body", "focused_body", "player_faction", "laws", "government_form"])

	if game.has_method("factions"):
		var countries: Array = []
		for faction: Variant in game.factions():
			if faction is Dictionary:
				countries.append(_fields(faction, FACTION_FIELDS))
		world["countries"] = countries
	world.sources["countries"] = _source(world.has("countries"), "public_faction_records", ["factions"])

	var visible: Array = []
	var body_records: Array = []
	var system_names: Array = []
	if game.has_method("body_names") and game.has_method("body"):
		for name: String in game.body_names():
			var body: Dictionary = game.body(name)
			if not bool(body.get("open", false)):
				continue
			visible.append(name)
			var row: Dictionary = {}
			for key: String in BODY_FIELDS:
				if body.has(key):
					row[BODY_FIELDS[key]] = _json(body[key])
			# The lookup key is canonical even if an optional record field is absent.
			row["name"] = name
			var params: Dictionary = body.get("parameters", {}) if body.get("parameters") is Dictionary else {}
			row["parameters"] = _fields(params, PARAMETERS)
			if game.has_method("body_system"):
				row["system"] = str(game.body_system(name))
				if row.system not in system_names:
					system_names.append(row.system)
			body_records.append(row)
		world["bodies"] = body_records
		world["discovered_bodies"] = visible.duplicate()
	world.sources["bodies"] = _source(world.has("bodies"), "discovered_loaded_bodies", ["body_names", "body"])
	world.sources["discovered_bodies"] = world.sources.bodies.duplicate(true)
	if game.has_method("systems") and world.has("bodies"):
		var systems: Array = []
		for system: Dictionary in game.systems():
			if system.get("name") in system_names:
				systems.append(_fields(system, ["name", "star", "position_ly", "mass", "description"]))
		world["systems"] = systems
	world.sources["systems"] = _source(world.has("systems"), "systems_of_discovered_bodies", ["systems", "body_system"])

	if game.has_method("colonies") and game.has_method("resources"):
		var resources: Dictionary = {}
		var colonies: Array = []
		for name: String in game.colonies():
			# A public colony record can exist before a discovered body list is ready.
			colonies.append(name)
			var stock: Dictionary = game.resources(name)
			var amounts: Dictionary = {}
			for key: Variant in stock:
				if key is String and (stock[key] is int or stock[key] is float) and is_finite(float(stock[key])):
					amounts[key] = stock[key]
				elif not stock[key] is Dictionary:
					diagnostics.append({"code":"world_sources.resource_type", "body":name, "resource":str(key)})
			resources[name] = amounts
		world["resources"] = resources
		world["colonized_bodies"] = colonies
	world.sources["resources"] = _source(world.has("resources"), "public_colony_stocks", ["colonies", "resources"])
	world.sources["colonized_bodies"] = world.sources.resources.duplicate(true)
	if game.has_method("charted_stars"):
		world["charted_stars"] = _json(game.charted_stars())
	world.sources["charted_stars"] = _source(world.has("charted_stars"), "built_system_keys", ["charted_stars"])

	if world.has("bodies") and game.has_method("province_count") and game.has_method("province"):
		var provinces: Array = []
		var read_maps: Array = []
		var unloaded: Array = []
		for name: String in visible:
			if name != home and name not in loaded_maps:
				unloaded.append(name)
				continue
			read_maps.append(name)
			var count: int = int(game.province_count(name))
			if count < 0 or count > 250000:
				diagnostics.append({"code":"world_sources.province_count", "body":name})
				continue
			for id: int in range(1, count + 1):
				var row: Dictionary = _fields(game.province(name, id), ["id", "name", "owner", "area_km2", "coastal", "neighbours", "direction"])
				if not row.is_empty():
					row["body"] = name
					provinces.append(row)
		world["provinces"] = provinces
		world.sources["provinces"] = _source(true, "already_loaded_maps_of_discovered_bodies", ["province_count", "province"])
		world.sources.provinces["loaded_bodies"] = read_maps
		world.sources.provinces["unloaded_bodies"] = unloaded
	else:
		world.sources["provinces"] = _source(false, "unavailable", ["province_count", "province"])
	world.sources["visited_bodies"] = _source(false, "unsupported_exact_visit_history", [])
	return {"ok":diagnostics.is_empty(), "world":world, "diagnostics":diagnostics}


# Tool calls get an overview by default; province details are explicitly paged.
# The editor's complete detached snapshot remains available through collect().
static func tool_view(world: Dictionary, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = world.duplicate(true)
	var provinces: Array = result.get("provinces",[])
	var body: String = str(options.get("body",""))
	var owner: String = str(options.get("owner",""))
	if body != "": provinces = provinces.filter(func(row: Dictionary): return row.get("body") == body)
	if owner != "": provinces = provinces.filter(func(row: Dictionary): return row.get("owner") == owner)
	var total: int = provinces.size()
	var offset: int = maxi(0,int(options.get("offset",0)))
	var limit: int = clampi(int(options.get("limit",0)),0,200)
	result.provinces = provinces.slice(offset,offset+limit)
	result["province_page"] = {"total":total,"returned":result.provinces.size(),"offset":offset,"limit":limit,
		"body":body,"owner":owner,"has_more":offset+result.provinces.size()<total,
		"next_offset":offset+result.provinces.size(),"note":"Overview omits province details by default. Set limit 1..200 and optional body/owner filters; use next_offset for more."}
	return result


static func native_loaded_maps(game: Object) -> Array:
	# Version-dependent read-only guard over the documented UNSTABLE main handle.
	# No call to _пров_тела: that method may generate/cache a new map.
	if not active(game):
		return []
	var main: Node = main_node(game)
	if main == null:
		return []
	var providers: Variant = main.get("body_provinces")
	if not providers is Dictionary:
		var scouting: Variant=main.call("scouting") if main.has_method("scouting") else null
		if scouting is Object and is_instance_valid(scouting): providers=scouting.get("body_provinces_cache")
	var names: Array = []
	if providers is Dictionary:
		for name: Variant in providers:
			if name is String and is_instance_valid(providers[name]) and providers[name] is Object:
				names.append(name)
	return names


static func main_node(game: Object) -> Node:
	# Official PaxGame documents main as a version-dependent raw handle. Its
	# stock facade has no is_active method; inspect that existing node only.
	if not is_instance_valid(game):
		return null
	if not game.get_property_list().any(func(property: Dictionary): return property.name == "main"):
		return null
	var node: Variant = game.get("main")
	if not is_instance_valid(node):
		return null
	return node if node is Node and not node.is_queued_for_deletion() else null


static func active(game: Object) -> bool:
	if not is_instance_valid(game):
		return false
	if game.has_method("is_active"):
		return bool(game.is_active())
	return main_node(game) != null


static func catalogue(world: Dictionary = {}, example_only: bool = false) -> Array:
	var rows: Array = []
	for item: Array in CATALOGUE:
		var source: Dictionary = world.get("sources", {}).get(item[1], {})
		var fields: Array = []
		for field: String in ROW_FIELDS.get(item[1], {}):
			fields.append({"path":[field], "type":ROW_FIELDS[item[1]][field], "description":"Public record field; inspect presence before use when this source is empty or incomplete."})
		rows.append({"id":"context.world." + item[0], "path":["context", "world", item[1]], "fields":fields,
			"category":item[2], "description":item[3], "available":world.has(item[1]),
			"coverage":source.get("coverage", "unavailable"), "provenance":source.duplicate(true),
			"example_only":example_only})
	return rows


static func _source(available: bool, coverage: String, api: Array) -> Dictionary:
	return {"available":available, "coverage":coverage, "api":api.duplicate(), "authoritative":true, "read_only":true}


static func _fields(source: Dictionary, keys: Array) -> Dictionary:
	var result: Dictionary = {}
	for key: String in keys:
		if source.has(key):
			result[key] = _json(source[key])
	return result


static func _json(value: Variant, depth: int = 0) -> Variant:
	if depth > 16:
		return null
	if value is Vector3:
		return {"x":value.x, "y":value.y, "z":value.z} if value.is_finite() else null
	if value == null or value is String or value is bool or value is int:
		return value
	if value is float:
		return value if is_finite(value) else null
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			if key is String:
				result[key] = _json(value[key], depth + 1)
		return result
	if value is Array or value is PackedStringArray or value is PackedInt32Array or value is PackedInt64Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_json(item, depth + 1))
		return result
	return null
