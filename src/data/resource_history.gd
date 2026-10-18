extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Recorded observations only. Missing historical values are never zero-filled.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")
const CAPACITY := 1024
const NAMES := {"food":"Еда","water":"Вода","materials":"Стройматериалы","fuel":"Горючее","energy":"Энергия","rare":"Редкие металлы","medicine":"Лекарства","money":"Казна","ammunition":"Боеприпасы","armour":"Броня","black_metals":"Чёрные металлы","coal":"Уголь","colored_metals":"Цветные металлы","drones":"Дроны","gas":"Газ","goods":"Товары","missiles":"Ракеты","oil":"Нефть","weapon":"Оружие"}
var records: Array = []
var _last_key := ""

func restore(state: Dictionary) -> void:
	records = state.get("records",[]).duplicate(true) if state.get("records") is Array else []
	records = records.filter(func(row: Variant): return row is Dictionary and Data.number(row.get("day")) and row.get("stocks") is Dictionary)
	if records.size() > CAPACITY: records = records.slice(-CAPACITY)
	_last_key = ""

func snapshot() -> Dictionary:
	return {"records":records.duplicate(true)}

func capture(game: RefCounted, force: bool = false) -> void:
	var key: String = str(game.country())+":"+str(game.day())
	if not force and key == _last_key: return
	_last_key = key
	var stocks: Dictionary = {}
	for body: String in game.colonies():
		var stock: Dictionary = {}
		var raw: Dictionary = game.resources(body)
		for resource: String in NAMES:
			if Data.number(raw.get(resource)): stock[resource] = raw[resource]
		stocks[body] = stock
	var row := {"day":game.day(),"date":game.date_text(),"country":game.country(),"stocks":stocks}
	# A branch rewind must not retain observations from its abandoned future.
	records = records.filter(func(old: Dictionary): return old.country != row.country or old.day < row.day)
	records.append(row)
	if records.size() > CAPACITY: records = records.slice(-CAPACITY)

func query(game: RefCounted, args: Dictionary) -> Dictionary:
	capture(game,true)
	var main: Node = Sources.main_node(game)
	var native_rows: Array = main.model.history if main != null else []
	return build(native_rows,records,game.country(),args)

static func build(native_rows: Array, saved: Array, country: String, args: Dictionary) -> Dictionary:
	var body: String = str(args.get("body","")) if args.get("scope","country") == "colony" else ""
	var by_resource: Dictionary = {}
	for resource: String in NAMES: by_resource[resource] = {}
	# Native statistics describe the country's aggregate, not an individual colony.
	if body == "":
		for row: Variant in native_rows:
			if not row is Dictionary or not Data.number(row.get("day")): continue
			for resource: String in NAMES:
				if Data.number(row.get(resource)):
					by_resource[resource][int(row.day)] = {"value":row[resource],"label":L.text("День ")+str(int(row.day))}
	for row: Dictionary in saved:
		if row.get("country") != country or not row.get("stocks") is Dictionary: continue
		var totals: Dictionary = {}
		for location: String in row.stocks:
			if body != "" and location != body: continue
			for resource: String in NAMES:
				if Data.number(row.stocks[location].get(resource)):
					totals[resource] = float(totals.get(resource,0))+float(row.stocks[location][resource])
		for resource: String in totals:
			by_resource[resource][int(row.day)] = {"value":totals[resource],"label":str(row.get("date",L.text("День ")+str(int(row.day))))}
	var available: Array = []
	for resource: String in NAMES:
		if not by_resource[resource].is_empty(): available.append({"resource":resource,"name":NAMES[resource],"points":by_resource[resource].size()})
	var requested: Array = args.get("resources",["food","water","materials"])
	var limit: int = clampi(int(args.get("limit",60)),2,60)
	var series: Array = []
	var charts: Array = []
	for resource: String in requested:
		if not by_resource.has(resource): continue
		var days: Array = by_resource[resource].keys()
		days.sort()
		if args.has("since_day"): days = days.filter(func(day: int): return day >= args.since_day)
		if args.has("until_day"): days = days.filter(func(day: int): return day <= args.until_day)
		var total: int = days.size()
		if days.size() > limit: days = days.slice(-limit)
		var labels: Array = []; var values: Array = []
		for day: int in days:
			labels.append(by_resource[resource][day].label)
			values.append(by_resource[resource][day].value)
		series.append({"resource":resource,"name":NAMES[resource],"total_points":total,"returned":days.size(),"x":days,"labels":labels,"values":values,"has_older":total>days.size()})
		if days.size() >= 2:
			charts.append({"type":"line","title":NAMES[resource]+" · "+country,"labels":labels,"x":days,"series":[{"name":NAMES[resource],"values":values}],"curve":args.get("curve","linear"),"x_label":L.text("Дни кампании"),"unit":L.text("ед."),"source":L.text("Сохранённая статистика державы и наблюдения запасов") if body == "" else L.text("Наблюдения запасов · ")+body})
	return {"country":country,"body":body,"coverage":"partial_retained_observations","available_resources":available,"series":series,"charts":charts,"note":"Charts are ready to display as pax-chart blocks. x is elapsed campaign days, including uneven gaps. Fewer than 2 points is not a trend. Missing values were not filled; only retained actual observations are available. New stocks are recorded by this mod from installation onward. Use since_day/until_day to request an older range."}
