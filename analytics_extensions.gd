extends RefCounted
## Optional API for installed mods. Readers must be synchronous, bounded and read-only.
const Data = preload("res://mods/pax_harness/runtime_tools/tool_data.gd")
const Validation = preload("res://mods/pax_harness/response_validation.gd")
var sources: Dictionary = {}
func register_source(id: String, title: String, description: String, schema: Dictionary, reader: Callable) -> bool:
	if RegEx.create_from_string("^[a-z0-9_]+\\.[a-z0-9_.-]{1,80}$").search(id) == null or sources.has(id) or sources.size() >= 64: return false
	if title.strip_edges().is_empty() or title.length() > 160 or description.length() > 500 or not reader.is_valid(): return false
	if not Data.plain(schema) or schema.get("type") != "object" or JSON.stringify(schema).length() > 8000: return false
	sources[id] = {"id":id,"title":title,"description":description,"parameters_schema":schema.duplicate(true),"reader":reader}
	return true
func describe(args: Dictionary) -> Dictionary:
	var id: String = str(args.get("source",""))
	if id != "":
		if not sources.has(id) or not sources[id].reader.is_valid(): return {"ok":false,"code":"analytics.source_unavailable"}
		var row: Dictionary = sources[id].duplicate(); row.erase("reader")
		return {"ok":true,"result":row}
	var rows: Array = []
	for key: String in sources:
		if sources[key].reader.is_valid(): rows.append(Data.fields(sources[key],["id","title","description"]))
	return {"ok":true,"result":{"sources":rows,"note":"Registered mod data only; no observations loaded. Describe one source, then query its parameters/pages. Base-game sources use analytics.read and resources.history."}}
func query(game: RefCounted, args: Dictionary) -> Dictionary:
	var id: String = str(args.get("source",""))
	if not sources.has(id) or not sources[id].reader.is_valid(): return {"ok":false,"code":"analytics.source_unavailable"}
	var parameters: Dictionary = args.get("parameters",{})
	var checked: Dictionary = Validation.validate(JSON.stringify(parameters),sources[id].parameters_schema)
	if not checked.ok: return {"ok":false,"code":"analytics.invalid_parameters","result":{"errors":Array(checked.errors)}}
	var limit: int = clampi(int(args.get("limit",100)),1,200); var offset: int = maxi(0,int(args.get("offset",0)))
	var result: Variant = sources[id].reader.call(game,parameters.duplicate(true),{"limit":limit,"offset":offset})
	if not result is Dictionary or not Data.plain(result) or JSON.stringify(result).to_utf8_buffer().size() > 262144: return {"ok":false,"code":"analytics.invalid_provider_result"}
	if not result.get("rows") is Array or result.rows.size() > limit or not result.get("source") is String or result.source.strip_edges().is_empty() or not result.get("has_more") is bool: return {"ok":false,"code":"analytics.invalid_provider_page"}
	if result.has_more and (not Data.number(result.get("next_offset")) or result.next_offset <= offset): return {"ok":false,"code":"analytics.invalid_provider_cursor"}
	return {"ok":true,"result":{"provider":id,"data":result.duplicate(true),"offset":offset,"limit":limit,"note":"Read from an explicitly registered installed-mod provider. Field semantics and coverage are supplied by that mod; not inferred by the harness."}}
