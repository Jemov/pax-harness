extends RefCounted
## Read-only bounded tables, referenced only through this task's successful receipts.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Chart = preload("res://mods/pax_harness/src/visualization/specs/chat_chart.gd")
const MAX_ROWS := 20000
const MAX_CELLS := 300000
const MAX_BYTES := 4000000
const MAX_FIELDS := 40

static func failure(code: String, message: String) -> Dictionary:
	return {"ok":false,"code":"datasets."+code,"result":{"message":message}}

static func execute(name: String, args: Dictionary, receipts: Array) -> Dictionary:
	if name == "datasets.read": return read_page(args,receipts)
	if name == "datasets.chart" and not args.has("rows") and not args.has("receipt_id") and not args.has("receipt_ids"):
		return standalone_chart(args)
	var input: Dictionary = resolve(args,receipts)
	if not input.get("ok",false): return input
	match name:
		"datasets.transform": return transform(input.result,args,receipts)
		"statistics.calculate": return statistics(input.result,args)
		"datasets.chart": return chart(input.result,args)
	return failure("unknown_tool","Неизвестная операция над данными.")

static func receipt_result(id: String, receipts: Array) -> Dictionary:
	for receipt: Variant in receipts:
		if receipt is Dictionary and receipt.get("call_id","") == id and receipt.get("status") == "complete" and receipt.get("result") is Dictionary:
			return tabular_result(receipt.result,str(receipt.get("name","")))
	return {}

## Only known receipt envelopes are unwrapped; never follow arbitrary paths or parse fragments.
static func tabular_result(result: Dictionary, name: String) -> Dictionary:
	if name == "analytics.query" and result.get("data") is Dictionary and result.data.get("rows") is Array:
		var data: Dictionary = result.data.duplicate(true)
		data["provider"] = result.get("provider","")
		data["offset"] = result.get("offset",0)
		return data
	if name in ["trace.read","trace.replay"]:
		var events: Array = result.get("items",result.get("recorded_observations",[]))
		var candidates: Array = []
		for wrapper: Variant in events:
			if not wrapper is Dictionary or not wrapper.get("event") is Dictionary: continue
			var event: Dictionary = wrapper.event
			var recorded: Dictionary = event.get("receipt",event)
			if recorded.get("status",event.get("status")) != "complete" or not recorded.get("result") is Dictionary: continue
			var data: Dictionary = tabular_result(recorded.result,str(recorded.get("name",event.get("name",""))))
			if not data.get("rows") is Array: continue
			data = data.duplicate(true)
			data["historical"] = true; data["current_world_verified"] = false
			data["recorded_origin"] = {"message_id":wrapper.get("message_id",""),"call_id":event.get("id",recorded.get("call_id","")),"date":wrapper.get("date","")}
			candidates.append(data)
		return candidates[0] if candidates.size() == 1 else {}
	return result

