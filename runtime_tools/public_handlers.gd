extends RefCounted
const Sources = preload("res://mods/pax_harness/world_sources.gd")
const Retained = preload("res://mods/pax_harness/retained_current.gd")
const Data = preload("res://mods/pax_harness/runtime_tools/tool_data.gd")
const METHODS := {
	"world.read":["body_names","body"],"history.read":["body_names","body"],
	"resources.read":["resources","colonies"],"resources.add":["resources","colonies","add_resource"],
	"money.read":["money","resources","home_body","colonies"],"money.add":["money","add_money","resources","home_body","colonies"],
	"characters.exists":["has_character"],"characters.create":["has_character","add_character","body_names","body"],
	"bodies.read":["body_names","body","body_params"],"bodies.set_parameter":["body_names","body","body_params","set_body_param"],
	"provinces.read":["body_names","body","home_body","province_count","province"],
	"provinces.set_owner":["body_names","body","home_body","province_count","province","set_province_owner","factions"],
	"diplomacy.read":["countries","relation","at_war"],"diplomacy.change_relation":["countries","relation","change_relation"],
	"diplomacy.declare_war":["countries","at_war","declare_war"],"ships.read":["ships"],
	"ships.launch":["body_names","body","ships","launch_ship","resources"],
	"navigation.focus":["body_names","body","focus","focused_body"],"time.observe":["set_speed"]}
const PersonRecord = preload("res://mods/pax_harness/runtime_tools/person_record.gd")
const PERSON_KEYS := {"name":"name","role":"who","backstory":"lore","personality":"temperament","age":"age","occupation":"чем занят","wants":"dream"}
const MODELS := {"ark":"ковчег","station":"станция","satellite":"спутник","orbital":"орбиталка"}


static func available(game: RefCounted, name: String) -> bool:
	if not METHODS.has(name) or not METHODS[name].all(func(method: String): return game.has_method(method)): return false
	if name == "time.observe":
		var main: Node = Sources.main_node(game)
		return main.rewind_state.autoplay_on is bool and main.watch_speed is int
	return true


