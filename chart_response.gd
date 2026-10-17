extends RefCounted
## Presentation validation only: never invent observations or execute chart data.
const Chart = preload("res://mods/pax_harness/chat_chart.gd")

static func failure(code: String, reason: String, field: String = "") -> Dictionary:
	return {"ok":false,"code":code,"reason":reason,"field":field,"spec":{},"normalized":false}

static func inspect(raw: String, receipts: Array = []) -> Dictionary:
	if raw.to_utf8_buffer().size() > Chart.MAX_BYTES: return failure("charts.too_large","Слишком большой блок диаграммы.")
	var json := JSON.new()
	if json.parse(raw) != OK: return failure("charts.invalid_json","Ошибка JSON, строка %d: %s" % [json.get_error_line()+1,json.get_error_message().left(180)])
	var value: Variant = json.data
	if value is Dictionary and value.size() == 1 and value.has("tool_call_id"):
		var id: Variant = value.tool_call_id
		if id is String and RegEx.create_from_string("^[A-Za-z0-9_.:-]{1,128}$").search(id) != null:
			for receipt: Dictionary in receipts:
				if receipt.get("kind","tool") != "tool" or receipt.get("id",receipt.get("call_id")) != id: continue
				if receipt.get("status") != "complete" or receipt.get("name") not in ["charts.function","charts.map","datasets.chart"]: continue
				var spec: Dictionary = Chart.validate(receipt.get("result",{}).get("chart",{}))
				if not spec.is_empty(): return {"ok":true,"spec":spec,"normalized":false}
		return failure("charts.invalid_reference","Не найден готовый результат инструмента для этой диаграммы.","tool_call_id")
	var spec: Dictionary = Chart.validate(value)
	if not spec.is_empty(): return {"ok":true,"spec":spec,"normalized":false}
	# A singleton object and an array containing that same object are unambiguous.
	# Accept ONLY if the complete strict schema then passes; do not coerce values.
	if value is Dictionary and value.get("series") is Dictionary:
		var candidate: Dictionary = value.duplicate(true)
		candidate.series = [candidate.series]
		spec = Chart.validate(candidate)
		if not spec.is_empty(): return {"ok":true,"spec":spec,"normalized":true}
	if not value is Dictionary: return failure("charts.invalid_spec","Данные диаграммы должны быть объектом JSON.")
	if value.get("type") not in Chart.TYPES and value.get("type") not in Chart.Extra.TYPES:
		return failure("charts.invalid_spec","Неизвестный или отсутствующий тип диаграммы.","type")
	for key: String in ["title","source"]:
		if not value.get(key) is String or str(value[key]).strip_edges().is_empty():
			return failure("charts.invalid_spec","Отсутствует заголовок или источник данных: "+key+".",key)
	if value.type in Chart.Extra.Extended.TYPES:
		# These fields are optional in the actual schema; missing unit is not an error.
		for key: String in ["unit","x_label","y_label"]:
			if not value.get(key,"") is String or str(value.get(key,"")).length() > 80:
				return failure("charts.invalid_spec","Поле "+key+" должно быть строкой длиной не более 80 символов.",key)
	var label_error: Dictionary = _label_diagnostic(value)
	if not label_error.is_empty(): return label_error
	if value.type == "combo":
		var diagnosed: Dictionary = _combo_diagnostic(value)
		if not diagnosed.is_empty(): return diagnosed
	if value.has("series"):
		if not value.series is Array: return failure("charts.invalid_spec","Поле series должно быть массивом объектов; проверьте также остальные поля диаграммы.","series")
		for i: int in value.series.size():
			var series: Variant = value.series[i]
			if not series is Dictionary or not series.get("values") is Array: return failure("charts.invalid_spec","В каждой серии нужен массив числовых значений values.","series[%d].values" % i)
			if value.get("labels") is Array and series.values.size() != value.labels.size():
				return failure("charts.invalid_spec","Количество значений серии (%d) не совпадает с количеством подписей (%d)." % [series.values.size(),value.labels.size()],"series[%d].values" % i)
	return failure("charts.invalid_spec","Данные не соответствуют выбранному типу диаграммы. Проверьте обязательные поля, числовые значения и структуру связей через charts.describe.")

static func _label_diagnostic(value: Dictionary) -> Dictionary:
	var base_labels: bool = value.type in Chart.TYPES
	var string_labels: bool = value.type in ["column","stacked_column","scatter","bubble","heatmap","treemap","radar","waterfall","stacked_area","combo","interval","errorbar","dumbbell","slope","bump","small_multiples"]
	if not base_labels and not string_labels: return {}
	var mapping_hint := " Проверьте label_field или явное сопоставление chart.labels с колонкой подписей."
	if not value.get("labels") is Array or value.labels.is_empty():
		return failure("charts.invalid_spec","Поле labels должно быть непустым массивом подписей."+mapping_hint,"labels")
	for index: int in value.labels.size():
		var label: Variant = value.labels[index]
		# Basic charts already support finite numeric ticks. Unlike the strict
		# extra schemas, their existing string rule does not trim whitespace.
		if base_labels:
			if (label is int or label is float) and is_finite(float(label)): continue
			if label is String and not label.is_empty() and label.length() <= 160: continue
			return failure("charts.invalid_spec","Подпись должна быть непустой строкой до 160 символов или конечным числом; null не является подписью."+mapping_hint,"labels[%d]"%index)
		if not Chart.Extra.text(label):
			return failure("charts.invalid_spec","Подпись должна быть непустой строкой длиной не более 160 символов; null не является подписью."+mapping_hint,"labels[%d]"%index)
	return {}