static func resolve(args: Dictionary, receipts: Array) -> Dictionary:
	var modes: int = int(args.has("rows"))+int(args.has("receipt_ids"))+int(args.has("receipt_id"))
	if modes != 1: return failure("one_input_required","Укажите ровно один вход: receipt_id, receipt_ids или учебные rows с source.")
	var rows: Array = []; var provenance: Array = []; var coverage: Array = []; var basis := "observed"
	if args.has("rows"):
		if not args.rows is Array or str(args.get("source","")).strip_edges().is_empty(): return failure("scenario_source_required","Для явно переданных строк нужен source; они считаются сценарными данными.")
		rows = args.rows.duplicate(true); basis = "scenario"; provenance.append({"source":str(args.source),"basis":"scenario"})
	else:
		var ids: Array = args.get("receipt_ids",[args.get("receipt_id","")])
		if ids.is_empty() or ids.size() > 100: return failure("invalid_references","Требуется от 1 до 100 уникальных результатов текущей задачи.")
		var seen: Dictionary = {}
		for raw_id: Variant in ids:
			var id: String = str(raw_id)
			if seen.has(id): return failure("duplicate_reference","Один результат нельзя включать дважды: "+id)
			seen[id] = true
			var result: Dictionary = receipt_result(id,receipts)
			if result.is_empty(): return failure("receipt_unavailable","Нет успешно завершённого результата в этой задаче: "+id)
			if ids.size() == 1 and result.has("statistics") and result.get("rows") is Array and result.rows.size() <= 24 and result.has("basis") and result.has("source") and result.has("provenance") and JSON.stringify(result).to_utf8_buffer().size() <= MAX_BYTES:
				return {"ok":true,"result":result.duplicate(true)}
			if not result.get("rows") is Array: return failure("rows_unavailable","Результат "+id+" не содержит табличных rows. Сначала запросите нужный источник данных.")
			rows.append_array(result.rows.duplicate(true))
			if rows.size() > MAX_ROWS: return failure("row_limit","Не более 20000 строк. Запросите агрегаты или меньший диапазон.")
			var inherited: String = str(result.get("basis","observed"))
			if inherited != "observed": basis = "scenario" if inherited == "scenario" or basis == "scenario" else "forecast"
			provenance.append({"receipt_id":id,"source":result.get("source","Recorded tool observation"),"basis":inherited,"date":result.get("date",null),"body":result.get("body",null),"country":result.get("country",null),"ancestors":result.get("provenance",[]),"provider":result.get("provider",null),"historical":result.get("historical",false),"current_world_verified":result.get("current_world_verified",null),"recorded_origin":result.get("recorded_origin",{})})
			coverage.append({"receipt_id":id,"returned":result.rows.size(),"total":result.get("total",result.get("original_count",result.rows.size())),"has_more":result.get("has_more",false),"details":result.get("coverage",result.get("details",{})),"offset":result.get("offset",null),"next_offset":result.get("next_offset",null)})
	var cells := 0
	if rows.size() > MAX_ROWS: return failure("row_limit","Не более 20000 строк.")
	for row: Variant in rows:
		if not row is Dictionary or row.size() > MAX_FIELDS: return failure("invalid_rows","Каждая строка должна быть объектом не более чем с 40 полями.")
		cells += row.size()
		for key: Variant in row:
			if not key is String or key.length() > 160 or not Data.plain(row[key]): return failure("invalid_cell","Недопустимое поле или значение в строке.")
	if cells > MAX_CELLS or JSON.stringify(rows).to_utf8_buffer().size() > MAX_BYTES: return failure("size_limit","Набор превышает лимит 300000 ячеек или 4 МБ; выберите меньше полей.")
	return {"ok":true,"result":{"rows":rows,"source":str(args.get("source","Учебные данные")) if args.has("rows") else "Преобразование сохранённых результатов инструментов","basis":basis,"provenance":provenance,"coverage":coverage,"original_count":rows.size()}}

static func transform(input: Dictionary, args: Dictionary, receipts: Array) -> Dictionary:
	var rows: Array = input.rows.duplicate(true)
	if args.has("join"):
		var joined: Dictionary = join_rows(rows,args.join,receipts)
		if not joined.ok: return joined
		rows = joined.result.rows
		input.provenance.append(joined.result.provenance)
		if joined.result.provenance.basis != "observed": input.basis = "scenario" if joined.result.provenance.basis == "scenario" or input.basis == "scenario" else "forecast"
	for filter: Dictionary in args.get("filters",[]):
		var filtered: Array = []
		for row: Dictionary in rows:
			if matches(row.get(str(filter.field)),filter): filtered.append(row)
		rows = filtered
	var filtered_count := rows.size()
	if not args.get("aggregates",[]).is_empty():
		var grouped: Dictionary = group_rows(rows,args.get("group_by",[]),args.aggregates)
		if not grouped.ok: return grouped
		rows = grouped.result.rows
	elif not args.get("group_by",[]).is_empty(): return failure("aggregate_required","Для группировки укажите aggregates.")
	var sorts: Array = args.get("sort",[])
	if not sorts.is_empty(): rows.sort_custom(func(a: Dictionary,b: Dictionary): return ordered(a,b,sorts))
	var before_sampling := rows.size()
	if args.has("downsample"):
		var sampled: Dictionary = downsample(rows,args.downsample)
		if not sampled.ok: return sampled
		rows = sampled.result.rows
	if args.has("limit"): rows = rows.slice(0,clampi(int(args.limit),1,MAX_ROWS))
	if not args.get("fields",[]).is_empty():
		for index: int in rows.size(): rows[index] = Data.fields(rows[index],args.fields)
	var result: Dictionary = input.duplicate(true); result.rows = rows
	# Derived statistics refer to the original population; transformed rows cannot reuse them.
	result.erase("statistics"); result.erase("correlation")
	result["filtered_count"] = filtered_count; result["before_sampling"] = before_sampling; result["selected_count"] = rows.size()
	result["sampled"] = args.has("downsample") and rows.size() < before_sampling
	result["truncated"] = args.has("limit") and rows.size() < before_sampling
	result["operations"] = args.duplicate(true); result.operations.erase("rows")
	if JSON.stringify(result).to_utf8_buffer().size() > MAX_BYTES: return failure("size_limit","Результат превышает 4 МБ.")
	return {"ok":true,"result":result}

