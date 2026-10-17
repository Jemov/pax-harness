extends RefCounted
## Curated read adapters. Model arguments never select arbitrary methods or objects.
const Data = preload("res://mods/pax_harness/runtime_tools/tool_data.gd")
const Validation = preload("res://mods/pax_harness/response_validation.gd")
const DEFINITIONS := {
	"dyson_sphere_program.state":{"mod":"dyson_sphere_program","title":"Сфера Дайсона: состояние","description":"Read one category of actual megastructures, fleets, rivals or research. Empty state means not built/recorded; never invent a developed space economy.","parameters_schema":{"type":"object","properties":{"section":{"type":"string","enum":["swarms","sphere","rings","furnaces","ships","stations","colonies","rivals","research"]},"country":{"type":"string","maxLength":160}},"required":["section"],"additionalProperties":false}},
	"dyson_sphere_program.stages":{"mod":"dyson_sphere_program","title":"Сфера Дайсона: этапы и стоимость","description":"Configured stage requirements for ring/swarm/furnace, not built assets or observed expenditure. Suitable for comparing design costs by resource.","parameters_schema":{"type":"object","properties":{"kind":{"type":"string","enum":["ring","swarm","furnace"]}},"required":["kind"],"additionalProperties":false}},
	"pax_corporations.companies":{"mod":"pax_corporations","title":"Корпорации: компании и котировки","description":"One page of live companies. Filter country/sector/id; history requires one explicit id. Company mean wages are not individual resident incomes.","parameters_schema":{"type":"object","properties":{"country":{"type":"string","maxLength":160},"sector":{"type":"string","maxLength":160},"id":{"type":"string","maxLength":160},"history":{"type":"boolean"}},"additionalProperties":false}},
	"economy_mod.summary":{"mod":"economy_mod","title":"Переработка экономики: сводка","description":"Read cached public economy/employment/power summary for the home body. No construction, trading or simulation step.","parameters_schema":{"type":"object","properties":{},"additionalProperties":false}},
	"occupation_rework.records":{"mod":"occupation_rework","title":"Оккупации и зависимые страны","description":"One page of the mod's actual subjects/occupied/world_subjects records. Fields follow the mod's semantics; absent values remain absent.","parameters_schema":{"type":"object","properties":{"section":{"type":"string","enum":["subjects","occupied","world_subjects"]}},"required":["section"],"additionalProperties":false}}
}
static func available(id: String, api: Node) -> bool:
	if not DEFINITIONS.has(id) or not api.has_mod(DEFINITIONS[id].mod): return false
	var mod: Node = api.get_mod(DEFINITIONS[id].mod)
	if not is_instance_valid(mod): return false
	match id:
		"dyson_sphere_program.state": return mod.has_method("get_swarms") and mod.has_method("is_ready") and mod.is_ready()
		"dyson_sphere_program.stages": return mod.has_method("get_stages") and mod.has_method("is_ready") and mod.is_ready()
		"pax_corporations.companies":
			var db: Variant = Data.property(mod,"db")
			if not is_instance_valid(db): return false
			for method: String in ["fund","name_of","price","cap","staff","wage","history"]:
				if not db.has_method(method): return false
			return Data.property(db,"companies") is Array
		"economy_mod.summary": return mod.has_method("aside_summary")
		"occupation_rework.records": return Data.property(mod,"subjects") is Dictionary and Data.property(mod,"occupied") is Dictionary and Data.property(mod,"world_subjects") is Dictionary
	return true
static func describe(args: Dictionary, api: Node) -> Dictionary:
	var id: String = str(args.get("source",""))
	if id != "":
		if not available(id,api): return {"ok":false,"code":"analytics.source_unavailable"}
		var row: Dictionary = DEFINITIONS[id].duplicate(true); row["id"] = id
		return {"ok":true,"result":row}
	var rows: Array = []
	for key: String in DEFINITIONS:
		if available(key,api):
			var row: Dictionary = Data.fields(DEFINITIONS[key],["title","description"]); row["id"] = key; rows.append(row)
	return {"ok":true,"result":{"sources":rows}}
