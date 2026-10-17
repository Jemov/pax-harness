extends RefCounted
## Bounded arithmetic for scenario curves; never evaluates scripts or expressions.
const Chart = preload("res://mods/pax_harness/chat_chart.gd")
const Formula = preload("res://mods/pax_harness/chart_formula.gd")

static func execute(args: Dictionary) -> Dictionary:
	if not args.get("parameters",{}) is Dictionary: return {"ok":false,"code":"charts.invalid_parameters"}
	var p: Dictionary = args.get("parameters",{})
	var function: String = str(args.get("function",""))
	var x_values: Array = []
	if args.has("x") == args.has("range"): return {"ok":false,"code":"charts.x_or_range_required","message":"Provide either x or range={min,max,samples}, not both."}
	if args.has("range"):
		var bounds: Variant = args.range
		if not bounds is Dictionary: return {"ok":false,"code":"charts.invalid_range"}
		for key: String in ["min","max"]:
			if not (bounds.get(key) is float or bounds.get(key) is int): return {"ok":false,"code":"charts.invalid_range"}
		var start: float = bounds.min; var end: float = bounds.max
		var samples: int = int(bounds.get("samples",121))
		if not is_finite(start) or not is_finite(end) or start >= end or samples < 2 or samples > 241: return {"ok":false,"code":"charts.invalid_range"}
		for index: int in samples: x_values.append(lerpf(start,end,float(index)/(samples-1)))
	elif args.x is Array: x_values = args.x.duplicate()
	if x_values.size() < 2 or x_values.size() > 241: return {"ok":false,"code":"charts.invalid_points"}
	var formula := Formula.new()
	var formulas: Dictionary = {"parabola":"a*(x-x0)^2+c","hyperbola":"a/(x-x0)+c","sine":"a*sin(b*x+c)+d","cosine":"a*cos(b*x+c)+d","tangent":"a*tan(b*x+c)+d"}
	var calculated: bool = function == "formula" or formulas.has(function)
	if calculated:
		var source: String = str(args.get("formula","")) if function == "formula" else str(formulas[function])
		if not formula.parse(source): return {"ok":false,"code":"charts.formula_syntax","result":{"message":formula.error}}
	var values: Array = []; var labels: Array = []; var actual_x: Array = []; var breaks: Array = []
	var previous := -INF
	var gap := false
	var skipped := 0
	for raw: Variant in x_values:
		if not (raw is float or raw is int) or not is_finite(float(raw)) or absf(float(raw)) > 1.0e9: return {"ok":false,"code":"charts.invalid_x"}
		var x: float = float(raw)
		if x <= previous: return {"ok":false,"code":"charts.x_must_increase"}
		previous = x
		var evaluated: Dictionary = {"ok":true,"value":formula.evaluate(x,p)} if calculated else _legacy_value(function,x,p)
		if not evaluated.ok or not is_finite(float(evaluated.value)) or absf(float(evaluated.value)) > 1.0e15:
			if not calculated and not args.has("range"): return evaluated if not evaluated.ok else {"ok":false,"code":"charts.numeric_overflow"}
			skipped += 1; gap = true
			continue
		if not actual_x.is_empty():
			var continuous: bool = formula.continuous_between(actual_x[-1],x,p) if calculated else not (function == "power" and float(p.get("b",1)) < 0 and actual_x[-1] < 0 and x > 0)
			if gap or not continuous: breaks.append(values.size())
		actual_x.append(x); values.append(evaluated.value); labels.append(Chart.number(x)); gap = false
	if values.size() < 2: return {"ok":false,"code":"charts.no_plottable_points","message":"Fewer than two finite points in this domain. Choose another range or formula."}
	var chart := {"type":"line","title":args.get("title",""),"labels":labels,"x":actual_x,"series":[{"name":args.get("y_label","y"),"values":values}],"unit":args.get("unit",""),"x_label":args.get("x_label","x"),"y_label":args.get("y_label","y"),"source":args.get("source",""),"basis":"scenario","curve":args.get("curve","smooth")}
	if not breaks.is_empty(): chart["breaks"] = breaks
	if Chart.validate(chart).is_empty(): return {"ok":false,"code":"charts.invalid_spec"}
	return {"ok":true,"result":{"chart":chart,"function":function,"formula":str(args.get("formula",formulas.get(function,""))),"parameters":p,"skipped_points":skipped,"segments":breaks.size()+1,"note":"Computed mathematical/scenario curve, not observed game history. Display the returned pax-chart unchanged, including breaks. Undefined/overflowing points are omitted and discontinuities split the line. Explain assumptions when relating the formula to game quantities."}}

static func _legacy_value(function: String, x: float, p: Dictionary) -> Dictionary:
	var y := 0.0
	match function:
		"polynomial":
			var coefficients: Array = p.get("coefficients",[])
			if coefficients.is_empty(): return {"ok":false,"code":"charts.coefficients_required"}
			for index: int in range(coefficients.size()-1,-1,-1): y = y*x+float(coefficients[index])
		"power":
			if x < 0 and not is_equal_approx(float(p.get("b",1)),roundf(float(p.get("b",1)))): return {"ok":false,"code":"charts.power_domain"}
			y = float(p.get("a",1))*pow(x,float(p.get("b",1)))+float(p.get("c",0))
		"exponential": y = float(p.get("a",1))*exp(float(p.get("b",1))*x)+float(p.get("c",0))
		"logarithmic":
			if x <= 0: return {"ok":false,"code":"charts.log_domain"}
			y = float(p.get("a",1))*log(x)+float(p.get("b",0))
		"logistic":
			var z: float = float(p.get("k",1))*(x-float(p.get("x0",0)))
			y = float(p.get("L",1))*(1/(1+exp(-z)) if z >= 0 else exp(z)/(1+exp(z)))
		_: return {"ok":false,"code":"charts.unknown_function"}
	return {"ok":true,"value":y}
