extends RefCounted
## Bounded shared-grid water/province map from the live raster, including mod edits.
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Chart = preload("res://mods/pax_harness/src/visualization/specs/chat_chart.gd")
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")

static func execute(game: Object, args: Dictionary) -> Dictionary:
	if not is_instance_valid(game): return {"ok":false,"code":"charts.inactive_world"}
	var body: String = str(args.get("body",game.home_body()))
	if body != game.home_body() and body not in Sources.native_loaded_maps(game): return {"ok":false,"code":"charts.map_not_loaded","result":{"message":"Open this body's map in the game first, then repeat. This read-only tool does not generate a new planetary map."}}
	if args.get("type","choropleth") != "choropleth": return {"ok":false,"code":"charts.water_requires_choropleth"}
	var bounds: Variant = args.get("bounds")
	if not bounds is Array or bounds.size() != 4: return {"ok":false,"code":"charts.water_bounds_required","result":{"message":"Supply bounds [west,south,east,north] in degrees. These crop the live map; they are not a claimed sea boundary. For named mod waters first use analytics.sources/query and charts.map_sources."}}
	for value: Variant in bounds:
		if not (value is int or value is float) or not is_finite(float(value)): return {"ok":false,"code":"charts.invalid_bounds"}
	if bounds[0] < -180 or bounds[2] > 180 or bounds[1] < -90 or bounds[3] > 90 or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]: return {"ok":false,"code":"charts.invalid_bounds","result":{"message":"Use west < east and south < north. Split a dateline-crossing view into two maps."}}
	var provider: Object = game._prov(body)
	if not is_instance_valid(provider) or provider.map.size() != provider.sh*provider.v_m*2: return {"ok":false,"code":"charts.geometry_unavailable"}
	var left: int = clampi(floori((bounds[0]+180.0)/360.0*provider.sh),0,provider.sh-1)
	var right: int = clampi(ceili((bounds[2]+180.0)/360.0*provider.sh),left+1,provider.sh)
	var top: int = clampi(floori((90.0-bounds[3])/180.0*provider.v_m),0,provider.v_m-1)
	var bottom: int = clampi(ceili((90.0-bounds[1])/180.0*provider.v_m),top+1,provider.v_m)
	var step: int = maxi(1,ceili(maxf(float(right-left)/384.0,float(bottom-top)/256.0)))
	var built: Dictionary = {}
	var aggregate_land := false
	for attempt: int in 5:
		built = raster(provider,Rect2i(left,top,right-left,bottom-top),step,aggregate_land)
		if built.get("code","") == "charts.water_too_many_provinces":
			aggregate_land = true
			built = raster(provider,Rect2i(left,top,right-left,bottom-top),step,true)
		if built.ok: break
		step *= 2
	if not built.ok: return built
	var regions: Array = []
	var ids: Array = built.polygons.keys(); ids.sort()
	# Water last: it remains visible even where a land province has a lake hole.
	ids.erase(0); ids.append(0)
	for id: int in ids:
		if not built.polygons.has(id): continue
		var row: Dictionary = game.province(body,id) if id > 0 else {}
		regions.append({"id":str(id) if id > 0 else "land:context" if id < 0 else "water:viewport","label":str(row.get("name",id)) if id > 0 else L.text("Суша (контекст)") if id < 0 else L.text("Вода в выбранной области"),"kind":"land" if id != 0 else "water","value":null,"polygons":built.polygons[id]})
	if regions.is_empty(): return {"ok":false,"code":"charts.geometry_unavailable"}
	var source: String = L.text("Маска воды и провинции текущей партии · ")+body+", "+game.date_text()+L.text("; выборка по общей сетке, включая изменения модов")
	var aspect: float = float(right-left)/maxi(1,bottom-top)
	var chart: Dictionary = {"body":body,"type":"choropleth","title":args.get("title",L.text("Суша и вода")),"source":source,"regions":regions,"aspect":clampf(aspect,0.05,20.0),"unit":""}
	if Chart.validate(chart).is_empty(): return {"ok":false,"code":"charts.invalid_water_map"}
	return {"ok":true,"result":{"chart":chart,"bounds":bounds,"grid_step_pixels":step,"land_aggregated":aggregate_land,"sampled_cells":built.cells,"water_cells":built.water_cells,"note":"Water/land cover only, not economic metrics or measured sea limits. Blue is live raster water (province ID 0 or water mask >=2). Land has actual province IDs unless land_aggregated=true: wide views merge land into one context layer, with no province identity. Frame edges crop geometry. Pixel-grid sampling is disclosed. No sea ice is treated as land. Named scenario objects are discovered separately through registered mod sources."}}

static func raster(provider: Object, box: Rect2i, step: int, aggregate_land: bool = false) -> Dictionary:
	var polygons: Dictionary = {}; var previous: Dictionary = {}; var rectangles: Array = []
	var cells := 0; var wet := 0; var seen: Dictionary = {}
	for y: int in range(box.position.y,box.end.y,step):
		var current: Dictionary = {}; var runs: Array = []; var last := -2; var start := box.position.x
		for x: int in range(box.position.x,box.end.x,step):
			var at: int = y*provider.sh+x; var id: int = provider.map[at*2]|(provider.map[at*2+1]<<8)
			if at < provider.water.size() and provider.water[at] >= 2: id = 0
			if aggregate_land and id > 0: id = -1
			seen[id] = true
			if seen.size() > 64: return {"ok":false,"code":"charts.water_too_many_provinces"}
			cells += 1
			if id == 0: wet += 1
			if id != last:
				if last != -2: runs.append([last,start,x])
				start = x; last = id
		if last != -2: runs.append([last,start,box.end.x])
		for run: Array in runs:
			var key: String = str(run)
			if previous.has(key):
				var index: int = previous[key]; rectangles[index][4] = mini(box.end.y,y+step); current[key] = index
			else:
				current[key] = rectangles.size(); rectangles.append([run[0],run[1],y,run[2],mini(box.end.y,y+step)])
		previous = current
		if rectangles.size() > 2800: return {"ok":false,"code":"charts.water_geometry_budget"}
	for rect: Array in rectangles:
		var id: int = rect[0]
		if not polygons.has(id): polygons[id] = []
		var x0: float = float(rect[1]-box.position.x)/box.size.x; var x1: float = float(rect[3]-box.position.x)/box.size.x
		var y0: float = float(rect[2]-box.position.y)/box.size.y; var y1: float = float(rect[4]-box.position.y)/box.size.y
		polygons[id].append([[x0,y0],[x1,y0],[x1,y1],[x0,y1]])
	if polygons.size() > 64: return {"ok":false,"code":"charts.water_too_many_provinces"}
	return {"ok":true,"polygons":polygons,"cells":cells,"water_cells":wet}
