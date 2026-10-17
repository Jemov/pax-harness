extends RefCounted
## Pure generated-artifact reference validation, shared by runtime and presentation.
const MAX_BYTES := 4*1024*1024
const MAX_DIMENSION := 1600

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("id") is String or RegEx.create_from_string("^[a-f0-9]{32}$").search(value.id) == null: return {}
	if value.get("source") != "game_configured_generator" or value.get("persistent") != true: return {}
	if value.get("mime_type") != "image/png": return {}
	for key: String in ["width","height","byte_size"]:
		var number: Variant = value.get(key)
		if (not number is int and not number is float) or number is bool or not is_finite(float(number)) or number != floorf(float(number)): return {}
	if value.width < 1 or value.height < 1 or value.width > MAX_DIMENSION or value.height > MAX_DIMENSION or value.byte_size < 16 or value.byte_size > MAX_BYTES: return {}
	if not value.get("sha256") is String or RegEx.create_from_string("^[a-f0-9]{64}$").search(value.sha256) == null: return {}
	if not value.get("title") is String or value.title.length() > 160: return {}
	return {"id":value.id,"mime_type":"image/png","width":int(value.width),"height":int(value.height),"byte_size":int(value.byte_size),"sha256":value.sha256,"title":value.title,"source":"game_configured_generator","persistent":true}