static func matches(value: Variant, filter: Dictionary) -> bool:
	var expected: Variant = filter.get("value")
	match str(filter.op):
		"missing": return value == null
		"present": return value != null
		"eq": return value != null and value == expected
		"ne": return value != null and value != expected
		"in": return value != null and expected is Array and value in expected
		"contains": return value is String and expected is String and expected.to_lower() in value.to_lower()
		"gt": return Data.number(value) and Data.number(expected) and value > expected
		"gte": return Data.number(value) and Data.number(expected) and value >= expected
		"lt": return Data.number(value) and Data.number(expected) and value < expected
		"lte": return Data.number(value) and Data.number(expected) and value <= expected
	return false

static func ordered(a: Dictionary,b: Dictionary,sorts: Array) -> bool:
	for item: Dictionary in sorts:
		var av: Variant = a.get(str(item.field)); var bv: Variant = b.get(str(item.field))
		if av == bv: continue
		if av == null: return false
		if bv == null: return true
		var less: bool = av < bv if Data.number(av) and Data.number(bv) else str(av).naturalnocasecmp_to(str(bv)) < 0
		return not less if item.get("descending",false) else less
	return false

static func group_rows(rows: Array, keys: Array, aggregates: Array) -> Dictionary:
	var groups: Dictionary = {}
	for row: Dictionary in rows:
		var values: Array = []
		for key: String in keys: values.append(row.get(key))
		var token: String = JSON.stringify(values)
		if not groups.has(token): groups[token] = {"keys":values,"rows":[]}
		groups[token].rows.append(row)
	if rows.is_empty() and keys.is_empty(): groups["[]"] = {"keys":[],"rows":[]}
	var result: Array = []
	for group: Dictionary in groups.values():
		var row: Dictionary = {}
		for i: int in keys.size(): row[str(keys[i])] = group.keys[i]
		for aggregate: Dictionary in aggregates:
			var alias: String = str(aggregate.get("as",str(aggregate.op)+"_"+str(aggregate.get("field","rows"))))
			if row.has(alias): return failure("duplicate_column","Повторное имя агрегата: "+alias)
			var values: Array = []
			for source: Dictionary in group.rows:
				var value: Variant = source.get(str(aggregate.get("field","")))
				if Data.number(value): values.append(float(value))
			var number: Variant = null
			match str(aggregate.op):
				"count":
					number = group.rows.size()
					if aggregate.has("field"):
						number = 0
						for source: Dictionary in group.rows:
							if source.get(str(aggregate.field)) != null: number += 1
				"sum":
					if not values.is_empty():
						number = 0.0
						for value: float in values: number += value
				"mean":
					if not values.is_empty():
						number = 0.0
						for value: float in values: number += value/values.size()
				"min": number = values.min() if not values.is_empty() else null
				"max": number = values.max() if not values.is_empty() else null
				_: return failure("unknown_aggregate","Неизвестный агрегат.")
			row[alias] = number
		result.append(row)
	return {"ok":true,"result":{"rows":result}}

