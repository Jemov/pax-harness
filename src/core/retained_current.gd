extends RefCounted
const WorldSources = preload("res://mods/pax_harness/src/data/world_sources.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")

static func collect(game: Object, _precollected: Dictionary = {}, include_history: bool = true) -> Dictionary:
	if not WorldSources.active(game): return {"ok":false,"campaign_context":{},"diagnostics":[]}
	var main: Node = WorldSources.main_node(game)
	var model: Object = main.model
	var current: Dictionary = {"authoritative":true,"date":game.date(),"elapsed_day":game.day(),"turn":model.sim.turn,
		"stock":{},"orders":Data.clean(model.orders),"trust":model.sim.res.get("trust",0),"sources":{}}
	for body: String in game.colonies(): current.stock[body] = Data.clean(game.resources(body))
	var history: Dictionary = {"authoritative":false,"records":[],"sources":{},"completeness":"partial_retained",
		"bootstrap_gap":true,"gap_reason":"Only retained records can be recovered. Use orders.failed for the indexed failure archive.","record_order":"source_snapshot_order_not_global_chronology"}
	if include_history:
		for row: Dictionary in model.world.chronicle:
			_record(history,"chronicle","",Data.fields(row,["body","text","tone","weight"]),row.get("day"))
		for row: Dictionary in main.player.assistant_history: _record(history,"dialogue.assistant","",row)
		for faction: Dictionary in model.factions:
			for row: Dictionary in faction.get("correspondence",[]): _record(history,"dialogue.faction",str(faction.get("name","")),row,row.get("day"))
		for row: Dictionary in model.stage_log: _record(history,"order_result","",row)
		for row: Dictionary in model.history: _record(history,"statistics","",row,row.get("day"))
		if not model.newspaper_issue.is_empty(): _record(history,"newspaper","",model.newspaper_issue)
		if model.memory != null:
			for row: Dictionary in model.memory.list_():
				var kind: String = str(row.get("kind",row.get("вид","")))
				var key: String = str(row.get("name",row.get("имя","")))
				if key != "" and kind in ["person","group","body","system","assistant"]:
					_record(history,"memory."+kind,key,{"text":model.memory.recall(kind,key,"",400),"recall_limit":400})
	for row: Dictionary in history.records:
		var source: String = str(row.source)
		if not history.sources.has(source): history.sources[source] = {"available":true,"count":0,"coverage":"retained_native_records"}
		history.sources[source].count += 1
	return {"ok":true,"campaign_context":{"current":current,"history":history},"diagnostics":[]}

static func page(history: Dictionary, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = history.duplicate(true)
	var records: Array = result.get("records",[])
	var query: String = str(options.get("query","")).to_lower()
	var source: String = str(options.get("source",""))
	if source != "": records = records.filter(func(row: Dictionary): return row.get("source") == source)
	if query != "": records = records.filter(func(row: Dictionary): return query in JSON.stringify(row).to_lower())
	var offset: int = maxi(0,int(options.get("offset",0)))
	var limit: int = clampi(int(options.get("limit",10)),1,100)
	result.records = records.slice(offset,offset+limit)
	result["total"] = records.size()
	result["returned"] = result.records.size()
	result["offset"] = offset
	result["limit"] = limit
	result["has_more"] = offset+result.records.size()<records.size()
	result["next_offset"] = offset+result.records.size()
	return result

static func _record(history: Dictionary, source: String, source_id: String, content: Dictionary, day: Variant = null) -> void:
	history.records.append({"id":history.records.size()+1,"source":source,"source_id":source_id,"capture":"retained_snapshot","elapsed_day":day,"turn":null,"date":null,"content":Data.clean(content)})