static func _combo_diagnostic(value: Dictionary) -> Dictionary:
	# Diagnostics run only AFTER strict rejection, using the same schema predicates.
	# No acceptance, normalization or observation values change here.
	var schema: Script = Chart.Extra.Extended
	if not value.get("labels") is Array or value.labels.is_empty() or value.labels.size() > 60:
		return failure("charts.invalid_spec","Для combo поле labels должно содержать от 1 до 60 непустых строковых подписей.","labels")
	for i: int in value.labels.size():
		if not schema.text(value.labels[i]):
			return failure("charts.invalid_spec","Подпись должна быть непустой строкой длиной не более 160 символов. Проверьте label_field или явное сопоставление chart.labels с колонкой подписей.","labels[%d]"%i)
	if not value.get("series") is Array: return {}
	if value.series.is_empty() or value.series.size() > 4:
		return failure("charts.invalid_spec","Для combo нужен массив от 1 до 4 серий, включающий kind=bar и kind=line.","series")
	var bars := false; var lines := false; var observed := false
	for i: int in value.series.size():
		var row: Variant = value.series[i]
		if not row is Dictionary: return failure("charts.invalid_spec","Серия должна быть объектом с полями name, kind и values.","series[%d]"%i)
		if not schema.text(row.get("name")): return failure("charts.invalid_spec","Имя серии должно быть непустой строкой длиной не более 160 символов.","series[%d].name"%i)
		if row.get("kind") not in ["bar","line"]:
			return failure("charts.invalid_spec","Для каждой серии combo явно задайте kind: bar или line. Нужен явный шаблон chart из charts.describe(type=combo); value_fields не задаёт виды серий.","series[%d].kind"%i)
		bars = bars or row.kind == "bar"; lines = lines or row.kind == "line"
		if row.get("unit",value.get("unit","")) != value.get("unit",""):
			return failure("charts.invalid_spec","Все серии combo должны использовать общую unit диаграммы; независимые шкалы разных единиц не поддерживаются.","series[%d].unit"%i)
		if not row.get("values") is Array: return {}
		if row.values.size() != value.labels.size():
			return failure("charts.invalid_spec","Количество значений серии (%d) не совпадает с количеством подписей (%d)."%[row.values.size(),value.labels.size()],"series[%d].values"%i)
		for j: int in row.values.size():
			if not schema.nullable(row.values[j]):
				return failure("charts.invalid_spec","Значение combo должно быть конечным числом в пределах ±1e15 или null для отсутствующего наблюдения.","series[%d].values[%d]"%[i,j])
			observed = observed or row.values[j] != null
		for key: Variant in row:
			if key not in ["name","kind","values","unit"]: return failure("charts.invalid_spec","Неизвестное поле серии combo; проверьте шаблон charts.describe(type=combo).","series[%d].%s"%[i,str(key).left(80)])
	if not bars or not lines: return failure("charts.invalid_spec","Диаграмма combo должна включать хотя бы одну серию kind=bar и одну kind=line.","series")
	if not observed: return failure("charts.invalid_spec","Во всех сериях отсутствуют наблюдения. Запросите доступные данные или сообщите об их отсутствии; не заменяйте null вымышленными значениями.","series")
	for key: Variant in value:
		if key not in schema.COMMON+schema.SCHEMAS.combo.fields: return failure("charts.invalid_spec","Поле не поддерживается схемой combo. Используйте явный шаблон charts.describe(type=combo).",str(key).left(160))
	return {}

static func fences(text: String) -> Array:
	var lines: PackedStringArray = text.split("\n")
	var result: Array = []; var inside := false; var start := -1; var offset := 0; var content := 0
	for line: String in lines:
		var marker: String = line.strip_edges()
		if not inside and marker.begins_with("```"):
			inside = true
			if marker == "```pax-chart": start = offset; content = offset+line.length()+1
		elif inside and marker == "```":
			if start >= 0:
				result.append({"start":start,"end":offset+line.length(),"raw":text.substr(content,maxi(0,offset-content)),"closed":true})
			inside = false; start = -1
		offset += line.length()+1
	if inside and start >= 0: result.append({"start":start,"end":text.length(),"raw":text.substr(mini(content,text.length())),"closed":false})
	return result

static func validate_message(markdown: String, receipts: Array = []) -> Dictionary:
	var text: String = markdown.replace("\r\n","\n")
	var blocks: Array = fences(text); var errors: Array = []; var normalized := 0
	# Replace from the end so offsets remain valid; ordinary quoted code is skipped.
	for index: int in range(blocks.size()-1,-1,-1):
		var block: Dictionary = blocks[index]
		var checked: Dictionary = inspect(block.raw,receipts) if block.closed else failure("charts.unclosed_fence","Не закрыт блок pax-chart: добавьте строку ```.")
		if not checked.ok:
			errors.push_front({"chart":index+1,"code":checked.code,"field":checked.field,"reason":checked.reason})
		elif checked.normalized:
			text = text.left(block.start)+"```pax-chart\n"+JSON.stringify(checked.spec)+"\n```"+text.substr(block.end)
			normalized += 1
	return {"ok":errors.is_empty(),"message":text,"errors":errors.slice(0,8),"normalized":normalized}
