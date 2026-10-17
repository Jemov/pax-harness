extends RefCounted
## Reviewed stock-only fixed method bindings. Methods are never supplied by AI.
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const ORDER_FIELDS := ["id","текст","тело","день","статус","заявка","дней","прошло","место"]
const RESEARCH_FIELDS := ["id","что","статус","день","лет","шанс","нужно","даст","сэкономит","почему","ставка","готово_день"]
const LAW_FIELDS := ["id","текст","заголовок","раздел","статус","день","указом","отменён","инициатор"]
const UNIT_FIELDS := ["id","имя","чей","наш","провинция","куда","дивизий","статус","путь"]
const PersonRecord = preload("res://mods/pax_harness/src/runtime/tools/person_record.gd")
const PERSON_FIELDS := PersonRecord.FIELDS
const CATEGORIES := {"basics":"основы","rights":"права","economy":"хозяйство","order":"порядок","land":"земля","science":"наука","defence":"оборона"}
const UNITS := {"days":"дни","weeks":"недели","months":"месяцы","years":"годы","centuries":"века","millennia":"тысячелетия","million_years":"млн лет","billion_years":"млрд лет"}
const METHODS := {"characters.list":[],"characters.read":[],"characters.connect":["_открыть_разговор"],"orders.read":[],"orders.submit":["_зарядить"],"orders.cancel":["_отменить_приказ"],"orders.update":["_изменить_приказ"],
	"research.read":[],"research.propose":["_завести_разработку"],"research.confirm":["_подтвердить_разработку"],"research.cancel":["_отменить_разработку"],
	"laws.read":[],"laws.propose":["_написать_закон"],"diplomacy.send":["_написать_фракции"],
	"military.read":[],"military.order":["_приказ_отряду"],"time.advance":["_перемотка_от_ви"]}


static func available(game: RefCounted, name: String) -> bool:
	var main: Node = Sources.main_node(game)
	if main == null or not METHODS.has(name) or not METHODS[name].all(func(method: String): return main.has_method(method)): return false
	match name.get_slice(".",0):
		"characters":
			var memory: Variant = Data.property(main,"память")
			return is_instance_valid(memory) and memory.has_method("список") and memory.has_method("шапка") and memory.has_method("есть") and (name != "characters.read" or memory.has_method("вспомнить")) and (name != "characters.connect" or Data.property(main,"разговор_с") is Dictionary)
		"orders": return Data.property(main,"приказы") is Array
		"research": return Data.property(main,"разработки") is Array
		"laws": return Data.property(main,"законы") is Array
		"diplomacy": return Data.property(main,"фракции") is Array
		"military": return is_instance_valid(Data.property(main,"армии"))
		"time": return Data.property(main,"идёт_перемотка") is bool
	return false


