extends SceneTree
const Wav=preload("res://mods/pax_harness/src/audio/audio_wav.gd")
const Store=preload("res://mods/pax_harness/src/audio/audio_store.gd")
const Payload=preload("res://mods/pax_harness/src/audio/audio_payload.gd")
const Service=preload("res://mods/pax_harness/src/audio/audio_service.gd")
const Asr=preload("res://mods/pax_harness/src/audio/native_asr.gd")
const Catalog=preload("res://mods/pax_harness/src/transport/provider_catalog.gd")
const Protocol=preload("res://mods/pax_harness/src/transport/provider_protocol.gd")
const ChatStore=preload("res://mods/pax_harness/src/chat/chat_store.gd")
const Recorder=preload("res://mods/pax_harness/src/audio/audio_recorder.gd")
class Provider extends Node:
	var model:="future-audio-model"
	var base_url:="https://audio.invalid/v1"
class Hearing extends Node:
	signal recognized(text: String)
	signal failed(why: String)
	var writing:=false
	var recognizing:=false
	var available:=true
	var _buffer:=PackedFloat32Array()
	var calls:=0
	var consumers:=0
	var initialized:=false
	func ready_m() -> bool:return available
	func why_not_ready() -> String:return "test recognizer unavailable"
	func begin() -> void:initialized=true;writing=true
	func stop_m() -> void:
		assert(initialized,"Native ASR must initialize its recorder before stopping")
		calls+=1;writing=false;recognizing=true
	func finish(text: String) -> void:recognizing=false;recognized.emit(text)
	func consumer(_text: String) -> void:consumers+=1
class World extends Node:
	var hearing: Node
	var provider: Node
class Game extends RefCounted:
	var main: Node
class Router extends RefCounted:
	var record: Dictionary={}
	func _image_record(_channel: String) -> Dictionary:return record
class Owner extends Node:
	var _source_generation:=1
	var _game: RefCounted
	var _router:=Router.new()
	var audio_service: Node
	var chat_stream: Node
	var saved: Dictionary={}
	var caps: Dictionary={}
	var asks: Array=[]
	var usage: Array=[]
	var result: Dictionary={}
	func save_data(key: String, value: Variant) -> void:saved[key]=JSON.parse_string(JSON.stringify(value))
	func load_data(key: String, fallback: Variant) -> Variant:return saved.get(key,fallback)
	func vision_context() -> Dictionary:return {"base":_game.main.provider.base_url,"model":_game.main.provider.model,"provider_id":_game.main.provider.get_instance_id(),"world_generation":_source_generation}
	func _provider_capabilities(_provider: Node) -> Dictionary:return caps
	func ask_ai(channel: String, prompt: String, data: Dictionary, done: Callable, options: Dictionary) -> bool:asks.append({"channel":channel,"prompt":prompt,"data":data,"done":done,"options":options});return true
	func _audio_intake_answer(response: Dictionary, channel: String) -> void:audio_service.receive(response,channel)
	func _chat_usage(target: Dictionary, request: Dictionary) -> void:usage.append({"target":target,"request":request})
	func begin(target: Dictionary) -> void:result=await audio_service.prepare(target)