static func join_rows(left: Array, args: Dictionary, receipts: Array) -> Dictionary:
	var right: Dictionary = receipt_result(str(args.get("receipt_id","")),receipts)
	if not right.get("rows") is Array: return failure("join_unavailable","Правый набор должен быть успешным результатом текущей задачи с rows.")
	var index: Dictionary = {}; var right_key: String = str(args.get("right_key","")); var left_key: String = str(args.get("left_key","")); var prefix: String = str(args.get("prefix","right_"))
	for row: Variant in right.rows:
		if not row is Dictionary: return failure("join_invalid_rows","Правый набор содержит не объекты.")
		var key: Variant = row.get(right_key)
		if key == null: continue
		var token: String = JSON.stringify(key)
		if index.has(token): return failure("join_not_unique","Правый ключ должен быть уникален; сначала агрегируйте его.")
		index[token] = row
	var result: Array = []
	for original: Dictionary in left:
		var row: Dictionary = original.duplicate(true); var key: Variant = original.get(left_key)
		var match_row: Dictionary = index.get(JSON.stringify(key),{}) if key != null else {}
		if match_row.is_empty() and args.get("mode","left") == "inner": continue
		for field: String in match_row:
			if field == right_key: continue
			if row.has(prefix+field): return failure("join_column_collision","Колонка объединения уже существует: "+prefix+field)
			row[prefix+field] = match_row[field]
		if row.size() > MAX_FIELDS: return failure("column_limit","После объединения не более 40 колонок.")
		result.append(row)
	return {"ok":true,"result":{"rows":result,"provenance":{"receipt_id":args.receipt_id,"source":right.get("source","Recorded observation"),"basis":right.get("basis","observed"),"join":"many-to-one "+str(args.get("mode","left"))}}}

static func downsample(rows: Array, args: Dictionary) -> Dictionary:
	var x: String = str(args.get("x","")); var y: String = str(args.get("y","")); var limit: int = clampi(int(args.get("limit",241)),4,1000)
	for row: Dictionary in rows:
		if not Data.number(row.get(x)) or not Data.number(row.get(y)): return failure("sample_numeric_required","Для downsample нужны конечные числовые x и y во всех строках; пропуски нельзя превращать в нули.")
	rows.sort_custom(func(a: Dictionary,b: Dictionary): return a[x] < b[x])
	if rows.size() <= limit: return {"ok":true,"result":{"rows":rows}}
	var picks: Dictionary = {0:true,rows.size()-1:true}
	# Min/max envelope per consecutive X bucket preserves sharp extrema and endpoints.
	var buckets: int = maxi(1,(limit-2)/2)
	for bucket: int in buckets:
		var start: int = 1+int(float(bucket)*(rows.size()-2)/buckets); var end: int = 1+int(float(bucket+1)*(rows.size()-2)/buckets)
		var low := start; var high := start
		for i: int in range(start,end):
			if rows[i][y] < rows[low][y]: low = i
			if rows[i][y] > rows[high][y]: high = i
		picks[low] = true; picks[high] = true
	var indices: Array = picks.keys(); indices.sort(); var result: Array = []
	for i: int in indices: result.append(rows[i])
	return {"ok":true,"result":{"rows":result}}

static func read_page(args: Dictionary, receipts: Array) -> Dictionary:
	var result: Dictionary = receipt_result(str(args.get("receipt_id","")),receipts)
	if not result.get("rows") is Array: return failure("receipt_unavailable","Набор rows не найден в успешных результатах текущей задачи.")
	var offset: int = maxi(0,int(args.get("offset",0))); var limit: int = clampi(int(args.get("limit",50)),1,200)
	var page: Dictionary = result.duplicate(true); page.rows = result.rows.slice(offset,offset+limit)
	page["total"] = result.rows.size(); page["offset"] = offset; page["has_more"] = offset+page.rows.size() < result.rows.size(); page["next_offset"] = offset+page.rows.size()
	return {"ok":true,"result":page}

static func quantile(sorted_values: Array, probability: float) -> Variant:
	if sorted_values.is_empty(): return null
	var at: float = (sorted_values.size()-1)*probability; var lo: int = floori(at); var hi: int = ceili(at)
	return lerpf(sorted_values[lo],sorted_values[hi],at-lo)

