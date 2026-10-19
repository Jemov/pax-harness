extends Node
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const Recorder=preload("res://mods/pax_harness/src/audio/audio_recorder.gd")
const Wav=preload("res://mods/pax_harness/src/audio/audio_wav.gd")
var ui: Node
var recorder: Node
var row: HFlowContainer
var notice: Label
var level: ProgressBar
var player: AudioStreamPlayer
var _chat:=""
var _signature:=""
var _mic_state:=""
var _error: Dictionary={}
var _locale:=""
func setup(value: Node, fields: VBoxContainer) -> void:
	ui=value;recorder=Recorder.new();add_child(recorder);recorder.completed.connect(_recorded)
	row=HFlowContainer.new();row.name="VoiceAttachment";fields.add_child(row);fields.move_child(row,0)
	notice=Label.new();notice.name="VoiceInputNotice";notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.add_theme_color_override("font_color",ui.QUIET);notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;fields.add_child(notice);fields.move_child(notice,1);notice.hide()
	level=ProgressBar.new();level.name="VoiceInputLevel";level.show_percentage=false;level.custom_minimum_size=Vector2(80,5);fields.add_child(level);fields.move_child(level,2);level.hide()
	player=AudioStreamPlayer.new();add_child(player);ui.store.changed.connect(sync);sync()
func audio() -> Array:return ui.store.current().get("draft_audio",[]).duplicate(true)
func recording() -> bool:return is_instance_valid(recorder) and recorder.recording
func toggle() -> void:
	if recording():recorder.stop();return
	if ui.owner_mod.chat_busy():return
	_chat=ui.store.selected;_error.clear()
	var result: Dictionary=recorder.begin()
	if not result.ok:show_error(result)
	else:notice.text=L.text("Запись голоса… Нажмите микрофон ещё раз, чтобы завершить.");notice.show();level.show();ui._update_send_state()
func _recorded(result: Dictionary) -> void:
	level.hide()
	if not result.get("ok",false):show_error(result);ui._update_send_state();return
	if _chat!=ui.store.selected:return
	var saved: Dictionary=ui.owner_mod.audio_service.store.import_bytes(result.bytes,L.text("Голосовое сообщение"))
	if not saved.ok:show_error(saved);return
	add_reference(saved.attachment)
func add_reference(handle: Dictionary) -> bool:
	if not ui.owner_mod.audio_service.store.resolve(handle).get("ok",false):return false
	ui.store.current()["draft_audio"]=[handle.duplicate(true)];notice.hide();ui.store.changed.emit();ui._update_send_state();return true
func show_error(result: Dictionary) -> void:
	_error=result.duplicate(true)
	var code: String=str(result.get("code","audio.failed"))
	var text: String=L.text("Не удалось записать голос. Проверьте микрофон в Настройки → Голос.")
	if code=="audio.empty_recording":text=L.text("В записи не слышно голоса. Проверьте выбранный микрофон и доступ к нему.")
	elif code=="audio.input_disabled":text=L.text("Ввод с микрофона выключен в игре. Проверьте Настройки → Голос и разрешение микрофона в Windows.")
	elif code.begins_with("audio.asr"):text=L.text("Распознавание голоса недоступно. Настройте его в Настройки → Голос. Запись сохранена, её можно отправить повторно.")
	elif code=="audio.no_speech":text=L.text("Не удалось разобрать речь. Прослушайте запись или запишите сообщение заново.")
	notice.text=text+("\n"+str(result.reason) if result.get("reason","")!="" else "");notice.show()
func sync() -> void:
	if not is_instance_valid(ui) or not is_instance_valid(row):return
	if recording() and ui.store.selected!=_chat:cancel()
	var clips: Array=audio();var signature: String=JSON.stringify([clips,L.language()])
	if L.language()!=_locale:
		_locale=L.language()
		if recording():notice.text=L.text("Запись голоса… Нажмите микрофон ещё раз, чтобы завершить.")
		elif not _error.is_empty():show_error(_error)
	if signature==_signature:return
	_signature=signature
	for child: Node in row.get_children():row.remove_child(child);child.queue_free()
	for handle: Dictionary in clips:
		var play: Button=ui._button(L.text("▶ Голосовое сообщение")+(L.text(" · %.1f с")%float(handle.seconds)),func():play_clip(ui.owner_mod,player,handle));row.add_child(play)
		play.name="PlayVoiceDraft";play.tooltip_text=L.text("Прослушать запись")
		var remove: Button=ui._button("×",func():player.stop();ui.store.current()["draft_audio"]=[];ui.store.changed.emit();ui._update_send_state());remove.tooltip_text=L.text("Убрать запись");row.add_child(remove)
	row.visible=not clips.is_empty()
static func play_clip(owner: Node, output: AudioStreamPlayer, handle: Dictionary) -> void:
	if output.playing:output.stop();return
	var resolved: Dictionary=owner.audio_service.store.resolve(handle)
	if resolved.get("ok",false):output.stream=Wav.stream(resolved.bytes);output.play()
static func message_preview(ui_: Node,parent: Node,handles: Array,route: String) -> void:
	for handle: Dictionary in handles:
		var output:=AudioStreamPlayer.new();parent.add_child(output)
		var play: Button=ui_._button(L.text("▶ Голосовое сообщение")+(L.text(" · %.1f с")%float(handle.get("seconds",0))),func():play_clip(ui_.owner_mod,output,handle));play.name="PlayVoiceMessage";parent.add_child(play)
	if route!="":parent.add_child(ui_._label(L.text("Аудио передано модели напрямую") if route=="native" else L.text("Голос распознан и передан текстом"),12,ui_.QUIET))
func _process(_delta: float) -> void:
	if is_instance_valid(ui) and ui.surface.visible:sync()
	if recording():
		level.value=clampf(recorder.level*500,0,100)
		if ui.store.selected!=_chat or not ui.surface.visible:cancel()
	var state: String=str(recording())+str(ui.owner_mod.chat_busy())
	if is_instance_valid(ui.mic_button) and state!=_mic_state:
		_mic_state=state
		ui.mic_button.icon=ui.Icons.make("stop" if recording() else "mic",Color("#d5979e") if recording() else ui.QUIET)
		ui.mic_button.disabled=ui.owner_mod.chat_busy() and not recording()
func cancel() -> void:
	_error.clear()
	if is_instance_valid(recorder):recorder.cancel()
	if is_instance_valid(player):player.stop()
	if is_instance_valid(level):level.hide()
	if is_instance_valid(notice):notice.hide()
func _exit_tree() -> void:cancel()
