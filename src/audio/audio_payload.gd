extends RefCounted
const Wav=preload("res://mods/pax_harness/src/audio/audio_wav.gd")
static func valid(handle: Variant) -> bool:
	if not handle is Dictionary or handle.size()!=6:return false
	return handle.get("id") is String and RegEx.create_from_string("^audio_[a-f0-9]{64}$").search(handle.id)!=null and handle.get("mime_type")=="audio/wav" and handle.get("name") is String and handle.name.length()<=100 and (handle.get("seconds") is float or handle.get("seconds") is int) and is_finite(float(handle.seconds)) and handle.seconds>0 and (handle.get("byte_size") is int or handle.get("byte_size") is float) and handle.byte_size==floorf(float(handle.byte_size)) and handle.byte_size>44 and handle.byte_size<=Wav.MAX_BYTES and handle.seconds<=float(handle.byte_size)/(Wav.RATE*2) and handle.get("source")=="user_audio"
static func contains_audio(query: Array) -> bool:
	if query.size()!=3 or not query[2] is Dictionary:return false
	for field: String in ["messages","contents"]:
		for message: Variant in query[2].get(field,[]):
			if not message is Dictionary:continue
			var blocks: Variant=message.get("content",message.get("parts",[]))
			if not blocks is Array:continue
			for block: Variant in blocks:
				if block is Dictionary and (block.get("type")=="input_audio" or block.get("inlineData",{}).get("mimeType","").begins_with("audio/")):return true
	return false
static func apply(query: Array, handles: Array, resolver: Callable) -> Dictionary:
	if handles.is_empty():return {"ok":true,"query":query}
	if handles.size()!=1 or not valid(handles[0]) or not resolver.is_valid():return {"ok":false,"code":"audio.invalid_attachment"}
	if query.size()!=3 or not query[0] is String or not query[2] is Dictionary:return {"ok":false,"code":"audio.unsupported_transport"}
	var data: Dictionary=resolver.call(handles[0])
	if not data.get("ok",false):return data
	var result: Array=query.duplicate(true);var body: Dictionary=result[2];var encoded: String=Marshalls.raw_to_base64(data.bytes)
	if query[0].ends_with("/chat/completions") and body.get("messages") is Array:
		body.messages.append({"role":"user","content":[{"type":"text","text":"Attached voice recording from the player."},{"type":"input_audio","input_audio":{"data":encoded,"format":"wav"}}]})
	elif (query[0].ends_with(":generateContent") or query[0].ends_with(":streamGenerateContent")) and body.get("contents") is Array:
		body.contents.append({"role":"user","parts":[{"inlineData":{"mimeType":"audio/wav","data":encoded}}]})
	else:return {"ok":false,"code":"audio.unsupported_transport"}
	return {"ok":true,"query":result}
static func unsupported(response: Dictionary) -> bool:
	if not response.has("error"):return false
	var message: String=JSON.stringify(response.error).to_lower()
	for phrase: String in ["does not support audio","doesn't support audio","audio input is not supported","unsupported_audio","input_audio is not supported","unsupported content type: input_audio","audio content is not supported","only supports text input","not support input_audio","invalid content type: input_audio"]:
		if phrase in message:return true
	return "input_audio" in message and ("not supported" in message or "unsupported" in message or "invalid value" in message)