static func statistics(input: Dictionary, args: Dictionary) -> Dictionary:
	var fields: Array = args.get("fields",[])
	if fields.is_empty() or fields.size() > 24: return failure("fields_required","Укажите 1..24 числовых поля.")
	var result: Dictionary = input.duplicate(true); result.erase("rows"); result["statistics"] = []; result["rows"] = []
	for field: String in fields:
		var values: Array = []; var invalid := 0
		for row: Dictionary in input.rows:
			if Data.number(row.get(field)): values.append(float(row[field]))
			else: invalid += 1
		values.sort(); var mean: Variant = null
		if not values.is_empty():
			mean = 0.0
			for value: float in values: mean += value/values.size()
		var variance: Variant = null
		if values.size() > 1:
			variance = 0.0
			for value: float in values: variance += pow(value-mean,2)/(values.size()-1)
		var row: Dictionary = {"field":field,"n":values.size(),"missing_or_nonnumeric":invalid,"min":values.min() if not values.is_empty() else null,"q1":quantile(values,0.25),"median":quantile(values,0.5),"q3":quantile(values,0.75),"max":values.max() if not values.is_empty() else null,"mean":mean,"sample_variance":variance}
		result.statistics.append(row); result.rows.append(row.duplicate(true))
	if args.get("correlations",false):
		var matrix: Array = []; var counts: Array = []
		for first: String in fields:
			var line: Array = []; var ns: Array = []
			for second: String in fields:
				var pairs: Array = []
				for row: Dictionary in input.rows:
					if Data.number(row.get(first)) and Data.number(row.get(second)): pairs.append([float(row[first]),float(row[second])])
				var mx := 0.0; var my := 0.0
				for pair: Array in pairs: mx += pair[0]/pairs.size(); my += pair[1]/pairs.size()
				var xx := 0.0; var yy := 0.0; var xy := 0.0
				for pair: Array in pairs: xx += pow(pair[0]-mx,2); yy += pow(pair[1]-my,2); xy += (pair[0]-mx)*(pair[1]-my)
				line.append(clampf(xy/sqrt(xx*yy),-1,1) if pairs.size()>1 and xx>0 and yy>0 else null); ns.append(pairs.size())
			matrix.append(line); counts.append(ns)
		result["correlation"] = {"fields":fields,"matrix":matrix,"pair_counts":counts,"method":"Pearson, pairwise complete finite numeric observations; zero variance or n<2 => null"}
	result["conventions"] = "Quartiles: Hyndman-Fan type 7 (linear interpolation at (n-1)*p). Variance: sample n-1. Missing and nonnumeric values excluded, never replaced by zero."
	return {"ok":true,"result":result}

static func chart(input: Dictionary, args: Dictionary) -> Dictionary:
	var spec: Dictionary = args.get("chart",{}).duplicate(true)
	if spec.is_empty():
		var expected: String = explicit_chart_fields(str(args.get("type","bar")),input)
		if not expected.is_empty():
			var kind: String = str(args.type)
			var reason: String = "Для типа «"+kind+"» нужен явный объект chart: "+expected+". Вызовите charts.describe("+JSON.stringify({"type":kind})+"), затем передайте chart по этой схеме с rows+source или receipt_id, либо полный самостоятельный chart с basis=scenario и source. Одни rows не задают структуру диаграммы; повтор без chart не исправит ошибку."
			var rejected: Dictionary = failure("chart_invalid",reason)
			rejected.result["errors"] = [{"field":"chart","reason":reason}]
			rejected.result["retry_unchanged"] = false
			return rejected
		spec = {"type":args.get("type","bar"),"title":args.get("title","Набор данных")}
		if spec.type == "heatmap" and input.has("correlation"):
			spec.labels = input.correlation.fields; spec.columns = input.correlation.fields; spec.matrix = input.correlation.matrix
		elif spec.type == "boxplot" and input.has("statistics"):
			spec.boxes = []
			for row: Dictionary in input.statistics:
				if row.n > 0: spec.boxes.append({"label":row.field,"min":row.min,"q1":row.q1,"median":row.median,"q3":row.q3,"max":row.max})
		elif spec.type in ["histogram"]:
			spec.samples = {"field":args.get("y_field","")}; spec.bins = args.get("bins",10)
		else:
			var value_fields: Array = args.get("value_fields",[args.get("y_field","")])
			for index: int in value_fields.size():
				var column: Variant = value_fields[index]
				if (args.has("value_fields") or args.has("y_field")) and column is String and not column.is_empty() and not input.rows.any(func(row: Dictionary): return row.has(column)):
					var field: String = "value_fields[%d]" % index if args.has("value_fields") else "y_field"
					var reason: String = "Колонка «"+column.left(160)+"» отсутствует во всех итоговых строках. Проверьте datasets.read и финальную проекцию fields: после группировки она должна включать созданные имена агрегатов."
					var rejected: Dictionary = failure("chart_invalid",reason)
					rejected.result["errors"] = [{"field":field,"reason":reason}]
					return rejected
			var label_field: Variant = args.get("label_field","")
			if not args.has("label_field") and spec.type in ["bar","stacked_bar","pie","donut","column","stacked_column","treemap","radar","waterfall"]:
				label_field = args.get("x_field","")
			spec.labels = {"field":label_field}; spec.series = []
			for field: String in value_fields: spec.series.append({"name":field,"values":{"field":field}})
			if args.has("x_field") and spec.type in ["line","area","scatter","bubble","stacked_area"]: spec.x = {"field":args.x_field}
			if spec.type == "bubble": spec.sizes = {"field":args.get("size_field","")}
	else:
		# Display metadata may be placed beside an explicit template. Inherit only
		# missing keys; invalid-but-present nested values still face strict validation.
		for key: String in ["type","title"]:
			if not spec.has(key) and args.has(key): spec[key] = args[key]
	var expanded: Variant = materialize(spec,input.rows)
	if not expanded is Dictionary: return failure("invalid_chart_mapping","Неверные ссылки на колонки.")
	spec = expanded; spec["source"] = str(input.get("source","Recorded dataset")); spec["basis"] = input.get("basis","observed")
	if args.has("unit"): spec["unit"] = args.unit
	var checked: Dictionary = validate_chart(spec)
	if not checked.ok: return checked
	return {"ok":true,"result":{"chart":checked.result.chart,"source":input.source,"basis":input.basis,"provenance":input.get("provenance",[]),"coverage":input.get("coverage",[]),"original_count":input.get("original_count",input.rows.size()),"selected_count":input.rows.size()}}

