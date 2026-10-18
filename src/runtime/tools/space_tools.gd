extends RefCounted
## Public live/catalogue space data. Searching never builds a star system.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")

static func available(game: Object, name: String) -> bool:
	if name in ["space.surface","navigation.open_surface"]: return is_instance_valid(game) and game.has_method("body_names") and game.has_method("body") and game.has_method("scene_root")
	var methods: Array = ["body_names","body","body_system","galaxies","galaxy","charted_stars"]
	if name == "navigation.enter_system": methods += ["chart_star","enter_star","charted_stars","system_bodies","focused_body","secrets_found"]
	return is_instance_valid(game) and methods.all(func(method: String): return game.has_method(method))

static func normalized(text: String) -> String:
	var ru := "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
	var latin: Array = ["a","b","v","g","d","e","e","zh","z","i","i","k","l","m","n","o","p","r","s","t","u","f","h","ts","ch","sh","sch","","y","","e","yu","ya"]
	var result := ""
	for c: String in text.to_lower():
		var at: int = ru.find(c)
		if at >= 0: result += latin[at]
		elif c >= "a" and c <= "z" or c >= "0" and c <= "9": result += c
	return result

static func matches(query: String, names: Array, allow_suffix: bool = false) -> bool:
	if query == "": return true
	var needle: String = normalized(query)
	if needle == "": return false
	for name: Variant in names:
		var candidate: String = normalized(str(name))
		if candidate.contains(needle): return true
		# A request for a not-yet-built planet may append a letter to its star.
		if allow_suffix and candidate.length() > 3 and needle.begins_with(candidate) and needle.length()-candidate.length() <= 2: return true
	return false

static func execute(game: RefCounted, name: String, args: Dictionary, owner: Node) -> Dictionary:
	if not available(game,name): return Data.failed("space.public_api_unavailable")
	if name in ["space.surface","navigation.open_surface"]: return surface(game,args,name=="navigation.open_surface")
	if name == "space.rules": return rules(game,args,owner)
	if name == "navigation.enter_system": return enter(game,args)
	var query: String = str(args.get("query","")); var rows: Array = []
	var scope: String = str(args.get("scope","all")); var star_classes: Array = []
	if scope != "catalogue":
		for body_name: String in game.body_names():
			var body: Dictionary = game.body(body_name)
			var aliases: Array=[body_name,str(body.get("harness_surface_parent",""))]
			if body.get("harness_surface_names") is Dictionary: aliases.append_array(body.harness_surface_names.values())
			if not body.get("open",false) or not matches(query,aliases): continue
			rows.append({"kind":"loaded_body","body":body_name,"body_kind":body.get("genus",""),"system":game.body_system(body_name),"discovered":true,"focus_tool":"navigation.focus","names":body.get("harness_surface_names",{}),"artificial_parent":body.get("harness_surface_parent","")})
	var galaxies: Array = Array(game.galaxies())
	var galaxy_key: String = str(args.get("galaxy",galaxies[0] if not galaxies.is_empty() else ""))
	if galaxy_key != "" and galaxy_key not in galaxies: return Data.failed("space.unknown_galaxy")
	if scope != "loaded" and galaxy_key != "":
		var catalogue: Dictionary = game.galaxy(galaxy_key)
		var stars: Array = catalogue.get("stars",[])
		if stars.size() > 100000: return Data.failed("space.catalogue_scan_budget")
		for star: Dictionary in stars:
			if str(star.get("class","")) not in star_classes: star_classes.append(str(star.get("class","")))
			var names: Variant = star.get("name",{})
			var aliases: Array = names.values() if names is Dictionary else [str(names)]
			aliases.append(str(star.get("system","")))
			if not matches(query,aliases+[str(star.get("class",""))],true): continue
			var key: String = galaxy_key+":"+str(star.get("id",""))
			rows.append({"kind":"catalogue_star","star_key":key,"names":Data.clean(names),"class":str(star.get("class","")),"system":str(star.get("system","")),"distance_reference_ly":star.get("sv_years"),"charted":key in game.charted_stars(),"enter_tool":"navigation.enter_system","note":"Catalogue entry only. Planet names/parameters are known only after the native system is built; a suffix match is not proof that such a planet exists."})
	var offset: int = int(args.get("offset",0)); var limit: int = int(args.get("limit",20))
	var selected: Array = rows.slice(offset,offset+limit)
	return Data.success({"rows":selected,"total":rows.size(),"next_offset":offset+selected.size(),"has_more":offset+selected.size()<rows.size(),"galaxy":galaxy_key,"available_galaxies":galaxies,"available_star_classes":star_classes,"source":"Public loaded-body and deterministic galaxy catalogues of the current game, including installed mod content. No system generated or time advanced."})