static func execute(game: RefCounted, name: String, a: Dictionary) -> Dictionary:
	var main: Node = Sources.main_node(game)
	match name:
		"characters.list":
			var memory: Variant = Data.property(main,"память")
			var contacts: Array = []
			for row: Variant in memory.список("человек"):
				if row is Dictionary and row.get("вид") == "человек" and row.get("имя") is String and memory.есть("человек",row.имя):
					contacts.append({"name":row.имя,"header":PersonRecord.read(memory,row.имя)})
			return Data.success({"contacts":contacts,"coverage":"native_contact_index_and_retained_headers"},{},{"authoritative":true,"contacts":contacts})
		"characters.read", "characters.connect":
			var memory: Variant = Data.property(main,"память")
			if a.name != a.name.strip_edges() or not memory.есть("человек",a.name): return Data.failed("tools.character_not_found")
			var header: Dictionary = PersonRecord.read(memory,a.name)
			if name == "characters.read":
				return Data.success({"name":a.name,"header":header,"selected_memory":str(memory.вспомнить("человек",a.name,"",400)),"memory_authoritative":false,"coverage":"native_recall_selection_only"},{},{"authoritative":true,"header":header})
			var before: Dictionary = Data.fields(Data.property(main,"разговор_с"),["вид","имя","кто","тело"])
			main._открыть_разговор("человек",a.name,str(header.get("кто","")))
			var after: Dictionary = Data.fields(Data.property(main,"разговор_с"),["вид","имя","кто","тело"])
			return Data.success({"name":a.name,"created":false,"reply_generated":false},{"authoritative":true,"conversation":before},{"authoritative":true,"conversation":after}) if after.get("вид") == "человек" and after.get("имя") == a.name else Data.failed("tools.native_contact_not_opened",before,after)
		"orders.read": return Data.success({"queue":_orders(main),"deferred":Data.clean(Data.property(main,"_отложенные_приказы"))})
		"orders.submit":
			if a.body not in game.colonies(): return Data.failed("tools.colony_not_found")
			var before: Array = _orders(main)
			var deferred_before: Variant = Data.clean(Data.property(main,"_отложенные_приказы"))
			var accepted: bool = main._зарядить(a.body,a.text)
			var after: Array = _orders(main)
			var created: Array = after.filter(func(row: Dictionary): return not before.any(func(old: Dictionary): return old.get("id") == row.get("id")))
			var deferred: Variant = Data.property(main,"_отложенные_приказы")
			var delayed: bool = deferred is Array and deferred_before is Array and deferred.size() > deferred_before.size() and deferred.slice(deferred_before.size()).any(func(row: Variant): return row is Array and row.size() >= 2 and row[0] == a.body and row[1] == a.text.strip_edges())
			return Data.success({"orders":created,"deferred":delayed,"completed":false},{"authoritative":true,"queue":before},{"authoritative":true,"queue":after},true) if accepted and (not created.is_empty() or delayed) else Data.failed("tools.native_order_refused",{"queue":before},{"authoritative":true,"queue":after})
		"orders.cancel", "orders.update":
			var before: Dictionary = _row(_orders(main),int(a.id))
			if before.is_empty(): return Data.failed("tools.order_not_found")
			if name == "orders.update" and before.get("текст") == a.text.strip_edges():
				return Data.success({"order":before,"changed":false,"completed":false},{"authoritative":true,"order":before},{"authoritative":true,"order":before})
			if name == "orders.cancel": main._отменить_приказ(int(a.id))
			else: main._изменить_приказ(int(a.id),a.text)
			var after: Dictionary = _row(_orders(main),int(a.id))
			var applied: bool = after.is_empty() if name == "orders.cancel" else after.get("текст") == a.text.strip_edges()
			return Data.success({"order":after,"completed":false},{"authoritative":true,"order":before},{"authoritative":true,"order":after},name == "orders.update") if applied else Data.failed("tools.native_order_unchanged",before,after)
		"research.read": return Data.success(_research(main))
		"research.propose":
			var before: Array = _research(main)
			var accepted: bool = main._завести_разработку(a.text)
			var after: Array = _research(main)
			var created: Array = after.filter(func(row: Dictionary): return not before.any(func(old: Dictionary): return old.get("id") == row.get("id")))
			return Data.success({"proposals":created,"completed":false},{"authoritative":true,"research":before},{"authoritative":true,"research":after},true) if accepted and not created.is_empty() else Data.failed("tools.native_research_refused",before,after)
		"research.confirm", "research.cancel":
			var before: Dictionary = _row(_research(main),int(a.id))
			if before.is_empty(): return Data.failed("tools.research_not_found")
			if name == "research.confirm":
				if before.get("статус") != "готово_к_подтверждению": return Data.failed("tools.research_not_pending_confirmation",before)
				if game.home_body() not in game.colonies(): return Data.failed("tools.home_colony_not_found",before)
				if game.resources(game.home_body()).values().any(func(value: Variant): return not Data.number(value)): return Data.failed("tools.invalid_current_stock",before)
			if name == "research.confirm": main._подтвердить_разработку(int(a.id),float(a.stake))
			else: main._отменить_разработку(int(a.id))
			var after: Dictionary = _row(_research(main),int(a.id))
			var observed: Dictionary = {"authoritative":true,"research":after,"home_stock":Data.clean(game.resources(game.home_body()))}
			var applied: bool = after.get("статус") == "идёт" if name == "research.confirm" else (after.is_empty() or after.get("статус") != before.get("статус"))
			return Data.success({"research":after,"completed":false},{"authoritative":true,"research":before},observed,name == "research.confirm") if applied else Data.failed("tools.native_research_unchanged",before,observed)
		"laws.read": return Data.success({"records":_laws(main),"active_titles":Data.clean(game.laws())})
		"laws.propose":
			var before: Array = _laws(main)
			var accepted: bool = main._написать_закон(CATEGORIES[a.category],a.text,-1,bool(a.get("decree",false)))
			var after: Array = _laws(main)
			var created: Array = after.filter(func(row: Dictionary): return not before.any(func(old: Dictionary): return old.get("id") == row.get("id")))
			return Data.success({"proposals":created,"enacted":false},{"authoritative":true,"laws":before},{"authoritative":true,"laws":after},true) if accepted and not created.is_empty() else Data.failed("tools.native_law_refused",before,after)
		"diplomacy.send":
			if a.country not in game.countries(): return Data.failed("tools.country_not_found")
			var before: Array = _letters(main,a.country)
			main._написать_фракции(a.country,a.text)
			var after: Array = _letters(main,a.country)
			var submitted: bool = after.slice(before.size()).any(func(row: Dictionary): return row.get("от") == "мы" and row.get("текст") == a.text)
			return Data.success({"letter_submitted":true,"treaty_agreed":false},{"authoritative":true,"letters":before},{"authoritative":true,"letters":after},true) if submitted else Data.failed("tools.native_letter_not_sent",before,after)
		"military.read": return Data.success(_units(main))
		"military.order":
			var unit: Dictionary = _row(_units(main),int(a.unit_id))
			if unit.is_empty(): return Data.failed("tools.unit_not_found")
			if unit.get("чей") != game.country() or not bool(unit.get("наш",false)): return Data.failed("tools.unit_not_owned")
			var before: Array = _orders(main)
			main._приказ_отряду(int(a.unit_id),a.text)
			var after: Array = _orders(main)
			var created: Array = after.filter(func(row: Dictionary): return not before.any(func(old: Dictionary): return old.get("id") == row.get("id")))
			return Data.success({"orders":created,"arrived":false,"captured":false},{"authoritative":true,"unit":unit,"queue":before},{"authoritative":true,"queue":after},true) if not created.is_empty() else Data.failed("tools.native_unit_order_not_observed",before,after)
		"time.advance":
			var before: Dictionary = {"authoritative":true,"day":game.day(),"jump_active":Data.property(main,"идёт_перемотка")}
			if before.jump_active: return Data.failed("tools.time_jump_already_active",before,before)
			main._перемотка_от_ви(int(a.count),UNITS[a.unit],false)
			var after: Dictionary = {"authoritative":true,"day":game.day(),"jump_active":Data.property(main,"идёт_перемотка")}
			return Data.success({"requested":a,"future_effects_unknown":true},before,after,bool(after.jump_active)) if after.jump_active or after.day != before.day else Data.failed("tools.native_time_jump_not_started",before,after)
	return Data.failed("tools.unknown_tool")


static func _orders(main: Node) -> Array:
	return Data.rows(main,"приказы",ORDER_FIELDS)


static func _research(main: Node) -> Array:
	return Data.rows(main,"разработки",RESEARCH_FIELDS)


static func _laws(main: Node) -> Array:
	return Data.rows(main,"законы",LAW_FIELDS)


static func _units(main: Node) -> Array:
	return Data.rows(Data.property(main,"армии"),"отряды",UNIT_FIELDS)


static func _letters(main: Node, country: String) -> Array:
	var factions: Variant = Data.property(main,"фракции")
	if factions is Array:
		for row: Variant in factions:
			if row is Dictionary and row.get("имя") == country and row.get("переписка") is Array:
				return row.переписка.map(func(letter: Dictionary): return Data.fields(letter,["от","день","текст"]))
	return []


static func _row(rows: Array, id: int) -> Dictionary:
	for row: Dictionary in rows:
		if row.get("id") == id: return row
	return {}