## Fully supplied scenario data needs no fictional table. Never infer its basis,
## resolve field references without rows, or label it as an observed receipt.
static func standalone_chart(args: Dictionary) -> Dictionary:
	var raw: Variant = args.get("chart")
	if not raw is Dictionary or raw.is_empty() or raw.get("basis") != "scenario":
		return failure("one_input_required","Укажите ровно один табличный вход: receipt_id, receipt_ids или учебные rows с source. Без таблицы разрешён только полный явный chart с chart.basis=\"scenario\" и непустым source; отсутствие basis не означает scenario.")
	var source: Variant = args.get("source",raw.get("source"))
	if not source is String or source.strip_edges().is_empty():
		return failure("scenario_source_required","Для самостоятельного сценарного chart нужен непустой source в аргументах или chart.source. Наблюдаемые данные требуют receipt_id или receipt_ids.")
	var spec: Dictionary = raw.duplicate(true)
	for key: String in ["type","title"]:
		if not spec.has(key) and args.has(key): spec[key] = args[key]
	spec["source"] = source
	if args.has("unit"): spec["unit"] = args.unit
	if JSON.stringify(spec).to_utf8_buffer().size() > Chart.MAX_BYTES:
		var reason := "Самостоятельный chart превышает лимит блока диаграммы 262144 байта. Сократите данные, сохранив явную структуру и источник."
		var oversized: Dictionary = failure("chart_invalid",reason)
		oversized.result["errors"] = [{"field":"chart","reason":reason}]
		return oversized
	var checked: Dictionary = validate_chart(spec)
	if not checked.ok: return checked
	return {"ok":true,"result":{"chart":checked.result.chart,"source":source,"basis":"scenario","input_kind":"standalone_scenario_chart","provenance":[{"source":source,"basis":"scenario","input_kind":"standalone_scenario_chart"}],"coverage":[]}}

static func validate_chart(spec: Dictionary) -> Dictionary:
	var validated: Dictionary = Chart.validate(spec)
	if validated.is_empty():
		var inspected: Dictionary = preload("res://mods/pax_harness/src/visualization/chart_response.gd").inspect(JSON.stringify(spec))
		var reason: String = str(inspected.get("reason","Результат не удовлетворяет строгой схеме диаграммы; используйте точный шаблон, включая массив series.")).left(500)
		var rejected: Dictionary = failure("chart_invalid",reason+" Запросите charts.describe(type) и исправьте структуру или сопоставление полей. Сохраните отсутствующие наблюдения как null там, где схема это разрешает.")
		rejected.result["errors"] = [{"field":str(inspected.get("field","")).left(160),"reason":reason}]
		return rejected
	return {"ok":true,"result":{"chart":validated}}

