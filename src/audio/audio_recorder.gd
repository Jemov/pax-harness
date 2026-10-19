extends Node
const Wav=preload("res://mods/pax_harness/src/audio/audio_wav.gd")
signal completed(result: Dictionary)
var recording:=false
var level:=0.0
var seconds:=0.0
var _samples:=PackedFloat32Array()
var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _bus:=""
var _rate:=48000
func begin() -> Dictionary:
	process_mode=Node.PROCESS_MODE_ALWAYS
	if recording:return {"ok":false,"code":"audio.recording_busy"}
	if not ProjectSettings.get_setting("audio/driver/enable_input",false):return {"ok":false,"code":"audio.input_disabled"}
	_samples.clear();seconds=0.0;level=0.0;_rate=int(AudioServer.get_mix_rate());_bus="HarnessMic_"+str(get_instance_id())
	AudioServer.add_bus();var index: int=AudioServer.bus_count-1;AudioServer.set_bus_name(index,_bus);AudioServer.set_bus_mute(index,true)
	_capture=AudioEffectCapture.new();_capture.buffer_length=0.25;AudioServer.add_bus_effect(index,_capture)
	_player=AudioStreamPlayer.new();_player.stream=AudioStreamMicrophone.new();_player.bus=_bus;add_child(_player);_player.play();recording=true;set_process(true)
	return {"ok":true}
func _read() -> void:
	if _capture==null:return
	var available: int=_capture.get_frames_available()
	if available<=0:return
	var frames: PackedVector2Array=_capture.get_buffer(available);var energy:=0.0
	for frame: Vector2 in frames:
		if _samples.size()>=_rate*Wav.MAX_SECONDS:break
		var sample: float=(frame.x+frame.y)*0.5;_samples.append(sample);energy+=sample*sample
	if not frames.is_empty():level=sqrt(energy/frames.size())
func _process(delta: float) -> void:
	if not recording:return
	_read();seconds+=delta
	if seconds>=Wav.MAX_SECONDS:stop()
func stop() -> void:
	if not recording:return
	_read();var bytes: PackedByteArray=Wav.encode(_samples,_rate);_cleanup()
	completed.emit(Wav.normalize(bytes))
func cancel() -> void:_cleanup()
func _cleanup() -> void:
	recording=false;level=0.0;set_process(false)
	if is_instance_valid(_player):_player.stop();_player.queue_free()
	_player=null;_capture=null;_samples.clear()
	var index: int=AudioServer.get_bus_index(_bus)
	if index>0:AudioServer.remove_bus(index)
	_bus=""
func _exit_tree() -> void:_cleanup()
