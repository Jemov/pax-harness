extends RefCounted
## Exact sent PNGs for the player's transcript; separate from expiring input grants.
const MAX_BYTES:=2097152
const MAX_TOTAL:=268435456
const MANIFEST:="screen_images"
var owner_mod: Object
var items: Dictionary={}
var _textures: Dictionary={}
func setup(owner: Object) -> void:
	owner_mod=owner
	if owner!=null and owner.has_method("load_data"):
		var saved: Variant=owner.load_data(MANIFEST,{})
		if saved is Dictionary:
			for id: Variant in saved:
				var row: Variant=saved[id]
				if id is String and RegEx.create_from_string("^screen_[a-f0-9]{32}$").search(id)!=null and row is Dictionary and row.get("id")==id and (row.get("width") is int or row.get("width") is float) and (row.get("height") is int or row.get("height") is float) and row.width>0 and row.width<=1600 and row.height>0 and row.height<=1600 and (row.get("byte_size") is int or row.get("byte_size") is float) and row.byte_size>0 and row.byte_size<=MAX_BYTES and row.get("sha256") is String:items[id]=row
func retain(bytes: PackedByteArray, width: int, height: int) -> Dictionary:
	if owner_mod==null or not owner_mod.has_method("save_data") or bytes.is_empty() or bytes.size()>MAX_BYTES: return {}
	var id: String="screen_"+Crypto.new().generate_random_bytes(16).hex_encode()
	var used:=0
	for value: Dictionary in items.values(): used+=int(value.get("byte_size",0))
	if used+bytes.size()>MAX_TOTAL: return {}
	var descriptor: Dictionary={"id":id,"width":width,"height":height,"byte_size":bytes.size(),"sha256":digest(bytes),"observed":false}
	owner_mod.save_data(id,{"descriptor":descriptor,"png_base64":Marshalls.raw_to_base64(bytes)})
	items[id]=descriptor
	if not resolve(descriptor).get("ok",false):items.erase(id);return {}
	owner_mod.save_data(MANIFEST,items)
	return descriptor.duplicate(true)
func mark_observed(descriptor: Dictionary) -> void:
	var id: String=str(descriptor.get("id",""))
	if not items.has(id) or items[id].get("observed",false): return
	items[id]["observed"]=true;owner_mod.save_data(MANIFEST,items)
func resolve(descriptor: Dictionary) -> Dictionary:
	var id: String=str(descriptor.get("id",""))
	if RegEx.create_from_string("^screen_[a-f0-9]{32}$").search(id)==null or not items.has(id): return {"ok":false}
	if not _textures.has(id):
		var saved: Variant=owner_mod.load_data(id,{})
		if not saved is Dictionary or not saved.get("png_base64") is String or saved.png_base64.length()>ceili(MAX_BYTES*4.0/3.0)+4: return {"ok":false}
		var bytes: PackedByteArray=Marshalls.base64_to_raw(saved.png_base64)
		if bytes.size()!=int(items[id].byte_size) or digest(bytes)!=items[id].sha256: return {"ok":false}
		if bytes.size()<33 or bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]):return {"ok":false}
		var width_: int=(int(bytes[16])<<24)|(int(bytes[17])<<16)|(int(bytes[18])<<8)|int(bytes[19])
		var height_: int=(int(bytes[20])<<24)|(int(bytes[21])<<16)|(int(bytes[22])<<8)|int(bytes[23])
		if width_!=int(items[id].width) or height_!=int(items[id].height):return {"ok":false}
		var image:=Image.new()
		if image.load_png_from_buffer(bytes)!=OK or image.get_width()!=items[id].width or image.get_height()!=items[id].height: return {"ok":false}
		if _textures.size()>=4: _textures.erase(_textures.keys()[0])
		_textures[id]=ImageTexture.create_from_image(image)
	return {"ok":true,"texture":_textures[id],"descriptor":items[id].duplicate(true)}
static func digest(bytes: PackedByteArray) -> String:
	var hash_:=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes);return hash_.finish().hex_encode()