## These structures cannot be inferred from common labels/value_fields mapping.
## Return only schema field names, never observations or fabricated sample data.
static func explicit_chart_fields(kind: String, input: Dictionary) -> String:
	match kind:
		"sankey": return "nodes:[{id,label}], links:[{source,target,value}] с положительными потоками"
		"sunburst","tree","icicle": return "nodes:[{id,label,parent?:id,value?:number}]; value только у листьев, у внутренних узлов отсутствует"
		"network": return "nodes:[{id,label}], links:[{source,target}]"
		"gantt": return "tasks:[{id,label,start,end}], dependencies?:[{source,target}]"
		"choropleth": return "regions:[{id,label,value,polygons}] с настоящими нормализованными контурами"
		"cartogram": return "regions:[{id,label,value,center?:[x,y]}]"
		"density","violin","ridgeline": return "groups:[{name,samples:number[]}]"
		"heatmap": return "labels, columns, matrix" if not input.has("correlation") else ""
		"boxplot": return "boxes:[{label,min,q1,median,q3,max}]" if not input.has("statistics") else ""
		"combo": return "labels, series:[{name,kind:bar|line,values:[number|null]}] с обоими видами серий"
		"interval","errorbar": return "labels, series:[{name,values,lower,upper}]"
		"calendar_heatmap": return "days:[{date:YYYY-MM-DD,value:number|null}]"
		"symbol_map": return "nodes:[{id,label,point:[x,y],value?:number}] с реальными нормализованными координатами"
		"flow_map": return "nodes:[{id,label,point:[x,y]}], links:[{source,target,value}] с реальными нормализованными координатами"
		"parallel": return "dimensions:[{label,unit?:text}], rows:[{label,values}]"
		"small_multiples": return "kind:line|bar, labels, panels:[{title,values}]"
	return ""

static func materialize(value: Variant, rows: Array, depth: int = 0) -> Variant:
	if depth > 16: return null
	if value is Dictionary:
		if value.size() == 1 and value.has("field"):
			var result: Array = []
			for row: Dictionary in rows: result.append(row.get(str(value.field)))
			return result
		var result: Dictionary = {}
		for key: String in value: result[key] = materialize(value[key],rows,depth+1)
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(materialize(item,rows,depth+1))
		return result
	return value

static func object_schema(properties: Dictionary, required: Array = []) -> Dictionary:
	return {"type":"object","properties":properties,"required":required,"additionalProperties":false}
static func text_schema(maximum: int = 160) -> Dictionary:
	return {"type":"string","minLength":1,"maxLength":maximum}
static func array_schema(items: Dictionary, maximum: int) -> Dictionary:
	return {"type":"array","items":items,"maxItems":maximum}
static func definition(name: String, description: String, properties: Dictionary, required: Array = []) -> Dictionary:
	return {"name":name,"id":name,"description":description,"arguments_schema":object_schema(properties,required),"mutates_world":false,"handler_kind":"public_game_facade","capability":"bounded_local_observations","after_state":"Read-only derived data with inherited source provenance and explicit sample coverage. No world mutation."}