static func query(game: RefCounted, args: Dictionary, api: Node) -> Dictionary:
	var id: String = str(args.get("source",""))
	if not available(id,api): return {"ok":false,"code":"analytics.source_unavailable"}
	var p: Dictionary = args.get("parameters",{})
	var checked: Dictionary = Validation.validate(JSON.stringify(p),DEFINITIONS[id].parameters_schema)
	if not checked.ok: return {"ok":false,"code":"analytics.invalid_parameters","result":{"errors":Array(checked.errors)}}
	var mod: Node = api.get_mod(DEFINITIONS[id].mod)
	var rows: Array = []; var notes: Dictionary = {}
	var limit: int = clampi(int(args.get("limit",50)),1,200); var offset: int = maxi(0,int(args.get("offset",0)))
	match id:
		"dyson_sphere_program.stages":
			rows = mod.get_stages(p.kind)
			notes = {"kind":p.kind,"basis":"configured requirements, not observed construction","units":"resource-specific costs from the mod; never sum unlike resources as physical tonnes"}
		"dyson_sphere_program.state":
			var method: String = {"swarms":"get_swarms","sphere":"get_sphere","rings":"get_rings","furnaces":"get_furnaces","ships":"get_ships","stations":"get_stations","colonies":"get_orbital_colonies","rivals":"get_rivals","research":"get_research"}[p.section]
			if not mod.has_method(method): return {"ok":false,"code":"analytics.mod_api_version_missing_method","result":{"method":method}}
			match p.section:
				"swarms": rows = mod.get_swarms()
				"sphere": rows = [mod.get_sphere()]
				"rings": rows = mod.get_rings()
				"furnaces": rows = mod.get_furnaces()
				"ships": rows = mod.get_ships(str(p.get("country",game.country())))
				"stations": rows = mod.get_stations()
				"colonies": rows = mod.get_orbital_colonies()
				"rivals": rows = mod.get_rivals()
				"research": rows = mod.get_research(str(p.get("country",game.country())))
			notes = {"section":p.section,"basis":"current mod state; no absent historical points inferred"}
		"pax_corporations.companies":
			if p.get("history",false) and str(p.get("id","")).is_empty(): return {"ok":false,"code":"analytics.history_requires_company_id"}
			for company: Dictionary in mod.db.companies:
				if p.get("country","") != "" and company.get("_country") != p.country: continue
				if p.get("sector","") != "" and company.get("sector") != p.sector: continue
				if p.get("id","") != "" and company.get("id") != p.id: continue
				rows.append(company)
			notes = {"units":{"price_usd":"USD/share","capitalization_mln_usd":"million USD","revenue_mln_usd_year":"million USD/year","profit_mln_usd_year":"million USD/year","staff":"employees","mean_wage_usd_month":"USD/employee/month"},"warning":"Company means and mod simulation estimates, not individual household samples. Price history is a retained weekly sequence, latest at the right; exact calendar dates are not supplied by this adapter."}
		"economy_mod.summary":
			var summary: Dictionary = mod.aside_summary(game.home_body())
			if summary.is_empty(): return {"ok":false,"code":"analytics.provider_not_ready"}
			rows = [summary]; notes = {"basis":"mod public live summary","scope":"power/labour/facilities/gdp/taxes describe the home body; money_income/expense/net aggregate ALL player colony bodies, as in the mod's own summary","units":{"money_income":"native game money/week","money_expense":"native game money/week","money_net":"native game money/week","gdp_week":"native game money/week","taxes_week":"native game money/week","people":"persons","employed":"persons","unemployed":"persons","soldiers":"persons","unemp_ratio":"fraction, negative sentinel means unknown","tax_rate":"fraction","fulfilled_need":"fraction, negative sentinel means unknown","power_cap":"native power capacity units","power_load":"native power capacity units"}}
		"occupation_rework.records":
			var records: Dictionary = mod.subjects if p.section == "subjects" else mod.occupied if p.section == "occupied" else mod.world_subjects
			for key: Variant in records: rows.append({"key":str(key),"record":records[key]})
	var selected: Array = rows.slice(offset,offset+limit)
	if id == "pax_corporations.companies":
		var formatted: Array = []
		for company: Dictionary in selected:
			var row := {"id":company.id,"name":mod.db.name_of(company),"country":company.get("_country"),"sector":company.get("sector"),"price_usd":mod.db.price(company),"capitalization_mln_usd":mod.db.cap(company),"revenue_mln_usd_year":mod.db.fund(company,"выручка"),"profit_mln_usd_year":mod.db.fund(company,"profit"),"staff":mod.db.staff(company),"mean_wage_usd_month":mod.db.wage(company)}
			if p.get("history",false): row["history_price_usd"] = mod.db.history(company).duplicate()
			formatted.append(row)
		selected = formatted
	var result := {"provider":id,"date":game.date_text(),"rows":Data.clean(selected),"total":rows.size(),"returned":selected.size(),"next_offset":offset+selected.size(),"has_more":offset+selected.size()<rows.size(),"details":notes,"source":str(DEFINITIONS[id].title)+" · "+game.date_text()}
	if JSON.stringify(result).to_utf8_buffer().size() > 262144: return {"ok":false,"code":"analytics.page_too_large","result":{"message":"Use a smaller limit or one filtered record."}}
	return {"ok":true,"result":result}
