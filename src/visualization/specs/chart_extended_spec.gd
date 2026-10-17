extends RefCounted
## Bounded declarative schemas. Coordinates must come from game/map data, never inferred.
const Strategy = preload("res://mods/pax_harness/src/visualization/specs/chart_strategy_spec.gd")
const TYPES := ["combo","interval","errorbar","calendar_heatmap","dumbbell","slope","bump","symbol_map","flow_map","tree","icicle","parallel","small_multiples"]
const COMMON := ["type","title","source","basis","unit","x_label","y_label"]
const SCHEMAS := {
 "combo":{"fields":["labels","series"],"rules":"One shared physical unit and scale. series: 1–4 {name,kind:bar|line,values:[number|null],unit?:same unit}. At least one bar and one line. Equal label/value counts, null is missing."},
 "interval":{"fields":["labels","series"],"rules":"1–4 series {name,values,lower,upper}; lower <= central <= upper. Equal lengths; missing observation is null in all three arrays. Band is supplied uncertainty, not automatically a confidence interval."},
 "errorbar":{"fields":["labels","series"],"rules":"Same schema as interval. Supplied lower/upper bounds; do not invent statistical uncertainty."},
 "calendar_heatmap":{"fields":["days"],"rules":"days: 1–366 unique {date:YYYY-MM-DD,value:number|null}. Real Gregorian dates; span <=366 days; omitted dates are missing, never zero. Monday-first calendar."},
 "dumbbell":{"fields":["labels","series"],"rules":"Exactly two named series {name,values:[number|null]}, equal labels (<=60), same unit. Missing endpoints are not connected."},
 "slope":{"fields":["labels","series"],"rules":"Exactly two named series {name,values:[number|null]}; labels identify compared entities, series names identify the two periods."},
 "bump":{"fields":["labels","series"],"rules":"labels: 2–24 ordered periods; 1–12 named series {name,values:[positive integer rank|null]}. Rank 1 is top; ties permitted, missing ranks break paths."},
 "symbol_map":{"fields":["nodes","regions","body","aspect"],"rules":"nodes <=128 {id,label,point:[normalized x,y],value?:nonnegative,region_id?:actual province ID}. Symbol area proportional to value, no fabricated coordinates. Optional regions: actual {id,label,value?,center?:[normalized x,y],polygons:[[[x,y],...]]}."},
 "flow_map":{"fields":["nodes","links","regions","body","aspect"],"rules":"symbol_map nodes plus <=256 links {source:node ID,target:node ID,value:positive number}. Directional supplied geographical routes; width proportional to sqrt(value); no invented coordinates."},
 "tree":{"fields":["nodes"],"rules":"Same rooted hierarchy as sunburst: <=128 {id,label,parent?:id,value?:number}. Exactly one root; leaf values >=0, internal values omitted; depth <=8; positive total."},
 "icicle":{"fields":["nodes"],"rules":"Same rooted leaf-value hierarchy as sunburst; rectangle width is sum of descendant leaf values, each level shares the same total."},
 "parallel":{"fields":["dimensions","rows"],"rules":"2–10 dimensions {label,unit?:text,min?:number,max?:number}; <=60 rows {label,values:[number|null]}. Each dimension uses its own explicitly labeled scale; values must fit supplied bounds. Missing values break paths."},
 "small_multiples":{"fields":["labels","panels","kind"],"rules":"kind line|bar; 1–12 panels {title,values:[number|null]}, common labels <=60, one common physical unit. All panels use the same global numeric scale. No nested charts."}
}
static func finite(v: Variant) -> bool: return Strategy.number(v)
static func text(v: Variant, cap: int = 160) -> bool: return Strategy.text(v,cap)
static func fields(v: Dictionary, allowed: Array) -> bool: return Strategy.fields(v,allowed)
static func nullable(v: Variant) -> bool: return v == null or finite(v)
static func labels(v: Variant, minimum: int = 1, maximum: int = 60) -> bool:
 if not v is Array or v.size() < minimum or v.size() > maximum: return false
 for label: Variant in v:
  if not text(label): return false
 return true
static func values(v: Variant, count: int) -> bool:
 if not v is Array or v.size() != count: return false
 for n: Variant in v:
  if not nullable(n): return false
 return true
static func point(v: Variant) -> bool:
 return v is Array and v.size() == 2 and finite(v[0]) and finite(v[1]) and v[0] >= 0 and v[0] <= 1 and v[1] >= 0 and v[1] <= 1