static func execute(game: RefCounted, name: String, a: Dictionary) -> Dictionary:
	if a.has("body") and not _known_body(game,a.body): return Data.failed("tools.unknown_or_hidden_body")
	match name:
		"world.read":
			var snapshot: Dictionary = Sources.collect(game,Sources.native_loaded_maps(game))
			if not snapshot.ok: return Data.failed("tools.world_source_unavailable")
			var view: Dictionary = Sources.tool_view(snapshot.world,a)
			return Data.success(view,{}, {"authoritative":true,"world":view})
		"history.read":
			var snapshot: Dictionary = Retained.collect(game)
			if not snapshot.ok: return Data.failed("tools.history_source_unavailable")
			var view: Dictionary = Retained.page(snapshot.campaign_context.history,a)
			return Data.success(view,{}, {"authoritative":false,"history":view})
		"resources.read", "resources.add":
			if a.body not in game.colonies(): return Data.failed("tools.colony_not_found")
			var raw: Dictionary = _stock(game,a.body)
			if raw.values().any(func(value: Variant): return not Data.number(value)): return Data.failed("tools.invalid_current_stock")
			var before: Dictionary = Data.clean(_stock(game,a.body))
			var goods: Array = registered_goods(game)
			if name == "resources.read": return Data.success({"body":a.body,"stocks":before,"registered_goods":goods,"electricity_semantics":"stock_value_not_persistent_generation"},{},{"authoritative":true,"body":a.body,"stocks":before})
			if a.resource not in goods: return Data.failed("tools.unregistered_resource",before)
			var old: float = float(before.get(a.resource,0.0))
			game.add_resource(a.body,a.resource,float(a.amount))
			var raw_after: Dictionary = _stock(game,a.body)
			if not Data.number(raw_after.get(a.resource)): return Data.failed("tools.invalid_native_stock_readback",before)
			var after: Dictionary = Data.clean(raw_after)
			return Data.success({"requested_delta":a.amount,"applied_delta":float(after.get(a.resource,0.0))-old,"resource":a.resource,"persistent_production_changed":false},
				{"authoritative":true,"body":a.body,"stocks":before},{"authoritative":true,"body":a.body,"stocks":after})
		"money.read":
			if game.home_body() not in game.colonies(): return Data.failed("tools.home_colony_not_found")
			if not Data.number(game.resources(game.home_body()).get("деньги",0.0)) or not Data.number(game.money()): return Data.failed("tools.invalid_current_money")
			return Data.success({"amount":game.money()},{},{"authoritative":true,"money":game.money()})
		"money.add":
			if not game.has_method("home_body") or not game.has_method("colonies") or game.home_body() not in game.colonies(): return Data.failed("tools.home_colony_not_found")
			if not Data.number(game.resources(game.home_body()).get("деньги",0.0)) or not Data.number(game.money()): return Data.failed("tools.invalid_current_money")
			var before: float = game.money()
			game.add_money(float(a.amount))
			var after: float = game.money()
			if not is_finite(after): return Data.failed("tools.invalid_native_money_readback",{"money":before})
			return Data.success({"requested_delta":a.amount,"applied_delta":after-before},{"authoritative":true,"money":before},{"authoritative":true,"money":after})
		"characters.exists":
			return Data.success({"name":a.name,"exists":game.has_character(a.name)})
		"characters.create":
			if a.info.name != a.info.name.strip_edges() or a.info.name.strip_edges().is_empty(): return Data.failed("tools.invalid_character_name")
			if game.has_character(a.info.name): return Data.failed("tools.character_already_exists",{"exists":true,"name":a.info.name})
			var info: Dictionary = {}
			for key: String in a.info: info[PERSON_KEYS[key]] = a.info[key]
			var created: bool = game.add_character(a.body,info,"",false)
			var exists: bool = game.has_character(a.info.name)
			var header: Dictionary = {}
			var memory: Variant = Sources.main_node(game).model.memory
			if is_instance_valid(memory) and memory.has_method("header"):
				header = PersonRecord.read(memory,a.info.name)
			if not created or not exists: return Data.failed("tools.native_character_refused",{"exists":false},{"authoritative":true,"exists":exists})
			var mismatched: Array = []
			for key: String in info:
				var expected: Variant = str(int(info[key])) if key == "age" else str(info[key]).strip_edges() if key == "lore" else info[key]
				if not header.has(key) or str(header[key]) != str(expected): mismatched.append(key)
			var result: Dictionary = {"created":true,"name":a.info.name,"submitted_info":info,"verified_header_fields":header.keys(),"unverified_or_changed_fields":mismatched,"contact_visibility":"native_contacts_require_conversation","conversation_opened":false}
			var observed: Dictionary = {"authoritative":true,"exists":exists,"header":header}
			if not mismatched.is_empty(): return {"ok":false,"code":"tools.character_attributes_not_preserved","before":{"exists":false},"after":observed,"result":result}
			return Data.success(result,{"authoritative":true,"exists":false},observed)
		"bodies.read":
			return Data.success(Data.fields(game.body(a.body),Sources.BODY_FIELDS.keys()+["parameters"]),{}, {"authoritative":true,"parameters":Data.clean(game.body_params(a.body))})
		"bodies.set_parameter":
			var before: Dictionary = Data.clean(game.body_params(a.body))
			game.set_body_param(a.body,a.parameter,float(a.value))
			var after: Dictionary = Data.clean(game.body_params(a.body))
			return Data.success({"body":a.body,"parameter":a.parameter,"requested":a.value},{"authoritative":true,"parameters":before},{"authoritative":true,"parameters":after}) if after.get(a.parameter) == a.value else Data.failed("tools.native_parameter_unchanged",before,after)
		"provinces.read", "provinces.set_owner":
			if not _loaded_map(game,a.body): return Data.failed("tools.map_not_loaded")
			var count: int = game.province_count(a.body)
			if int(a.id) > count: return Data.failed("tools.province_not_found")
			var before: Dictionary = Data.clean(game.province(a.body,int(a.id)))
			if before.is_empty(): return Data.failed("tools.province_not_found")
			if name == "provinces.read": return Data.success(before,{}, {"authoritative":true,"province":before})
			if a.owner != "" and not game.factions().any(func(row: Dictionary): return row.get("name") == a.owner): return Data.failed("tools.country_not_found",before)
			game.set_province_owner(a.body,int(a.id),a.owner)
			var after: Dictionary = Data.clean(game.province(a.body,int(a.id)))
			return Data.success(after,{"authoritative":true,"province":before},{"authoritative":true,"province":after}) if after.get("owner") == a.owner else Data.failed("tools.native_owner_unchanged",before,after)
		"diplomacy.read", "diplomacy.change_relation", "diplomacy.declare_war":
			if a.country not in game.countries(): return Data.failed("tools.country_not_found")
			if name != "diplomacy.declare_war" and (not Data.number(game.relation(a.country)) or game.relation(a.country) < 0 or game.relation(a.country) > 1): return Data.failed("tools.invalid_current_relation")
			if name == "diplomacy.read": return Data.success({"country":a.country,"relation":game.relation(a.country),"at_war":game.at_war(a.country)})
			if name == "diplomacy.change_relation":
				var before: float = game.relation(a.country)
				game.change_relation(a.country,float(a.delta))
				var after: float = game.relation(a.country)
				return Data.success({"requested_delta":a.delta,"applied_delta":after-before},{"authoritative":true,"relation":before},{"authoritative":true,"relation":after}) if after >= 0 else Data.failed("tools.native_relation_refused")
			var before: bool = game.at_war(a.country)
			game.declare_war(a.country)
			var after: bool = game.at_war(a.country)
			return Data.success({"country":a.country},{"authoritative":true,"at_war":before},{"authoritative":true,"at_war":after}) if after else Data.failed("tools.native_war_refused",{"at_war":before},{"authoritative":true,"at_war":after})
		"ships.read":
			return Data.success(Data.clean(game.ships()))
		"ships.launch":
			if not _known_body(game,a.from_body) or not _known_body(game,a.to_body): return Data.failed("tools.unknown_or_hidden_body")
			if float(a.people) > 0 and a.from_body not in game.colonies(): return Data.failed("tools.passenger_source_colony_not_found")
			if _stock(game,a.from_body).values().any(func(value: Variant): return not Data.number(value)): return Data.failed("tools.invalid_current_stock")
			var before: Dictionary = Data.clean(_stock(game,a.from_body))
			var launched: Dictionary = game.launch_ship(a.from_body,a.to_body,float(a.speed_c),float(a.people),{},MODELS[a.model],"")
			var after: Dictionary = Data.clean(_stock(game,a.from_body))
			if launched.is_empty(): return Data.failed("tools.native_launch_refused",before,after)
			var present: bool = game.ships().any(func(row: Dictionary): return row.get("id") == launched.get("id"))
			return Data.success({"ship":Data.clean(launched),"requested_people":a.people,"arrived":false},
				{"authoritative":true,"source_stock":before},{"authoritative":true,"source_stock":after,"in_flight":present},true) if present else Data.failed("tools.flight_not_observed",before,after)
		"navigation.focus":
			var before: String = game.focused_body()
			game.focus(a.body,true)
			var after: String = game.focused_body()
			return Data.success({"physical_travel":false},{"focused_body":before},{"authoritative":true,"focused_body":after}) if after == a.body else Data.failed("tools.native_focus_refused")
		"time.observe":
			var main: Node = Sources.main_node(game)
			var before: int = int(main.watch_speed) if bool(main.rewind_state.autoplay_on) else 0
			game.set_speed(int(a.speed))
			var after: int = int(main.watch_speed) if bool(main.rewind_state.autoplay_on) else 0
			return Data.success({"requested_speed":a.speed},{"authoritative":true,"speed":before},{"authoritative":true,"speed":after}) if after == int(a.speed) else Data.failed("tools.native_speed_unchanged",{"speed":before},{"authoritative":true,"speed":after})
	return Data.failed("tools.unknown_tool")


static func registered_goods(game: RefCounted) -> Array:
	var goods: Array = []
	for body: String in game.colonies():
		for key: Variant in game.resources(body):
			if key is String and key not in goods: goods.append(key)
	var main: Node = Sources.main_node(game)
	var resources: Variant = main.model.resources
	if is_instance_valid(resources) and resources.has_method("all_kinds"):
		for key: Variant in resources.all_kinds():
			if key is String and key not in goods: goods.append(key)
	var economy: Variant = main.econ
	var registered: Variant = Data.property(economy,"goods")
	if registered is Dictionary:
		for key: Variant in registered:
			if key is String and key not in goods: goods.append(key)
	goods.sort()
	return goods


static func _known_body(game: RefCounted, body: String) -> bool:
	return game.has_method("body_names") and game.has_method("body") and body in game.body_names() and bool(game.body(body).get("open",false))


static func _loaded_map(game: RefCounted, body: String) -> bool:
	if body == game.home_body(): return is_instance_valid(Sources.main_node(game).model.earth_provinces)
	return body in Sources.native_loaded_maps(game)


static func _stock(game: RefCounted, body: String) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in game.resources(body):
		var value: Variant = game.resources(body)[key]
		if key is String and Data.number(value): result[key] = value
	return result
