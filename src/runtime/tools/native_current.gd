extends RefCounted
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const PersonRecord = preload("res://mods/pax_harness/src/runtime/tools/person_record.gd")
const METHODS := {"characters.list":"conversation","characters.read":"conversation","characters.connect":"conversation",
	"orders.read":"orders_panel","orders.submit":"order_evaluation","orders.cancel":"orders_panel","orders.update":"orders_panel",
	"research.read":"research","research.propose":"research","research.confirm":"research","research.cancel":"research",
	"laws.read":"law_making","laws.propose":"law_making","diplomacy.send":"letters","military.read":"army_map_view","military.order":"army_map_view","time.advance":"assistant_orders"}

static func available(game: RefCounted, name: String) -> bool:
	var main: Node = Sources.main_node(game)
	return main != null and METHODS.has(name) and main.has_method(METHODS[name])

static func execute(game: RefCounted, name: String, a: Dictionary) -> Dictionary:
	var main: Node = Sources.main_node(game)
	var model: Object = main.model
	match name:
		"characters.list":
			var contacts: Array = []
			for row: Dictionary in model.memory.list_("person"):
				contacts.append({"name":row.name,"header":PersonRecord.read(model.memory,str(row.name))})
			return Data.success({"contacts":contacts})
		"characters.read", "characters.connect":
			if not model.memory.exists("person",a.name): return Data.failed("tools.character_not_found")
			var header: Dictionary = PersonRecord.read(model.memory,a.name)
			if name == "characters.read": return Data.success({"name":a.name,"header":header,"selected_memory":model.memory.recall("person",a.name,"",400),"coverage":"retained_memory"})
			main.conversation().open("person",a.name,str(header.get("who","")))
			return Data.success({"conversation":main.player.talking_with,"reply_generated":false})
		"orders.read": return Data.success({"queue":Data.clean(model.orders),"deferred":Data.clean(main.order_evaluation().get("_deferred_orders"))})
		"orders.submit":
			if a.body not in game.colonies(): return Data.failed("tools.colony_not_found")
			var before: Array = Data.clean(model.orders)
			var accepted: bool = main.order_evaluation().charge(a.body,a.text)
			var created: Array = model.orders.filter(func(row: Dictionary): return not before.any(func(old: Dictionary): return old.id == row.id))
			return Data.success({"orders":created,"accepted":accepted,"completed":false},{},{},true) if accepted else Data.failed("tools.native_order_refused")
		"orders.cancel", "orders.update":
			var before: Dictionary = _row(model.orders,int(a.id)).duplicate(true)
			if before.is_empty(): return Data.failed("tools.order_not_found")
			if main.rewind_state.rewinding: return Data.failed("tools.time_jump_active")
			if name == "orders.cancel": main.orders_panel().cancel_order(int(a.id))
			else: main.orders_panel().edit_order(int(a.id),a.text)
			var after: Dictionary = _row(model.orders,int(a.id))
			var changed: bool = after.is_empty() if name == "orders.cancel" else after.get("text") == a.text.strip_edges()
			return Data.success({"order":after,"completed":false},before,after,name=="orders.update") if changed else Data.failed("tools.native_order_unchanged",before,after)
		"research.read": return Data.success(Data.clean(model.research_list))
		"research.propose":
			var accepted: bool = main.research().create(a.text)
			return Data.success({"accepted":accepted,"completed":false},{},{},true) if accepted else Data.failed("tools.native_research_refused")
		"research.confirm", "research.cancel":
			var before: Dictionary = _row(model.research_list,int(a.id)).duplicate(true)
			if before.is_empty(): return Data.failed("tools.research_not_found")
			if name == "research.confirm":
				if before.get("status") != "done_k_confirmation": return Data.failed("tools.research_not_pending_confirmation")
				main.research().confirm(int(a.id),float(a.stake))
			else: main.research().cancel(int(a.id))
			var after: Dictionary = _row(model.research_list,int(a.id))
			var changed: bool = after.get("status") == "under_way" if name == "research.confirm" else after.is_empty() or after.get("status") != before.get("status")
			return Data.success({"research":after,"completed":false},before,after,name=="research.confirm") if changed else Data.failed("tools.native_research_unchanged",before,after)
		"laws.read": return Data.success({"records":Data.clean(model.laws),"active_titles":game.laws()})
		"laws.propose":
			var accepted: bool = main.law_making().write_law(a.category,a.text,-1,bool(a.get("decree",false)))
			return Data.success({"accepted":accepted,"enacted":false},{},{},true) if accepted else Data.failed("tools.native_law_refused")
		"diplomacy.send":
			if a.country not in game.countries(): return Data.failed("tools.country_not_found")
			main.letters().write(a.country,a.text)
			return Data.success({"letter_submitted":true,"treaty_agreed":false},{},{},true)
		"military.read": return Data.success(Data.clean(model.armies.units))
		"military.order":
			var unit: Dictionary = _row(model.armies.units,int(a.unit_id))
			if unit.is_empty() or not bool(unit.get("ours",false)): return Data.failed("tools.unit_not_owned")
			main.army_map_view().order_unit(int(a.unit_id),a.text)
			return Data.success({"submitted":true,"arrived":false},{},{},true)
		"time.advance":
			if main.rewind_state.rewinding: return Data.failed("tools.time_jump_already_active")
			main.assistant_orders().rewind_from_ai(int(a.count),a.unit,false)
			return Data.success({"jump_active":main.rewind_state.rewinding,"future_effects_unknown":true},{},{},true)
	return Data.failed("tools.unknown_tool")

static func _row(rows: Array, id: int) -> Dictionary:
	for row: Dictionary in rows:
		if int(row.get("id",-1)) == id: return row
	return {}
