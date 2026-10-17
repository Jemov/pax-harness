extends RefCounted
## Read-only analytical rows from the current save, not estimated microdata.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")
static func available(game: Object) -> bool:
	return is_instance_valid(game) and game.has_method("economy") and game.has_method("province") and game.has_method("provinces_of")
static func execute(game: Object, args: Dictionary) -> Dictionary:
	if not Sources.active(game): return {"ok":false,"code":"charts.inactive_world"}
	var body: String = str(args.get("body",game.home_body()))
	if body != game.home_body(): return {"ok":false,"code":"charts.home_body_only","result":{"message":"This adapter reads the already-loaded home-country economy only."}}
	var country: String = str(args.get("country",game.country()))
	var kind: String = str(args.get("section","enterprises"))
	if country != game.country() and kind != "countries": return {"ok":false,"code":"charts.foreign_economy_unverified","result":{"message":"This adapter exposes the player's economy. Read foreign province records via provinces.read; absent enterprise data is not zero."}}
	var economy: Dictionary = game.economy(body)
	var ids: Array = game.provinces_of(body,country)
	var counts: Dictionary = {}; var levels: Dictionary = {}; var groups: Dictionary = {}; var enterprises: Array = []
	for raw: Variant in economy.get("enterprises",[]):
		if not raw is Dictionary or not Data.number(raw.get("levels")): continue
		var id: int = int(raw.get("province",0))
		if id not in ids: continue
		var province: Dictionary = game.province(body,id)
		var row: Dictionary = {"id":raw.get("id"),"type":str(raw.get("type","unknown")),"province":id,"province_name":str(province.get("name","")),"levels":float(raw.levels)}
		enterprises.append(row); counts[id] = int(counts.get(id,0))+1; levels[id] = float(levels.get(id,0))+float(raw.levels)
		if not groups.has(row.type): groups[row.type] = []
		groups[row.type].append(row.levels)
	var rows: Array = []
	var extra: Dictionary = {}
	match kind:
		"countries":
			for faction: Dictionary in game.factions():
				rows.append(Data.fields(faction,["name","type","humans","income_v_year","ours"]))
			extra = {"warning":"Presence of a field is not guaranteed. income_v_year, where recorded, is aggregate organizational income, not household wages. Do not fill absent population/income with zeros."}
		"enterprises":
			rows = enterprises
			extra = {"measure":"Enterprise development levels; not workers, incomes or physical output. Group only the returned rows; use pages for the complete distribution."}
		"provinces":
			for id: int in ids:
				var row: Dictionary = Data.clean(game.province(body,id))
				row["enterprise_count"] = counts.get(id,0); row["enterprise_levels"] = levels.get(id,0)
				rows.append(row)
		"resource_flows":
			if country != game.country(): return {"ok":false,"code":"charts.foreign_flow_unavailable"}
			for resource: String in economy.get("accounting",{}):
				var components: Dictionary = economy.accounting[resource]
				var incoming := 0.0; var outgoing := 0.0; var flows: Array = []
				for name: String in components:
					if not Data.number(components[name]): continue
					var value: float = float(components[name]); incoming += maxf(0,value); outgoing += maxf(0,-value)
					flows.append({"name":name,"signed_amount":value})
				rows.append({"resource":resource,"components":flows,"incoming":incoming,"outgoing":outgoing,"net_change":incoming-outgoing})
			extra = {"weeks":economy.get("accounting_weeks"),"warning":"These are recorded aggregate accounting flows, not bilateral trade by partner. Opposite signs mean supply/use; net difference is not an invented extra flow."}
		"statistics":
			if country != game.country(): return {"ok":false,"code":"charts.foreign_history_unavailable"}
			var main: Node = Sources.main_node(game)
			if main != null: rows = Data.clean(main.model.history)
			extra = {"coverage":"partial retained aggregate country observations; not individual people/households or per-province income histories"}
		_: return {"ok":false,"code":"charts.unknown_section"}
	var offset: int = maxi(0,int(args.get("offset",0))); var limit: int = clampi(int(args.get("limit",100)),1,200)
	return {"ok":true,"result":{"country":country,"body":body,"date":game.date_text(),"section":kind,"rows":rows.slice(offset,offset+limit),"total":rows.size(),"next_offset":offset+mini(limit,maxi(0,rows.size()-offset)),"has_more":offset+limit<rows.size(),"details":extra,"source":"Current native economy/province records and retained statistics; no estimates or world changes."}}