static func definitions() -> Array:
	var input: Dictionary = {"receipt_id":text_schema(128),"receipt_ids":array_schema(text_schema(128),100),"rows":array_schema({"type":"object","additionalProperties":true},1000),"source":text_schema(500)}
	var fields: Dictionary = array_schema(text_schema(),24)
	var transform_args: Dictionary = input.duplicate(true)
	transform_args.merge({"fields":array_schema(text_schema(),40),"filters":array_schema(object_schema({"field":text_schema(),"op":{"type":"string","enum":["eq","ne","gt","gte","lt","lte","in","contains","missing","present"]},"value":{}},["field","op"]),16),"sort":array_schema(object_schema({"field":text_schema(),"descending":{"type":"boolean"}},["field"]),4),"group_by":array_schema(text_schema(),8),"aggregates":array_schema(object_schema({"field":text_schema(),"op":{"type":"string","enum":["count","sum","mean","min","max"]},"as":text_schema()},["op"]),16),"limit":{"type":"integer","minimum":1,"maximum":20000},"downsample":object_schema({"x":text_schema(),"y":text_schema(),"limit":{"type":"integer","minimum":4,"maximum":1000}},["x","y"]),"join":object_schema({"receipt_id":text_schema(128),"left_key":text_schema(),"right_key":text_schema(),"prefix":text_schema(80),"mode":{"type":"string","enum":["left","inner"]}},["receipt_id","left_key","right_key"])})
	var statistics_args: Dictionary = input.duplicate(true); statistics_args.merge({"fields":fields,"correlations":{"type":"boolean"}})
	var chart_args: Dictionary = input.duplicate(true); chart_args.merge({"chart":{"type":"object","additionalProperties":true},"type":text_schema(80),"title":text_schema(500),"label_field":text_schema(),"value_fields":array_schema(text_schema(),4),"x_field":text_schema(),"y_field":text_schema(),"size_field":text_schema(),"unit":{"type":"string","maxLength":40},"bins":{"type":"integer","minimum":2,"maximum":40}})
	return [definition("datasets.transform","Prepare up to 20000 rows / 300000 cells / 4MB from SAME TASK complete receipts (receipt_id or receipt_ids concatenates pages) OR explicit scenario rows+source. Filter, stable sort, group count/sum/mean/min/max; count(field) counts nonnull values and count without field counts rows; missing numeric observations are excluded, empty aggregates null. fields is the FINAL projection AFTER grouping, aggregation and sampling: include generated aggregate aliases (e.g. revenue_sum), not removed raw input names. Optional many-to-one join rejects duplicate right keys. downsample min/max X-bucket envelope preserves endpoints and extrema; limit is explicit truncation. Registered analytics.query data.rows is supported. Historical SAME CHAT data: first trace.replay(message_id,call_id) or trace.read selecting exactly one successful tool event; then reference that NEW trace receipt. Historical data is never current verification. Cross-chat reads and serialized fragments are not accepted. Full table stays local; metadata and preview only. Read pages on demand.",transform_args),definition("datasets.read","Read one page of a prepared same-task dataset, max200 rows. Does not requery the world or change original dataset. Coverage records whether source was partial.",{"receipt_id":text_schema(128),"offset":{"type":"integer","minimum":0},"limit":{"type":"integer","minimum":1,"maximum":200}},["receipt_id"]),definition("statistics.calculate","Calculate finite numeric counts, missing counts, min/Q1/median/Q3/max, mean, sample variance. Quartiles use Hyndman-Fan type7 linear interpolation. Optional Pearson matrix uses pairwise complete observations and pair_counts; n<2/zero variance => null. Source coverage retained. datasets.chart can display this receipt as heatmap or boxplot.",statistics_args,["fields"]),definition("datasets.chart","Build validated chart from prepared SAME TASK table, OR a complete standalone chart with explicit chart.basis=scenario and nonempty args.source or chart.source; standalone mode needs no rows/receipt, never infers basis, and accepts no unresolved field mappings. Common mapping: type,title,label_field,value_fields (or y_field for one series). Without an explicit chart template, x_field is an alias for category labels ONLY for bar,stacked_bar,pie,donut,column,stacked_column,treemap,radar,waterfall when label_field is absent; present label_field always wins. Numeric x_field is emitted as x ONLY for line,area,scatter,bubble,stacked_area; size_field supplies bubble sizes. Complex types (e.g. sankey,sunburst) REQUIRE a full explicit chart template from charts.describe; type+rows+label_field/value_fields alone is insufficient. For any other chart, pass full chart template from charts.describe: replace any column ARRAY with {field:column_name}, e.g. series:[{name:Output,values:{field:output}}]. For an explicit chart template, only missing type/title inherit supplied top-level type/title; present nested values win and are still strictly validated. Top-level unit keeps its existing precedence. With table input, metadata source/basis always inherited from the dataset; standalone full charts remain explicitly scenario. Statistics receipt supports automatic type=heatmap (correlations) or boxplot. Missing values are never filled; aggregate/filter/downsample to chart limits first. Display returned display_ref unchanged.",chart_args)]