static func surface(game: RefCounted, args: Dictionary, open_map: bool) -> Dictionary:
	var name: String=str(args.body)
	if name not in game.body_names() or not game.body(name).get("open",false): return Data.failed("tools.unknown_or_hidden_body")
	var original: String=name
	var shells: Array=[]
	for key: String in game.body_names():
		var candidate: Dictionary=game.body(key)
		if candidate.get("harness_surface_parent")==name: shells.append({"body":key,"name":candidate.get("harness_surface_names",{}),"solid_surface":true})
	if not shells.is_empty(): name=str(shells[0].body)
	var kind: String=str(game.body(name).get("genus",""))
	var solid: bool=kind not in ["star","gas","black_hole","white_dwarf","neutron"]
	if open_map and not solid: return Data.failed("space.no_solid_surface",{"body":name,"artificial_surface_project":"creation.propose kind=surface, only on explicit player request and after player Apply"})
	if open_map:
		var root: Node=game.scene_root()
		if not root.has_method("galaxy_view"): return Data.failed("space.map_navigation_unavailable")
		root.galaxy_view().open_body_map(Array(game.body_names()).find(name))
	var loaded: bool=name==game.home_body() or name in Sources.native_loaded_maps(game)
	return Data.success({"body":name,"requested_body":original,"original_kind":game.body(original).get("genus",""),"kind":kind,"solid_surface":solid,"artificial_surfaces":shells,"artificial_parent":game.body(name).get("harness_surface_parent",""),"map_loaded":loaded,"province_count":game.province_count(name) if loaded and solid else null,"map_open_requested":open_map,"surface_tool":"charts.map","load_chart_tools":{"groups":["maps"]},"map_arguments":{"body":name},"water_supported":solid and loaded,"note":"Natural solid bodies and approved artificial rock shells have native province maps. Original stars/gas giants retain their kinds. Opening a parent with an approved shell opens that shell. No colonization or population is granted. Use the returned body ID in charts.map; include_water=true supports water coverage after map_loaded=true."})

static func enter(game: RefCounted, args: Dictionary) -> Dictionary:
	var key: String = str(args.get("star_key","")); var parts: PackedStringArray = key.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or parts[0] not in game.galaxies(): return Data.failed("space.invalid_star_key")
	var found := false
	for star: Dictionary in game.galaxy(parts[0]).get("stars",[]):
		if str(star.get("id","")) == parts[1]: found = true; break
	if not found: return Data.failed("space.star_not_found")
	var before: Dictionary = {"focused_body":game.focused_body(),"charted":key in game.charted_stars(),"day":game.day(),"secrets":Data.clean(game.secrets_found())}
	var system: String = game.chart_star(key)
	if system == "": return Data.failed("space.native_chart_refused",before)
	game.enter_star(key)
	var members: Array = []
	for body: String in game.system_bodies(system):
		members.append({"body":body,"discovered":bool(game.body(body).get("open",false)),"kind":str(game.body(body).get("genus",""))})
	var after: Dictionary = {"focused_body":game.focused_body(),"charted":key in game.charted_stars(),"day":game.day(),"secrets":Data.clean(game.secrets_found())}
	if not after.charted: return Data.failed("space.native_chart_unverified",before,after)
	var stellar_count: int = members.filter(func(row: Dictionary): return row.kind in ["star","black_hole","white_dwarf","neutron"]).size()
	return Data.success({"system":system,"star_key":key,"members":members,"member_count":members.size(),"stellar_body_count":stellar_count,"nonstellar_body_count":members.size()-stellar_count,"members_semantics":"Includes the central star and any moons; member_count is NOT a planet count. Classify actual kinds before describing the system.","system_generated":not before.charted,"physical_travel":false,"time_advanced":after.day != before.day,"note":"Native system entry/camera action. It may reveal the game's own system secret. No ship launched and no colony founded. Select an actually returned discovered member with navigation.focus; never invent a planet suffix."},before,after)

static func rules(game: RefCounted, args: Dictionary, owner: Node) -> Dictionary:
	var api: Node = owner.get_node_or_null("/root/Pax") if owner != null else null
	if api == null: return Data.failed("space.public_api_unavailable")
	var section: String = str(args.get("section","megastructures"))
	if section not in ["megastructures","terraforming","supply_methods","roles"]: return Data.failed("space.unknown_rule_section")
	var data: Dictionary = api.json("res://data/"+section+".json")
	var classes: Variant = data.get("roles",{}) if section == "roles" else data.get("classes",{})
	var rows: Array = []
	if classes is Dictionary:
		for key: Variant in classes: rows.append({"id":str(key),"definition":Data.clean(classes[key])})
	elif classes is Array:
		for row: Variant in classes: rows.append(Data.clean(row))
	var offset: int = int(args.get("offset",0)); var limit: int = int(args.get("limit",10))
	var result: Dictionary = {"section":section,"rows":rows.slice(offset,offset+limit),"total":rows.size(),"has_more":offset+limit<rows.size(),"next_offset":mini(rows.size(),offset+limit),"source":"Current merged game/mod data/"+section+".json","note":"Configured construction/research categories and requirements, not a promise of affordability, feasibility on any body or a completed project. Check the body's actual kind and scenario technology/resources; use native orders/research assessment for a concrete proposal. No construction or research submitted."}
	if args.has("body"):
		var body: String = str(args.body)
		if body not in game.body_names() or not game.body(body).get("open",false): return Data.failed("tools.unknown_or_hidden_body")
		result["body"] = Data.fields(game.body(body),["name","genus","description","parameters"])
		result["body_specific_rules"] = Data.clean(data.get("bodies",{}).get(body,{}))
	if JSON.stringify(result).to_utf8_buffer().size() > 65536: return Data.failed("space.rules_page_too_large")
	return Data.success(result)
