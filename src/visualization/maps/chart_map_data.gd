extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Shared raster-grid contours: neighboring provinces keep identical boundaries.
const Sources = preload("res://mods/pax_harness/src/data/world_sources.gd")
const Chart = preload("res://mods/pax_harness/src/visualization/specs/chat_chart.gd")
static var _cache: Dictionary = {}
static func available(game: Object) -> bool:
	return is_instance_valid(game) and game.has_method("_prov") and game.has_method("provinces_of")
static func execute(game: Object, args: Dictionary) -> Dictionary:
	if args.get("type","choropleth") not in ["choropleth","cartogram"]: return {"ok":false,"code":"charts.route_provider_required","result":{"message":"Symbol/flow maps need recorded points/routes from an explicit map provider or a sourced datasets.chart template. Native province totals contain no measured routes."}}
	if not Sources.active(game): return {"ok":false,"code":"charts.inactive_world"}
	var body: String = str(args.get("body",game.home_body()))
	if body != game.home_body(): return {"ok":false,"code":"charts.home_body_only","result":{"message":"No new body map is generated. Select the currently loaded home body."}}
	var country: String = str(args.get("country",game.country()))
	var owned: Array = game.provinces_of(body,country)
	var ids: Array = args.get("province_ids",owned).duplicate()
	if ids.is_empty() or ids.size() > 64: return {"ok":false,"code":"charts.select_up_to_64_provinces","result":{"available_count":owned.size(),"message":"Select 1..64 actual province IDs from analytics.read/provinces.read."}}
	for id: Variant in ids:
		if not (id is int or id is float) or float(id) != floorf(float(id)) or ids.count(id) != 1: return {"ok":false,"code":"charts.invalid_or_duplicate_province"}
		if int(id) not in owned: return {"ok":false,"code":"charts.province_not_in_country"}
	ids.sort()
	var provider: Object = game._prov(body)
	if not is_instance_valid(provider): return {"ok":false,"code":"charts.geometry_unavailable"}
	var contours: bool = args.get("type","choropleth") == "choropleth"
	var key: String = str(provider.get_instance_id())+":"+str(ids)+":"+str(contours)
	if not _cache.has(key):
		var geometry: Dictionary = geometry(provider,ids,contours)
		if not geometry.get("ok",false): return geometry
		if _cache.size() >= 8: _cache.clear()
		_cache[key] = geometry
	var geometry: Dictionary = _cache[key]
	var metric: String = str(args.get("metric","area_km2"))
	if country != game.country() and metric in ["enterprise_count","enterprise_levels"]: return {"ok":false,"code":"charts.foreign_economy_unverified"}
	var custom: Dictionary = args.get("values",{})
	if metric == "custom" and str(args.get("source","")).strip_edges().is_empty(): return {"ok":false,"code":"charts.custom_source_required"}
	var counts: Dictionary = {}; var levels: Dictionary = {}
	for row: Dictionary in game.economy(body).get("enterprises",[]):
		var id: int = int(row.get("province",0)); counts[id] = int(counts.get(id,0))+1; levels[id] = float(levels.get(id,0))+float(row.get("levels",0))
	var regions: Array = []
	for id: int in ids:
		var row: Dictionary = game.province(body,id)
		var value: Variant = row.get("area_km2") if metric == "area_km2" else counts.get(id,0) if metric == "enterprise_count" else levels.get(id,0) if metric == "enterprise_levels" else custom.get(str(id))
		regions.append({"id":str(id),"label":str(row.get("name",id)),"value":value,"polygons":geometry.regions[str(id)].polygons,"center":geometry.regions[str(id)].center})
	var source: String = str(args.get("source",L.text("Текущие данные провинций · ")+country+", "+game.date_text()))+(L.text("; границы по общей сетке карты игры") if contours else L.text("; схематичные плитки по положениям провинций"))
	var chart: Dictionary = {"body":body,"type":args.get("type","choropleth"),"title":args.get("title",L.text("Провинции · ")+country),"source":source,"regions":regions,"aspect":geometry.aspect,"unit":L.text("км²") if metric == "area_km2" else L.text("предприятий") if metric == "enterprise_count" else L.text("уровни") if metric == "enterprise_levels" else str(args.get("unit",""))}
	if Chart.validate(chart).is_empty(): return {"ok":false,"code":"charts.invalid_map_data"}
	return {"ok":true,"result":{"chart":chart,"metric":metric,"country":country,"date":game.date_text(),"selected_count":ids.size(),"country_province_count":owned.size(),"geometry":"native province raster with shared-grid borders; equal-tile cartogram is schematic, not area-preserving geography","note":"Display returned chart unchanged. ONLY selected regions are drawn; unselected provinces are omitted, NOT gray. Within the selected set gray means no supplied value, not zero."}}

