extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Outcome index saved with this mod. Reading the index never calls the AI.
var records: Array = []
var _active: Dictionary = {}
var _game: RefCounted
var _scan_day: int = -1
var _seeded: bool = false
var _stage_stamp: int = -1

func setup(game: RefCounted) -> void:
	_game = game
	if not _seeded:
		_scan_memory()
		_seeded = true
	scan()

func restore(state: Dictionary) -> void:
	records = state.get("records",[]).duplicate(true)
	_active = state.get("active",{}).duplicate(true)
	_seeded = false
	_scan_day = -1
	_stage_stamp = -1

func snapshot() -> Dictionary:
	scan()
	return {"version":1,"records":records.duplicate(true),"active":_active.duplicate(true)}

static func is_failure(outcome: String) -> bool:
	var text: String = outcome.to_lower().strip_edges()
	return text.begins_with("failure") or text.begins_with("failed") or text.begins_with("провал") or text.begins_with("неудач")

func scan() -> void:
	if _game == null: return
	var model: Object = _game.main.model
	var stamp: int = hash(model.stage_log)
	if stamp == _stage_stamp and _scan_day == _game.day():
		for order: Dictionary in model.orders: _active[str(order.id)] = order.duplicate(true)
		return
	_stage_stamp = stamp
	for entry: Dictionary in model.stage_log:
		var row: Dictionary = {"text":str(entry.get("order_cmd","")),"outcome":str(entry.get("outcome","")),
			"body":str(entry.get("body","")),"date":str(entry.get("day","")),"day":_date_day(str(entry.get("day",""))),"turn":-1,"source":"native_outcome"}
		for order: Dictionary in _active.values():
			if str(order.get("request",{}).get("understood",order.get("text",""))) == row.text or str(order.get("text","")) == row.text:
				row["order_id"] = int(order.id)
				row["original_text"] = str(order.get("text",""))
				break
		_add(row)
	for order: Dictionary in model.orders: _active[str(order.id)] = order.duplicate(true)
	if _scan_day != _game.day():
		_scan_day = _game.day()
		_scan_memory()

func _scan_memory() -> void:
	if _game == null: return
	var memory: Object = _game.main.model.memory
	if memory == null: return
	for kind: String in ["body","assistant"]:
		for entry: Dictionary in memory.list_(kind):
			var key: String = str(entry.get("name",""))
			if key == "": continue
			var raw: String = str(memory._read_it(memory._file_name(kind,key)))
			for line: String in raw.split("\n",false):
				if not line.begins_with("- [н"): continue
				var close: int = line.find("]")
				if close < 0: continue
				var turn: int = int(line.substr(4,close-4))
				var text: String = line.substr(close+1).trim_prefix("!").strip_edges()
				var sep: int = text.rfind(" — ")
				if sep < 0: continue
				var outcome: String = text.substr(sep+3)
				if not is_failure(outcome): continue
				var body: String = key if kind == "body" else ""
				if kind == "assistant":
					var prefix: int = text.find(": ")
					if prefix >= 0 and prefix < sep:
						body = text.left(prefix)
						text = text.substr(prefix+2)
						sep = text.rfind(" — ")
				_add({"text":text.left(sep),"outcome":outcome.get_slice(";",0),"reason":outcome.substr(outcome.find(";")+1).strip_edges() if outcome.contains(";") else "",
					"body":body,"turn":turn,"day":-1,"date":"","source":"retained_memory"})

func _add(row: Dictionary) -> void:
	if str(row.get("text","")).is_empty() or str(row.get("outcome","")).is_empty(): return
	var signature: String = str(row.get("body","")) + "|" + str(row.text).strip_edges().to_lower() + "|" + str(row.outcome).get_slice(";",0).strip_edges().to_lower()
	for old: Dictionary in records:
		if str(old.get("signature","")) != signature: continue
		var same_date: bool = int(row.get("day",-1)) >= 0 and int(old.get("day",-1)) == int(row.day)
		var same_turn: bool = int(row.get("turn",-1)) >= 0 and int(old.get("turn",-1)) == int(row.turn)
		var recovered_copy: bool = str(old.source) != str(row.source) and (int(old.get("day",-1)) < 0 or int(row.get("day",-1)) < 0)
		if same_date or same_turn or recovered_copy:
			for field: String in ["reason","order_id","original_text"]:
				if row.has(field) and str(row[field]) != "": old[field] = row[field]
			if int(row.get("day",-1)) >= 0:
				old.day = row.day
				old.date = row.date
			if int(row.get("turn",-1)) >= 0: old.turn = row.turn
			return
	row = row.duplicate(true)
	row["signature"] = signature
	row["key"] = str(records.size()+1)
	row["sequence"] = records.size()+1
	records.append(row)

static func _date_day(text: String) -> int:
	var months: Array = [L.text("января"),L.text("февраля"),L.text("марта"),L.text("апреля"),L.text("мая"),L.text("июня"),L.text("июля"),L.text("августа"),L.text("сентября"),L.text("октября"),L.text("ноября"),L.text("декабря")]
	var parts: PackedStringArray = text.split(" ",false)
	if parts.size() < 3 or not parts[0].is_valid_int() or parts[1] not in months or not parts[2].is_valid_int(): return -1
	return int(Time.get_unix_time_from_datetime_dict({"year":int(parts[2]),"month":months.find(parts[1])+1,"day":int(parts[0]),"hour":0,"minute":0,"second":0}) / 86400)

func query(arguments: Dictionary) -> Dictionary:
	scan()
	var body: String = str(arguments.get("body",""))
	var search: String = str(arguments.get("query","")).to_lower()
	var matched: Array = []
	for row: Dictionary in records:
		if not is_failure(str(row.outcome)): continue
		if body != "" and str(row.get("body","")) != body: continue
		if search != "" and not (str(row.text)+" "+str(row.get("original_text",""))+" "+str(row.get("reason",""))).to_lower().contains(search): continue
		matched.append(row.duplicate(true))
	matched.sort_custom(func(a: Dictionary,b: Dictionary):
		if int(a.get("turn",-1)) >= 0 and int(b.get("turn",-1)) >= 0 and int(a.turn) != int(b.turn): return int(a.turn) > int(b.turn)
		if int(a.get("day",-1)) >= 0 and int(b.get("day",-1)) >= 0 and int(a.day) != int(b.day): return int(a.day) > int(b.day)
		return int(a.sequence) > int(b.sequence))
	var offset: int = maxi(0,int(arguments.get("offset",0)))
	var limit: int = clampi(int(arguments.get("limit",10)),1,1000)
	var count_only: bool = bool(arguments.get("count_only",false))
	var page: Array = []
	var bytes: int = 0
	if not count_only:
		for row: Dictionary in matched.slice(offset,offset+limit):
			var cost: int = JSON.stringify(row).to_utf8_buffer().size()
			if bytes+cost > 150000 and not page.is_empty(): break
			bytes += cost
			page.append(row)
	for row: Dictionary in page: row.erase("signature")
	return {"total":matched.size(),"returned":page.size(),"offset":offset,"limit":limit,"items":page,
		"has_more":not count_only and offset+page.size()<matched.size(),"next_offset":offset+page.size(),
		"coverage":"retained_native_outcomes_and_memory_plus_persistent_local_archive","complete_campaign_history":false,
		"note":"Count covers recoverable records, not discarded history. No date/order id is invented. Use offset to fetch all pages; order by known execution turn/date, otherwise recovery order."}