const INVALID_DAY := -9999999
static func date_day(v: Variant) -> int:
 if not v is String or v.length() != 10 or v[4] != "-" or v[7] != "-": return INVALID_DAY
 var bits: PackedStringArray = v.split("-")
 if bits.size() != 3 or not bits[0].is_valid_int() or not bits[1].is_valid_int() or not bits[2].is_valid_int(): return INVALID_DAY
 var y := int(bits[0]); var m := int(bits[1]); var d := int(bits[2])
 if y < 1 or y > 9999 or m < 1 or m > 12 or d < 1: return INVALID_DAY
 var months := [31,29 if y%4 == 0 and (y%100 != 0 or y%400 == 0) else 28,31,30,31,30,31,31,30,31,30,31]
 if d > months[m-1] or v != "%04d-%02d-%02d"%[y,m,d]: return INVALID_DAY
 return int(floor(Time.get_unix_time_from_datetime_dict({"year":y,"month":m,"day":d,"hour":0,"minute":0,"second":0})/86400.0))
static func validate(v: Dictionary) -> Dictionary:
 var kind: String = str(v.get("type",""))
 if kind not in TYPES or not text(v.get("title"),500) or not text(v.get("source"),500): return {}
 if v.get("basis","observed") not in ["observed","scenario","forecast"]: return {}
 for key: String in ["unit","x_label","y_label"]:
  if not v.get(key,"") is String or str(v.get(key,"")).length() > 80: return {}
 if not fields(v,COMMON+SCHEMAS[kind].fields): return {}
 if kind in ["tree","icicle"]:
  var copy := v.duplicate(true); copy.type = "sunburst"
  if Strategy.validate(copy).is_empty(): return {}
 elif kind == "calendar_heatmap":
  if not v.get("days") is Array or v.days.is_empty() or v.days.size() > 366: return {}
  var dates := {}; var low := 10000000; var high := -10000000
  for row: Variant in v.days:
   if not row is Dictionary or not fields(row,["date","value"]) or not row.has("value") or not nullable(row.value): return {}
   var day := date_day(row.get("date"))
   if day == INVALID_DAY or dates.has(row.date): return {}
   dates[row.date] = true; low = mini(low,day); high = maxi(high,day)
  if high-low > 365: return {}
 elif kind in ["symbol_map","flow_map"]:
  if not v.get("nodes") is Array or v.nodes.is_empty() or v.nodes.size() > 128: return {}
  if not finite(v.get("aspect",1.6)) or v.get("aspect",1.6) <= 0 or v.get("aspect",1.6) > 20: return {}
  if v.has("body") and not text(v.body): return {}
  var ids := {}; var vertices := 0
  for row: Variant in v.nodes:
   if not row is Dictionary or not fields(row,["id","label","point","value","region_id"]) or not text(row.get("id"),80) or ids.has(row.id) or not text(row.get("label")) or not point(row.get("point")): return {}
   if row.has("value") and (not finite(row.value) or row.value < 0): return {}
   if row.has("region_id") and not text(row.region_id,80): return {}
   ids[row.id] = true
  if kind == "flow_map":
   if not v.get("links") is Array or v.links.is_empty() or v.links.size() > 256: return {}
   for row: Variant in v.links:
    if not row is Dictionary or not fields(row,["source","target","value"]) or not ids.has(row.get("source")) or not ids.has(row.get("target")) or row.source == row.target or not finite(row.get("value")) or row.value <= 0: return {}
  if not v.get("regions",[]) is Array or v.get("regions",[]).size() > 256: return {}
  var region_ids := {}
  for row: Variant in v.get("regions",[]):
   if not row is Dictionary or not fields(row,["id","label","value","polygons","center"]) or not text(row.get("id"),80) or region_ids.has(row.id) or not text(row.get("label")) or not row.get("polygons") is Array or row.polygons.is_empty(): return {}
   if row.has("value") and not nullable(row.value): return {}
   if row.has("center") and not point(row.center): return {}
   region_ids[row.id] = true
   for polygon: Variant in row.polygons:
    if not polygon is Array or polygon.size() < 3 or polygon.size() > 2048: return {}
    vertices += polygon.size()
    if vertices > 20000: return {}
    for p: Variant in polygon:
     if not point(p): return {}
 elif kind == "parallel":
  if not v.get("dimensions") is Array or v.dimensions.size() < 2 or v.dimensions.size() > 10 or not v.get("rows") is Array or v.rows.is_empty() or v.rows.size() > 60: return {}
  for dim: Variant in v.dimensions:
   if not dim is Dictionary or not fields(dim,["label","unit","min","max"]) or not text(dim.get("label")) or not dim.get("unit","") is String or dim.get("unit","").length() > 80: return {}
   for key: String in ["min","max"]:
    if dim.has(key) and not finite(dim[key]): return {}
   if dim.has("min") and dim.has("max") and dim.min >= dim.max: return {}
  for row: Variant in v.rows:
   if not row is Dictionary or not fields(row,["label","values"]) or not text(row.get("label")) or not values(row.get("values"),v.dimensions.size()): return {}
   for i: int in row.values.size():
    if row.values[i] == null: continue
    if row.values[i] < v.dimensions[i].get("min",-INF) or row.values[i] > v.dimensions[i].get("max",INF): return {}
 else:
  if not labels(v.get("labels"),2 if kind == "bump" else 1,24 if kind == "bump" else 60): return {}
  var rows: Variant = v.get("panels") if kind == "small_multiples" else v.get("series")
  if not rows is Array or rows.is_empty() or rows.size() > (12 if kind in ["small_multiples","bump"] else 4): return {}
  if kind in ["dumbbell","slope"] and rows.size() != 2: return {}
  if kind == "small_multiples" and v.get("kind") not in ["line","bar"]: return {}
  var present := false; var bars := false; var lines := false
  for row: Variant in rows:
   var allowed := ["title","values"] if kind == "small_multiples" else ["name","values","lower","upper"] if kind in ["interval","errorbar"] else ["name","values","kind","unit"] if kind == "combo" else ["name","values"]
   if not row is Dictionary or not fields(row,allowed) or not text(row.get("title" if kind == "small_multiples" else "name")) or not values(row.get("values"),v.labels.size()): return {}
   if kind == "combo":
    if row.get("kind") not in ["bar","line"] or row.get("unit",v.get("unit","")) != v.get("unit",""): return {}
    bars = bars or row.kind == "bar"; lines = lines or row.kind == "line"
   if kind in ["interval","errorbar"] and (not values(row.get("lower"),v.labels.size()) or not values(row.get("upper"),v.labels.size())): return {}
   for i: int in row.values.size():
    var n: Variant = row.values[i]
    present = present or n != null
    if kind in ["interval","errorbar"]:
     if n == null:
      if row.lower[i] != null or row.upper[i] != null: return {}
     elif row.lower[i] == null or row.upper[i] == null or row.lower[i] > n or row.upper[i] < n: return {}
    if kind == "bump" and n != null and (n < 1 or n != floorf(n) or n > 1000000): return {}
  if not present or (kind == "combo" and (not bars or not lines)): return {}
 return v.duplicate(true)
