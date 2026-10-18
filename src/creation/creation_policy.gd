extends RefCounted
## Declarative content only. No scripts, URLs, paths or model-controlled callbacks.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const KINDS := ["object","resource","panel","warp_link","warp_transit","surface","resource_style","object_damage"]
const SHAPES := ["box","sphere","cylinder","torus","line"]
static func definitions() -> Array:
	var result: Array = []
	for item: Array in [
		["creation.capabilities","Read supported declarative content, voxel model format, resource classes and actual limitations. No creation or map generation.",{},[]],
		["creation.list","Read this campaign's created objects/resources/panels/warp links and pending player-review projects. Never implies a pending project was applied.",{},[]],
		["creation.propose","ONLY when the current player explicitly asks to add/create content: prepare ONE declarative project for PLAYER REVIEW. This does NOT create anything in the world. The player must click Apply in its review card; there is NO apply tool. Object model is bounded voxel JSON, resource starts at zero, panel is labelled rows only, warp_link joins two existing approved warp_gate objects, warp_transit reroutes one existing ship through an approved link. No scripts or arbitrary UI/code. First read creation.capabilities for exact formats. Never propose unsolicited content or claim a pending project was created.",{"kind":{"type":"string","enum":KINDS},"definition":{"type":"object","additionalProperties":true}},["kind","definition"]]
	]:
		result.append({"name":item[0],"id":item[0],"description":item[1],"arguments_schema":{"type":"object","properties":item[2],"required":item[3],"additionalProperties":false},"mutates_world":false,"handler_kind":"public_game_facade","capability":"player_reviewed_declarative_content","after_state":"Actual campaign content or pending proposal. No world change until the player applies a specific proposal in the UI."})
	return result

static func keys(value: Dictionary, allowed: Array, required: Array = []) -> bool:
	return required.all(func(key: String): return value.has(key)) and value.keys().all(func(key: Variant): return key in allowed)
static func identifier(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z][a-z0-9_]{0,47}$").search(value) != null
static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func label(value: Variant) -> bool:
	return value is Dictionary and keys(value,["ru","en"],["ru","en"]) and [value.ru,value.en].all(func(s: Variant): return s is String and s.strip_edges().length()>0 and s.length()<=160)
static func vector(value: Variant, count: int, low: float, high: float) -> bool:
	return value is Array and value.size()==count and value.all(func(v: Variant): return number(v,low,high))
static func icon(value: Variant) -> bool:
	if value is String: return value in ["gate","station","crystal","dust","panel"]
	if not value is Dictionary or not keys(value,["rows","palette"],["rows","palette"]): return false
	if not value.rows is Array or value.rows.size()<4 or value.rows.size()>16 or not palette(value.palette): return false
	var width: int = str(value.rows[0]).length()
	if width<4 or width>16: return false
	for row: Variant in value.rows:
		if not row is String or row.length()!=width: return false
		for c: String in row:
			if not c in "0123456789abcdef" or c.hex_to_int()>value.palette.size(): return false
	return true