var checks:=0
var errors: Array=[]
func check(value: bool, label_: String) -> void:
	checks+=1
	if not value:errors.append(label_);print("FAIL "+label_)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var samples:=PackedFloat32Array();samples.resize(16000)
	for i: int in samples.size():samples[i]=sin(float(i)*0.08)*0.2
	var bytes: PackedByteArray=Wav.encode(samples,16000);var parsed: Dictionary=Wav.inspect(bytes)
	check(parsed.ok and parsed.rate==16000 and parsed.channels==1 and parsed.seconds==1,"real mono PCM WAV encoding")
	check(Wav.stream(bytes)!=null and Wav.stream(bytes).get_length()==1.0,"playable recording")
	check(Wav.normalize(bytes).ok,"normalized voiced clip")
	var silent:=PackedFloat32Array();silent.resize(16000);check(not Wav.normalize(Wav.encode(silent,16000)).ok,"silence cannot become an instruction")
	var damaged: PackedByteArray=bytes.duplicate();damaged.encode_u32(4,99);check(not Wav.inspect(damaged).ok,"RIFF lengths checked")
	damaged=bytes.duplicate();damaged.encode_u16(34,8);check(not Wav.inspect(damaged).ok,"unsupported PCM rejected")
	check(not Wav.inspect("not audio".to_utf8_buffer()).ok,"non-WAV data rejected")
	var owner:=Owner.new();root.add_child(owner);var world:=World.new();owner.add_child(world);world.provider=Provider.new();world.add_child(world.provider);world.hearing=Hearing.new();world.add_child(world.hearing);world.hearing.recognized.connect(world.hearing.consumer)
	var game:=Game.new();game.main=world;owner._game=game
	var service:=Service.new();owner.add_child(service);owner.audio_service=service;service.setup(owner)
	var imported: Dictionary=service.store.import_bytes(bytes,"voice");check(imported.ok,"audio persists through JSON numeric round trip")
	var long_samples:=PackedFloat32Array();long_samples.resize(71*Wav.RATE);long_samples.fill(0.1);long_samples[-1]=0.7
	var recorder:=Recorder.new();root.add_child(recorder);recorder.set_process(false);recorder.recording=true;recorder._rate=Wav.RATE;recorder._samples=long_samples
	var recordings: Array=[];recorder.completed.connect(func(value: Dictionary):recordings.append(value))
	recorder._process(71.0)
	check(recorder.recording and recordings.is_empty(),"recording continues past 30 seconds without automatic completion")
	recorder.stop()
	check(not recorder.recording and recordings.size()==1 and recordings[0].ok,"only explicit Stop completes a long recording")
	var long_read: Dictionary=Wav.inspect(recordings[0].bytes)
	check(long_read.ok and long_read.seconds==71.0 and long_read.pcm.decode_s16(long_read.pcm.size()-2)>22000,"long recording retains final audio instead of truncating at 30 seconds")
	var long_saved: Dictionary=service.store.import_bytes(recordings[0].bytes,"long voice")
	check(long_saved.ok and long_saved.attachment.byte_size>2*1024*1024 and service.store.resolve(long_saved.attachment).ok,"long WAV survives previous attachment-size limit and JSON persistence")
	var long_query: Array=["https://audio.invalid/v1/chat/completions",[],{"model":"future-audio-model","messages":[{"role":"user","content":"long voice"}],"response_format":{"type":"json_object"}}]
	var long_applied: Dictionary=Payload.apply(long_query,[long_saved.attachment],service.store.resolve)
	var long_recovered: Dictionary=Protocol.recover(long_applied.query,400,JSON.stringify({"error":{"message":"response_format is not supported","param":"response_format"}}).to_utf8_buffer())
	check(long_applied.ok and not long_recovered.is_empty() and Payload.contains_audio(long_recovered.query),"native transport and format repair preserve audio beyond the old base64-size limit")
	recorder.queue_free()
	var handle: Dictionary=JSON.parse_string(JSON.stringify(imported.attachment));check(Payload.valid(handle) and service.store.resolve(handle).ok,"saved handle survives restart")
	check(not JSON.stringify(handle).contains("base64") and not JSON.stringify(handle).contains("RIFF"),"history metadata contains no WAV bytes")
	var bad: Dictionary=handle.duplicate();bad.id="../../file";check(not service.store.resolve(bad).ok,"attachment cannot name a filesystem path")
	var query: Array=["https://audio.invalid/v1/chat/completions",[],{"model":"future-audio-model","messages":[{"role":"user","content":"ORIGINAL TEXT"}]}]
	var applied: Dictionary=Payload.apply(query,[handle],service.store.resolve)
	check(applied.ok and Payload.contains_audio(applied.query) and not Payload.contains_audio(query),"native audio reaches Chat Completions without changing original text")
	check(applied.query[2].messages[-1].content[-1].input_audio.format=="wav","WAV input format")
	var retry: Array=applied.query.duplicate(true);retry[2]["response_format"]={"type":"json_object"}
	var recovered: Dictionary=Protocol.recover(retry,400,JSON.stringify({"error":{"message":"response_format is not supported","param":"response_format"}}).to_utf8_buffer())
	check(not recovered.is_empty() and Payload.contains_audio(recovered.query),"format compatibility repair preserves native WAV")
	var gemini: Array=["https://google.invalid/v1beta/models/future:generateContent",[],{"contents":[{"role":"user","parts":[{"text":"ORIGINAL TEXT"}]}]}]
	check(Payload.apply(gemini,[handle],service.store.resolve).ok and Payload.contains_audio(Payload.apply(gemini,[handle],service.store.resolve).query),"native Gemini inlineData audio")
	check(not Payload.apply(["https://audio.invalid/v1/messages",[],{"messages":[]}],[handle],service.store.resolve).ok,"unsupported transport does not invent audio schema")
	check(Payload.unsupported({"error":{"message":"This model does not support audio input"}}) and not Payload.unsupported({"error":{"message":"rate limit"}}),"only explicit modality rejection is cached")
	var target: Dictionary={"chat_id":"qa","message_id":"answer","audio":[handle]};owner.begin(target);await process_frame
	var channel: String=service.pending.keys()[0]
	check(owner.asks.size()==1 and owner.asks[0].options.max_tokens==Service.OUTPUT_BUDGET,"unknown capability tries the selected model through SDK")
	check(service.apply_query(world.provider,query,channel).ok,"intake uses actual WAV bytes")
	service.response(channel,200,JSON.stringify({"usage":{"prompt_tokens":20,"completion_tokens":10}}).to_utf8_buffer());service.record_usage({"channel":channel,"usage":{"prompt_tokens":999}})
	check(owner.usage.size()==1 and owner.usage[0].request.usage.prompt_tokens==20,"intake usage recorded once")
	service.receive({"text":"spoken request"},channel);await process_frame
	check(owner.result.ok and owner.result.native and owner.result.text=="spoken request","native decoding result retained for agent context")
	check(not service.apply_query(world.provider,query,channel).ok,"expired intake cannot resend audio")
	owner.caps={"audio_input":false};owner.result={};owner.begin(target);await process_frame
	check(world.hearing.calls==1 and world.hearing.recognizing and owner.asks.size()==1,"declared text-only model goes directly to game's recognizer")
	world.hearing.finish("recognized words");await process_frame;await process_frame
	check(owner.result.ok and not owner.result.native and owner.result.text=="recognized words","text fallback preserves recognized speech")
	check(world.hearing.consumers==0 and world.hearing.recognized.is_connected(world.hearing.consumer),"native hidden chat receives nothing; signal consumers restored")
	var calls_before: int=world.hearing.calls
	owner.begin({"chat_id":"qa","message_id":"long-answer","audio":[long_saved.attachment]});await process_frame
	for fragment: String in ["alpha beta","beta gamma","gamma delta","delta omega"]:
		check(world.hearing.recognizing and world.hearing._buffer.size()<=int(AudioServer.get_mix_rate())*20,"long speech is recognized sequentially without shortening the recording")
		world.hearing.finish(fragment);await process_frame;await process_frame
	check(owner.result.ok and owner.result.text=="alpha beta gamma delta omega" and world.hearing.calls==calls_before+4,"all chunks join in order and overlapping words are not repeated")
	long_samples.resize(71*Wav.RATE);long_samples.fill(0.0)
	for index: int in Wav.RATE:long_samples[-1-index]=0.2
	var late_clip: Dictionary=service.store.import_bytes(Wav.encode(long_samples,Wav.RATE),"late speech")
	calls_before=world.hearing.calls;owner.begin({"chat_id":"qa","message_id":"late-answer","audio":[late_clip.attachment]});await process_frame
	check(world.hearing.calls==calls_before+1 and world.hearing._buffer.size()<int(AudioServer.get_mix_rate())*2,"speech beyond 70 seconds is reached while silent ranges are skipped")
	world.hearing.finish("last words");await process_frame;await process_frame
	check(owner.result.ok and owner.result.text=="last words" and world.hearing.recognized.is_connected(world.hearing.consumer),"tail speech completes with native listeners restored")
	owner.begin(target);await process_frame;service.cancel_all();world.hearing.finish("late speech");await process_frame;await process_frame
	check(owner.result.code=="cancelled" and world.hearing.consumers==0 and world.hearing.recognized.is_connected(world.hearing.consumer),"late ASR after cancellation cannot send or write hidden inputs")
	world.hearing.available=false;owner.begin(target);await process_frame
	check(not owner.result.ok and owner.result.code=="audio.asr_unavailable","missing backend gives a real diagnostic")
	owner.caps={};world.hearing.available=true;owner.begin(target);await process_frame;channel=service.pending.keys()[0]
	service.response(channel,400,JSON.stringify({"error":{"message":"unsupported_audio"}}).to_utf8_buffer());service.receive({},channel);await process_frame;world.hearing.finish("fallback after API rejection");await process_frame
	check(owner.result.ok and not owner.result.native and not service.rejected.is_empty(),"explicit native rejection falls back to ASR")
	var store:=ChatStore.new();store.create("audio");check(store.enqueue_user("","date",[],[],[handle]),"audio-only message can be queued")
	var delivery: Dictionary=store.deliveries[-1];var started: Dictionary=store.begin(delivery.text,"date",delivery.target_id,[],{},delivery.user_message_id,[],delivery.audio)
	check(started.audio==[handle] and store.current().messages[0].audio==[handle],"queue preserves the exact voice attachment")
	var restored:=ChatStore.new();restored.restore(store.snapshot());check(restored.current().messages[0].audio==[handle],"voice attachment remains in saved chat")
	for pair: Array in [[{"input_modalities":["text","audio"]},true],[{"architecture":{"input_modalities":["text","image"]}},false],[{"name":"Gemini audio super"},null],[{"output_modalities":["audio"]},null]]:
		var row: Dictionary=pair[0].duplicate();row.id="selected";var caps: Dictionary=Catalog.parse_metadata(JSON.stringify({"data":[row]}).to_utf8_buffer(),"selected","https://audio.invalid/v1").capabilities
		check(caps.get("audio_input")==pair[1],"input audio metadata only "+JSON.stringify(pair[0]))
	owner.queue_free();await process_frame
	if errors.is_empty():print("AUDIO TESTS PASS; ",checks," checks");quit(0)
	else:push_error(str(errors));quit(1)
