extends RefCounted
## Public live/catalogue space data. Searching never builds a star system.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")

static func available(game: Object, name: String) -> bool:
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
	if name == "space.rules": return rules(game,args,owner)
	if name == "navigation.enter_system": return enter(game,args)
	var query: String = str(args.get("query","")); var rows: Array = []
	var scope: String = str(args.get("scope","all")); var star_classes: Array = []
	if scope != "catalogue":
		for body_name: String in game.body_names():
			var body: Dictionary = game.body(body_name)
			if not body.get("open",false) or not matches(query,[body_name]): continue
			rows.append({"kind":"loaded_body","body":body_name,"body_kind":body.get("genus",""),"system":game.body_system(body_name),"discovered":true,"focus_tool":"navigation.focus"})
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