static func color(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^#[0-9a-fA-F]{6}$").search(value)!=null
static func palette(value: Variant) -> bool:
	return value is Array and value.size()>0 and value.size()<=15 and value.all(func(c: Variant): return c is String and RegEx.create_from_string("^#[0-9a-fA-F]{6}$").search(c)!=null)
static func model(value: Variant) -> bool:
	if not value is Dictionary or not keys(value,["size","palette","shapes","voxels"],["size","palette"]): return false
	if not vector(value.size,3,1,64) or not value.size.all(func(v: Variant): return float(v)==floorf(float(v))) or not palette(value.palette): return false
	var shapes: Variant = value.get("shapes",[]); var voxels: Variant = value.get("voxels",[])
	if not shapes is Array or shapes.size()>128 or not voxels is Array or voxels.size()>4096 or (shapes.is_empty() and voxels.is_empty()): return false
	for shape: Variant in shapes:
		if not shape is Dictionary or not keys(shape,["type","center","radius","tube","height","axis","from","to","width","color"],["type","color"]) or shape.type not in SHAPES or not number(shape.color,0,value.palette.size()) or float(shape.color)!=floorf(float(shape.color)): return false
		for field: String in ["center","from","to"]:
			if shape.has(field) and not vector(shape[field],3,0,64): return false
		for field: String in ["radius","tube","height","width"]:
			if shape.has(field) and not number(shape[field],0.1,64): return false
		if shape.has("axis") and shape.axis not in ["x","y","z"]: return false
		if shape.type in ["box","line"] and not shape.has_all(["from","to"]): return false
		if shape.type in ["sphere","cylinder","torus"] and not shape.has_all(["center","radius"]): return false
		if shape.type=="torus" and not shape.has("tube"): return false
		if shape.type=="cylinder" and not shape.has("height"): return false
	for voxel: Variant in voxels:
		if not vector(voxel,4,0,64) or voxel[3]>value.palette.size() or voxel[0]>=value.size[0] or voxel[1]>=value.size[1] or voxel[2]>=value.size[2] or not voxel.all(func(v: Variant): return float(v)==floorf(float(v))): return false
	return true

static func validate(kind: String, definition: Variant) -> Dictionary:
	if kind not in KINDS or not definition is Dictionary or not Data.plain(definition) or JSON.stringify(definition).length()>65536: return {"ok":false,"code":"creation.invalid_definition"}
	var d: Dictionary = definition
	var ok := false
	match kind:
		"object":
			ok = keys(d,["id","name","body","model","icon","longitude","latitude","altitude_km","size_km","behavior","destructible"],["id","name","body","model","icon","longitude","latitude","altitude_km","size_km"])
			ok = ok and (not d.has("destructible") or d.destructible is bool)
			ok = ok and identifier(d.get("id")) and label(d.get("name")) and d.get("body") is String and d.body.length()<=160 and model(d.get("model")) and icon(d.get("icon")) and number(d.get("longitude"),-180,180) and number(d.get("latitude"),-90,90) and number(d.get("altitude_km"),0,1e9) and number(d.get("size_km"),0.001,1e7) and d.get("behavior","decoration") in ["decoration","warp_gate"]
		"resource":
			ok = keys(d,["id","name","body","goods_class","unit","price","icon","text_color"],["id","name","body","goods_class","unit","price","icon"])
			ok = ok and identifier(d.get("id")) and label(d.get("name")) and d.get("body") is String and d.get("goods_class") is String and d.get("unit") is String and d.unit.length()<=40 and number(d.get("price"),0,1e12) and icon(d.get("icon")) and (not d.has("text_color") or color(d.text_color))
		"resource_style":
			ok = keys(d,["resource_id","text_color"],["resource_id","text_color"]) and identifier(d.get("resource_id")) and (d.text_color==null or color(d.text_color))
		"object_damage":
			ok = keys(d,["object_id","center","radius"],["object_id","center","radius"]) and identifier(d.get("object_id")) and vector(d.get("center"),3,0,64) and number(d.get("radius"),0.25,16)
		"panel":
			ok = keys(d,["id","name","target_id","rows"],["id","name","target_id","rows"]) and identifier(d.get("id")) and label(d.get("name")) and identifier(d.get("target_id")) and d.get("rows") is Array and d.rows.size()>0 and d.rows.size()<=20
			if ok:
				for row: Variant in d.rows:
					if not row is Dictionary or not keys(row,["label","value","resource_id","body"],["label"]) or not label(row.label): ok=false; break
					if row.has("resource_id"):
						if not identifier(row.resource_id) or not row.get("body") is String or row.has("value"): ok=false; break
					elif not row.get("value") is String or row.value.length()>1000: ok=false; break
		"warp_link":
			ok = keys(d,["id","name","from_id","to_id","days"],["id","name","from_id","to_id","days"]) and identifier(d.get("id")) and label(d.get("name")) and identifier(d.get("from_id")) and identifier(d.get("to_id")) and d.from_id!=d.to_id and number(d.get("days"),1,36500) and float(d.days)==floorf(float(d.days))
		"surface":
			ok = keys(d,["id","name","body","altitude_km","provinces_count","climate"],["id","name","body","altitude_km","provinces_count","climate"]) and identifier(d.get("id")) and label(d.get("name")) and d.get("body") is String and number(d.get("altitude_km"),100,1e8) and number(d.get("provinces_count"),4,40) and float(d.provinces_count)==floorf(float(d.provinces_count)) and d.get("climate") is Dictionary
			if ok:
				ok = keys(d.climate,["temperature","water","biomass","radiation","atmosphere","urban","magnetic"],["temperature","water","biomass","radiation","atmosphere","urban","magnetic"]) and d.climate.values().all(func(v: Variant): return number(v,0,1)) and float(d.climate.urban)==0.0
		"warp_transit":
			ok = keys(d,["link_id","ship_id"],["link_id","ship_id"]) and identifier(d.get("link_id")) and number(d.get("ship_id"),1,2147483647) and float(d.ship_id)==floorf(float(d.ship_id))
	return {"ok":true,"definition":d.duplicate(true)} if ok else {"ok":false,"code":"creation.invalid_"+kind+"_definition"}