static func geometry(provider: Object, ids: Array, contours: bool = true) -> Dictionary:
	var width: int = provider.sh; var height: int = provider.v_m; var bytes: PackedByteArray = provider.map
	if width <= 0 or height <= 0 or width*height > 32000000 or bytes.size() != width*height*2: return {"ok":false,"code":"charts.unsupported_map_format"}
	var boxes: Dictionary = {}; var selected: Dictionary = {}
	for id: int in ids:
		selected[id] = true
		var point: Vector2 = provider.label_point(id)*Vector2(width,height)
		boxes[id] = Rect2i(Vector2i(point),Vector2i.ONE)
	# Do not sample each province on a different grid or simplify its edge in
	# isolation: both produce cracks/overlaps along a shared border.
	var stride := 1
	for y: int in range(0,height,stride):
		for x: int in range(0,width,stride):
			var index: int = (y*width+x)*2; var id: int = bytes[index]|(bytes[index+1]<<8)
			if selected.has(id): boxes[id] = boxes[id].expand(Vector2i(x,y))
	var overall := Rect2i()
	for id: int in ids:
		boxes[id] = boxes[id].grow(stride+1).intersection(Rect2i(0,0,width,height))
		overall = boxes[id] if overall.size == Vector2i.ZERO else overall.merge(boxes[id])
	var cells := 0
	for box: Rect2i in boxes.values(): cells += box.get_area()
	if contours and cells > 8000000: return {"ok":false,"code":"charts.map_geometry_too_large","result":{"message":"Choose a smaller province subset; exact shared borders exceed the raster work budget."}}
	var regions: Dictionary = {}; var vertices := 0
	for id: int in ids:
		var box: Rect2i = boxes[id]
		var center: Vector2 = ((provider.label_point(id)*Vector2(width,height)-Vector2(overall.position))/Vector2(overall.size)).clamp(Vector2.ZERO,Vector2.ONE)
		if not contours:
			regions[str(id)] = {"polygons":[],"center":[center.x,center.y]}
			continue
		var step := 1
		var dimensions := Vector2i(ceili(float(box.size.x)/step),ceili(float(box.size.y)/step))
		var bitmap := BitMap.new(); bitmap.create(dimensions)
		for y: int in dimensions.y:
			for x: int in dimensions.x:
				var actual := Vector2i(mini(width-1,box.position.x+x*step),mini(height-1,box.position.y+y*step))
				var index: int = (actual.y*width+actual.x)*2
				if (bytes[index]|(bytes[index+1]<<8)) == id: bitmap.set_bit(x,y,true)
		var polygons: Array = []
		var epsilon := 0.0
		var raw: Array = bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO,dimensions),epsilon)
		var total := 0
		for polygon: PackedVector2Array in raw: total += polygon.size()
		if total > 12000: return {"ok":false,"code":"charts.map_geometry_too_large","result":{"message":"Choose fewer provinces; exact shared borders exceed the vertex budget."}}
		for polygon: PackedVector2Array in raw:
			if polygon.size() > 2048: return {"ok":false,"code":"charts.map_geometry_too_large","result":{"message":"A contour exceeds 2048 vertices. Use a schematic cartogram or a smaller map."}}
			if polygon.size() < 3 or Geometry2D.triangulate_polygon(polygon).is_empty(): continue
			var points: Array = []
			for point: Vector2 in polygon:
				var normalized: Vector2 = ((Vector2(box.position)+point*step-Vector2(overall.position))/Vector2(overall.size)).clamp(Vector2.ZERO,Vector2.ONE)
				points.append([snappedf(normalized.x,0.00001),snappedf(normalized.y,0.00001)])
			vertices += points.size(); polygons.append(points)
		if polygons.is_empty(): return {"ok":false,"code":"charts.province_contour_unavailable","result":{"province":id,"message":"This province is too small or its raster contour is unavailable. Select another subset."}}
		regions[str(id)] = {"polygons":polygons,"center":[center.x,center.y]}
	if vertices > 12000: return {"ok":false,"code":"charts.map_geometry_too_large","result":{"vertices":vertices,"message":"Choose fewer provinces for this chart."}}
	return {"ok":true,"regions":regions,"aspect":float(overall.size.x)/maxi(1,overall.size.y)}
