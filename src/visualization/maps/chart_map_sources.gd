extends RefCounted
## Explicit installed-mod map adapters. No map generation or guessed geometry.
const Chart = preload("res://mods/pax_harness/src/visualization/specs/chat_chart.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
var sources: Dictionary = {}
func unregister_source(id: String, reader: Callable) -> bool:
	if not sources.has(id) or sources[id].reader != reader: return false
	sources.erase(id); return true
func register_source(id: String, title: String, body: String, reader: Callable) -> bool:
	if sources.has(id) and not sources[id].reader.is_valid(): sources.erase(id)
	if sources.size() >= 32 or sources.has(id) or RegEx.create_from_string("^[a-z0-9_]+\\.[a-z0-9_.-]{1,70}$").search(id) == null: return false
	if title.is_empty() or title.length() > 160 or body.is_empty() or body.length() > 160 or not reader.is_valid(): return false
	sources[id] = {"id":id,"title":title,"body":body,"reader":reader}
	return true
func describe(game: Object = null) -> Dictionary:
	var rows: Array = []
	for row: Dictionary in sources.values():
		if row.reader.is_valid(): rows.append({"id":row.id,"title":row.title,"body":row.body})
	var native: Array=[]
	if is_instance_valid(game):
		var loaded: Array=preload("res://mods/pax_harness/src/data/world_sources.gd").native_loaded_maps(game)
		for body: String in game.body_names():
			var d: Dictionary=game.body(body)
			if not d.get("open",false) or d.get("genus")!="rock": continue
			native.append({"body":body,"names":d.get("harness_surface_names",{}),"map_loaded":body==game.home_body() or body in loaded,"artificial_parent":d.get("harness_surface_parent","")})
	return {"ok":true,"result":{"sources":rows,"native_bodies":native,"note":"Native charts.map supports every already-loaded solid body, including custom scenario bodies and approved artificial surfaces. Use navigation.open_surface to generate/open a discovered body's native map first. A missing country on a non-home body selects its territories without a country filter. Explicit mod providers are listed separately; discovering sources never generates maps."}}
func execute(game: Object, args: Dictionary) -> Dictionary:
	var id: String = str(args.get("provider",""))
	if not sources.has(id) or not sources[id].reader.is_valid(): return {"ok":false,"code":"charts.map_provider_unavailable"}
	var item: Dictionary = sources[id]
	if str(args.get("body",item.body)) != item.body: return {"ok":false,"code":"charts.map_provider_body_mismatch"}
	var result: Variant = item.reader.call(game,args.duplicate(true))
	if not result is Dictionary or not _plain_callback(result) or JSON.stringify(result).to_utf8_buffer().size() > 262144: return {"ok":false,"code":"charts.invalid_map_provider_result"}
	result = JSON.parse_string(JSON.stringify(result))
	if not result.get("ok",false): return result
	var raw: Variant = result.get("chart")
	if raw == null and result.get("result") is Dictionary: raw = result.result.get("chart")
	var chart: Dictionary = Chart.validate(raw)
	if chart.is_empty() or chart.type not in ["choropleth","cartogram","symbol_map","flow_map"] or chart.type != args.get("type","choropleth") or chart.get("body","") != item.body: return {"ok":false,"code":"charts.invalid_map_provider_chart"}
	return {"ok":true,"result":{"chart":chart,"provider":id,"body":item.body,"source":chart.source,"note":"Geometry/coordinates are supplied by the named installed mod. Unknown values remain null. This adapter does not generate or visit another body."}}

static func _plain_callback(value: Variant, budget: Dictionary = {}, depth: int = 0) -> bool:
	# GDScript dictionary.dot = value creates StringName keys. They are ordinary
	# JSON object names, not objects or executable values. Canonicalize only after
	# validating the complete bounded callback output.
	if budget.is_empty(): budget = {"nodes":65536}
	budget.nodes -= 1
	if depth > 24 or budget.nodes < 0: return false
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _plain_callback(value[key],budget,depth+1): return false
		return true
	if value is Array:
		for row: Variant in value:
			if not _plain_callback(row,budget,depth+1): return false
		return true
	if value is StringName: return str(value).length() <= 65536
	return Data.plain(value)
