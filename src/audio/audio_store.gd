extends RefCounted
const Wav=preload("res://mods/pax_harness/src/audio/audio_wav.gd")
const Payload=preload("res://mods/pax_harness/src/audio/audio_payload.gd")
var owner_mod: Object
func setup(owner: Object) -> void:owner_mod=owner
func import_bytes(bytes: PackedByteArray, name_: String="Voice message") -> Dictionary:
	var normalized: Dictionary=Wav.normalize(bytes)
	if not normalized.ok:return normalized
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(normalized.bytes)
	var id: String="audio_"+digest.finish().hex_encode()
	var handle: Dictionary={"id":id,"mime_type":"audio/wav","byte_size":normalized.bytes.size(),"seconds":normalized.seconds,"name":name_.left(100),"source":"user_audio"}
	owner_mod.save_data(id,{"attachment":handle,"wav_base64":Marshalls.raw_to_base64(normalized.bytes)})
	return {"ok":true,"attachment":handle} if resolve(handle).get("ok",false) else {"ok":false,"code":"audio.save_failed"}
func resolve(handle: Dictionary) -> Dictionary:
	if not Payload.valid(handle):return {"ok":false,"code":"audio.invalid_attachment"}
	var saved: Variant=owner_mod.load_data(handle.id,{})
	if not saved is Dictionary or not saved.get("attachment") is Dictionary or saved.attachment.get("id")!=handle.id or not saved.get("wav_base64") is String or saved.wav_base64.length()>2800000:return {"ok":false,"code":"audio.unavailable"}
	var bytes: PackedByteArray=Marshalls.base64_to_raw(saved.wav_base64);var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
	if bytes.size()!=handle.byte_size or "audio_"+digest.finish().hex_encode()!=handle.id or not Wav.inspect(bytes).ok:return {"ok":false,"code":"audio.invalid_attachment"}
	return {"ok":true,"bytes":bytes}
