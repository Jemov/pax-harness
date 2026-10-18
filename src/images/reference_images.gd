extends RefCounted
## Player image pixels use PaxMod storage; no external filesystem access.
const Vision=preload("res://mods/pax_harness/src/transport/vision_payload.gd")
const Png=preload("res://mods/pax_harness/src/images/ui_png.gd")
var owner_mod: Object
func setup(owner: Object) -> void: owner_mod=owner
func import_bytes(bytes: PackedByteArray,title: String="image") -> Dictionary:
	if bytes.size()>20971520: return {"ok":false,"code":"reference.image_too_large"}
	var image:=Image.new(); var error:=image.load_png_from_buffer(bytes)
	if error!=OK: error=image.load_jpg_from_buffer(bytes)
	if error!=OK: error=image.load_webp_from_buffer(bytes)
	if error!=OK: return {"ok":false,"code":"reference.decode_failed"}
	return import_image(image,title)
func import_image(image: Image,title: String="image") -> Dictionary:
	if image.is_empty() or image.get_width()>16384 or image.get_height()>16384: return {"ok":false,"code":"reference.invalid_dimensions"}
	if owner_mod==null: return {"ok":false,"code":"reference.storage_unavailable"}
	image=image.duplicate(); var longest: int=maxi(image.get_width(),image.get_height())
	if longest>Vision.MAX_DIMENSION: image.resize(maxi(1,roundi(float(image.get_width())*Vision.MAX_DIMENSION/longest)),maxi(1,roundi(float(image.get_height())*Vision.MAX_DIMENSION/longest)),Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	var bytes: PackedByteArray=Png.encode(image)
	while bytes.size()>Vision.MAX_BYTES and maxi(image.get_width(),image.get_height())>256:
		image.resize(maxi(1,int(image.get_width()*0.8)),maxi(1,int(image.get_height()*0.8)),Image.INTERPOLATE_LANCZOS); bytes=Png.encode(image)
	if bytes.is_empty() or bytes.size()>Vision.MAX_BYTES: return {"ok":false,"code":"reference.image_too_large"}
	var digest:=HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(bytes)
	var id: String="reference_"+digest.finish().hex_encode()
	var handle: Dictionary={"id":id,"mime_type":"image/png","width":image.get_width(),"height":image.get_height(),"byte_size":bytes.size(),"source":"user_reference","name":title.left(160)}
	owner_mod.save_data(id,{"attachment":handle,"png_base64":Marshalls.raw_to_base64(bytes)})
	if not resolve(handle).get("ok",false): return {"ok":false,"code":"reference.save_failed"}
	return {"ok":true,"attachment":handle}
func resolve(handle: Dictionary) -> Dictionary:
	if owner_mod==null or not Vision.valid_reference(handle) or handle.source!="user_reference" or RegEx.create_from_string("^reference_[a-f0-9]{64}$").search(str(handle.id))==null: return {"ok":false,"code":"vision_invalid_reference"}
	var saved: Variant=owner_mod.load_data(str(handle.id),{})
	if not saved is Dictionary or not saved.get("png_base64") is String or saved.png_base64.length()>ceili(Vision.MAX_BYTES*4.0/3.0)+4: return {"ok":false,"code":"reference.image_unavailable"}
	var bytes: PackedByteArray=Marshalls.base64_to_raw(saved.png_base64)
	var digest:=HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(bytes)
	if bytes.size()!=int(handle.byte_size) or "reference_"+digest.finish().hex_encode()!=handle.id: return {"ok":false,"code":"reference.image_unavailable"}
	return {"ok":true,"bytes":bytes,"mime_type":handle.mime_type,"width":handle.width,"height":handle.height}
func texture(handle: Dictionary) -> Texture2D:
	var result: Dictionary=resolve(handle)
	if not result.ok: return null
	var image:=Image.new()
	if image.load_png_from_buffer(result.bytes)!=OK: return null
	return ImageTexture.create_from_image(image)