static func plain(v: Dictionary) -> String:
 return str(v.title)+"\n"+JSON.stringify(v,"  ")+"\nИсточник: "+str(v.source)

static func example(kind: String) -> Dictionary:
 var base := {"type":kind,"title":"Пример: "+kind,"source":"Учебные данные, не состояние партии","basis":"scenario","unit":"ед."}
 var definitions := {
  "combo":{"labels":["А","Б","В"],"series":[{"name":"Выпуск","kind":"bar","values":[10,20,16]},{"name":"Спрос","kind":"line","values":[12,18,22]}]},
  "interval":{"labels":["1","2","3"],"series":[{"name":"Прогноз","values":[10,15,18],"lower":[8,10,11],"upper":[12,20,25]}]},
  "errorbar":{"labels":["А","Б"],"series":[{"name":"Оценка","values":[10,20],"lower":[8,16],"upper":[12,24]}]},
  "calendar_heatmap":{"days":[{"date":"2026-10-01","value":10},{"date":"2026-10-02","value":null},{"date":"2026-10-03","value":20}]},
  "dumbbell":{"labels":["Север","Юг"],"series":[{"name":"До","values":[10,20]},{"name":"После","values":[15,18]}]},
  "slope":{"labels":["Север","Юг"],"series":[{"name":"До","values":[10,20]},{"name":"После","values":[15,18]}]},
  "bump":{"labels":["Март","Апрель","Май"],"series":[{"name":"Север","values":[1,2,1]},{"name":"Юг","values":[2,1,2]}],"unit":"Место"},
  "symbol_map":{"nodes":[{"id":"a","label":"А","point":[0.2,0.3],"value":10},{"id":"b","label":"Б","point":[0.8,0.7],"value":20}]},
  "flow_map":{"nodes":[{"id":"a","label":"А","point":[0.2,0.3]},{"id":"b","label":"Б","point":[0.8,0.7]}],"links":[{"source":"a","target":"b","value":10}]},
  "tree":{"nodes":[{"id":"root","label":"Страна"},{"id":"a","label":"Север","parent":"root","value":10},{"id":"b","label":"Юг","parent":"root","value":20}]},
  "icicle":{"nodes":[{"id":"root","label":"Страна"},{"id":"a","label":"Север","parent":"root","value":10},{"id":"b","label":"Юг","parent":"root","value":20}]},
  "parallel":{"dimensions":[{"label":"Выпуск","unit":"ед."},{"label":"Население","unit":"чел."}],"rows":[{"label":"Север","values":[20,100]},{"label":"Юг","values":[10,200]}]},
  "small_multiples":{"kind":"line","labels":["Март","Апрель","Май"],"panels":[{"title":"Север","values":[10,20,15]},{"title":"Юг","values":[15,12,18]}]}
 }
 if not definitions.has(kind): return {}
 base.merge(definitions[kind],true)
 return base
