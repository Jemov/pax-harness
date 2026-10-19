extends Node
## Uses the game's configured recognizer; no executable, path or credential handling.
const Wav=preload("res://mods/pax_harness/src/audio/audio_wav.gd")
signal completed
var result: Dictionary={}
var finished:=false
var _native: Node
var _started:=0
var _connections: Dictionary={}
var _restored:=false
var _read: Dictionary={}
var _position:=0
var _text:=""
func begin(game: RefCounted, bytes: PackedByteArray) -> void:
	var original: Variant=game.main.get("hearing") if game!=null else null
	if not is_instance_valid(original) or not original.has_method("stop_m") or not original.has_method("ready_m"):_finish({"ok":false,"code":"audio.asr_unavailable"});return
	if original.writing or original.recognizing:_finish({"ok":false,"code":"audio.asr_busy"});return
	if not original.ready_m():_finish({"ok":false,"code":"audio.asr_unavailable","reason":str(original.why_not_ready())});return
	var read: Dictionary=Wav.inspect(bytes)
	if not read.ok:_finish(read);return
	_native=original;_read=read
	# Preserve native consumers while this explicitly submitted recording is owned
	# by Harness. They must not write its words into a hidden stock chat or order.
	for signal_: String in ["recognized","failed"]:
		_connections[signal_]=_native.get_signal_connection_list(signal_)
		for row: Dictionary in _connections[signal_]:_native.disconnect(signal_,row.callable)
	_native.recognized.connect(_recognized);_native.failed.connect(_failed)
	_next_chunk()
func _sample(frame: int) -> float:
	var value: float=float(_read.pcm.decode_s16(frame*2*_read.channels))/32768.0
	if _read.channels==2:value=(value+float(_read.pcm.decode_s16(frame*4+2))/32768.0)/2
	return value
func _next_chunk() -> void:
	if finished:return
	var frames: int=_read.pcm.size()/(_read.channels*2)
	var first: int=_position;var last: int=first
	var voiced:=false
	# The game recognizer owns short microphone jobs. Feed all of a long clip
	# sequentially, with overlap; skip silence without discarding stored audio.
	while _position<frames:
		first=_position;last=mini(frames,first+int(_read.rate)*20)
		_position=last if last==frames else last-int(_read.rate)/2
		var voice_first:=last;var voice_last:=first
		for frame: int in range(first,last):
			if absf(_sample(frame))>=0.0005:voice_first=mini(voice_first,frame);voice_last=frame+1
		if voice_first==last:continue
		first=maxi(first,voice_first-int(_read.rate)/4);last=mini(last,voice_last+int(_read.rate)/4)
		voiced=true
		break
	if not voiced:
		_finish({"ok":not _text.is_empty(),"text":_text,"code":"audio.no_speech" if _text.is_empty() else ""});_restore.call_deferred();return
	_native.begin()
	if not _native.writing:_finish({"ok":false,"code":"audio.asr_unavailable","reason":str(_native.why_not_ready())});_restore.call_deferred();return
	# Feed an owned recognizer the same mono mix-rate buffer its recorder uses.
	# Its stop method performs resampling, temporary-file handling and recognition.
	var rate: int=int(AudioServer.get_mix_rate());var samples:=PackedFloat32Array();samples.resize(int(float(last-first)*rate/_read.rate))
	for i: int in samples.size():
		samples[i]=_sample(mini(last-1,first+int(float(i)*_read.rate/rate)))
	_native.set("_buffer",samples);_started=Time.get_ticks_msec();_native.stop_m()
func _process(_delta: float) -> void:
	if finished:
		if not is_instance_valid(_native) or not _native.recognizing:_restore()
		return
	if _started>0 and Time.get_ticks_msec()-_started>120000:_finish({"ok":false,"code":"audio.asr_timeout"})
func cancel() -> void:_finish({"ok":false,"code":"cancelled"})
func _finish(value: Dictionary) -> void:
	if finished:return
	result=value;finished=true;completed.emit()
func _recognized(text: String) -> void:
	if finished:_restore.call_deferred();return
	var words: PackedStringArray=text.strip_edges().split(" ",false)
	var prior: PackedStringArray=_text.split(" ",false);var overlap:=0
	for count: int in range(1,mini(12,mini(prior.size(),words.size()))+1):
		if " ".join(prior.slice(prior.size()-count)).to_lower()==" ".join(words.slice(0,count)).to_lower():overlap=count
	var extra: String=" ".join(words.slice(overlap))
	if not extra.is_empty():_text+=(" " if not _text.is_empty() else "")+extra
	_next_chunk.call_deferred()
func _failed(why: String) -> void:
	_finish({"ok":false,"code":"audio.asr_failed","reason":why});_restore.call_deferred()
func _restore() -> void:
	if _restored:return
	_restored=true
	if is_instance_valid(_native):
		if _native.recognized.is_connected(_recognized):_native.recognized.disconnect(_recognized)
		if _native.failed.is_connected(_failed):_native.failed.disconnect(_failed)
		for signal_: String in _connections:
			for row: Dictionary in _connections[signal_]:
				if row.callable.is_valid() and not _native.is_connected(signal_,row.callable):_native.connect(signal_,row.callable,int(row.flags))
	_connections.clear();_native=null
func _exit_tree() -> void:_restore()
