extends SceneTree
const Support=preload("res://mods/pax_harness/src/transport/vision_support.gd")
const Picture=preload("res://mods/pax_harness/src/transport/vision_probe_image.gd")
const Catalog=preload("res://mods/pax_harness/src/transport/provider_catalog.gd")
const Vision=preload("res://mods/pax_harness/src/transport/vision_payload.gd")
class Provider extends Node:
 var base_url:="https://future.invalid/v1"
 var model:="unknown-model"
class Owner extends Node:
 var _source_generation:=1
 var vision_support: Node
 var provider: Node
 var chat_stream: Node
 var profile: Dictionary={}
 var caps: Dictionary={}
 var saved: Dictionary={}
 var requests: Array=[]
 var usage: Array=[]
 var result: Dictionary={}
 func load_data(_key: String, fallback: Variant) -> Variant:return saved.get("cache",fallback)
 func save_data(_key: String, data: Dictionary) -> void:saved["cache"]=data.duplicate(true)
 func vision_context(p: Node=null) -> Dictionary:
  var value: Dictionary={"enabled":false}
  if p!=null and p!=provider:return value
  value={"base":provider.base_url,"model":provider.model,"provider_id":provider.get_instance_id(),"world_generation":_source_generation}
  value.merge(vision_support.decide(provider.base_url,provider.model,profile,caps));return value
 func ask_ai(channel: String, prompt: String, data: Dictionary, done: Callable, options: Dictionary) -> bool:
  requests.append({"channel":channel,"prompt":prompt,"data":data,"done":done,"options":options});return true
 func _vision_probe_answer(response: Dictionary, channel: String) -> void:vision_support.receive(response,channel)
 func _chat_usage(target: Dictionary, request: Dictionary) -> void:usage.append({"target":target,"request":request})
 func begin() -> void:result=await vision_support.ensure(provider,{"chat_id":"qa","message_id":"answer"})
var checks:=0
var errors: Array=[]
func check(value: bool, why: String) -> void:
 checks+=1
 if not value:errors.append(why);print("FAIL "+why)
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var owner:=Owner.new();root.add_child(owner);owner.provider=Provider.new();owner.add_child(owner.provider)
 var service:=Support.new();owner.add_child(service);owner.vision_support=service;service.setup(owner)
 check(owner.vision_context().mode=="auto" and owner.vision_context().needs_probe,"fresh profile defaults Auto, even generation profile disabled")
 check(Support.mode({"enabled":true,"vision_input":true})=="on","legacy explicit enable retained")
 check(Support.mode({"enabled":false,"vision_input":true})=="auto","inactive legacy profile migrates to Auto")
 check(Support.mode({"enabled":true,"vision_input":"true"})=="auto","nonboolean legacy value cannot force permission")
 check(Support.key("https://future.invalid/v1/","unknown-model")==Support.key(owner.provider.base_url,owner.provider.model),"normalized identity")
 owner.profile={"vision_mode":"off"};check(not (await service.ensure(owner.provider)).ok and owner.requests.is_empty(),"explicit Off never probes")
 owner.profile={"vision_mode":"on"};check((await service.ensure(owner.provider)).ok and owner.requests.is_empty(),"explicit On bypasses check")
 owner.profile={};owner.caps={"image_input":false};check(not (await service.ensure(owner.provider)).ok and owner.requests.is_empty(),"API text-only declaration denies images without probe")
 owner.caps={"image_input":true};check((await service.ensure(owner.provider)).ok and owner.requests.is_empty(),"API image declaration avoids paid probe")
 owner.caps={};owner.begin();await process_frame
 var channel: String=service.pending.keys()[0];var record: Dictionary=service.pending[channel];var request: Dictionary=owner.requests[0]
 check(service.pending.size()==1 and request.options.max_tokens==Support.OUTPUT_BUDGET,"unknown support triggers bounded same-model SDK request")
 check(record.picture.code not in request.prompt and record.picture.code not in JSON.stringify(request.data),"visual secret never in text")
 check(Picture.DIGITS.all(func(pattern: String):return pattern.length()==35),"all bitmap digits valid")
 var event: Dictionary={"channel":channel,"system":"native world framing","user":"game data","dossier":"huge dossier"};service.prepare_request(event)
 check(event.system==record.prompt and event.dossier=="" and event.max_tokens==Support.OUTPUT_BUDGET,"probe excludes world framing")
 var query: Array=[owner.provider.base_url+"/chat/completions",[],{"model":owner.provider.model,"messages":[{"role":"user","content":"Read the image."}]}]
 var prepared: Dictionary=service.prepare(owner.provider,query,channel)
 check(prepared.ok and Vision.contains_images(prepared.query) and not Vision.contains_images(query),"actual PNG serialized, original query untouched")
 var image:=Image.new();check(image.load_png_from_buffer(record.picture.bytes)==OK and image.get_width()==224 and image.get_height()==64,"valid bounded random image")
 service.response(channel,200,JSON.stringify({"usage":{"prompt_tokens":100,"completion_tokens":10,"total_tokens":110}}).to_utf8_buffer())
 service.record_usage({"channel":channel,"usage":{"total_tokens":999}})
 check(owner.usage.size()==1 and owner.usage[0].request.usage.total_tokens==110,"actual probe usage attributed once")
 service.receive({"code":record.picture.code},channel);await process_frame
 check(owner.result.ok and owner.vision_context().verified and owner.vision_context().source=="visual_probe","correct visual challenge confirms support")
 check((await service.ensure(owner.provider)).ok and owner.requests.size()==1,"second use reuses detection")
 check(not service.prepare(owner.provider,query,channel).ok,"late probe channel cannot send orphan image request")
 check(service.decide("https://other.invalid/v1",owner.provider.model,{},{}).needs_probe,"different API never inherits result")
 check(service.decide(owner.provider.base_url,"another-model",{},{}).needs_probe,"different model never inherits result")
 var restored:=Support.new();owner.add_child(restored);restored.setup(owner)
 check(restored.decide(owner.provider.base_url,owner.provider.model,{},{}).verified,"positive detection persists across service reload")
 service.cache.clear();owner.result={};owner.begin();await process_frame
 channel=service.pending.keys()[0];service.receive({"code":"wrong"},channel);await process_frame
 check(not owner.result.ok and service.cache.is_empty() and owner.vision_context().needs_probe,"HTTP success with wrong/unreadable content cannot confirm vision")
 check(not (await service.ensure(owner.provider)).ok and service.pending.is_empty(),"temporary failure backs off instead of repeated paid checks")
 service.backoff.clear();owner.begin();await process_frame;channel=service.pending.keys()[0]
 service.response(channel,400,JSON.stringify({"error":{"message":"This model does not support image input"}}).to_utf8_buffer());service.receive({},channel);await process_frame
 check(not owner.result.ok and owner.result.code=="vision_unsupported" and not owner.vision_context().enabled,"explicit API rejection learned")
 owner.profile={"vision_mode":"on"};check(owner.vision_context().enabled,"manual override remains available")
 owner.profile={};service.cache.clear();owner.begin();await process_frame;channel=service.pending.keys()[0];record=service.pending[channel]
 owner.provider.model="changed";service.receive({"code":record.picture.code},channel);await process_frame
 check(not owner.result.ok and service.cache.is_empty(),"model switch invalidates in-flight result")
 owner.begin();await process_frame;service.cancel_all();await process_frame
 check(not owner.result.ok and owner.result.code=="cancelled" and service.pending.is_empty(),"stop cancels suspended detection")
 for pair: Array in [[{"input_modalities":["text","image"]},true],[{"architecture":{"input_modalities":["text"]}},false],[{"capabilities":{"vision":true}},true],[{"output_modalities":["image"]},null],[{"name":"vision-awesome"},null],[{"input_modalities":["image"],"capabilities":{"vision":false}},null]]:
  var row: Dictionary=pair[0].duplicate(true);row.id="selected"
  var parsed: Dictionary=Catalog.parse_metadata(JSON.stringify({"data":[row]}).to_utf8_buffer(),"selected",owner.provider.base_url)
  check(parsed.capabilities.get("image_input")==pair[1],"metadata input modality "+JSON.stringify(pair[0]))
 restored.queue_free();owner.queue_free();await process_frame
 if errors.is_empty():print("VISION_AUTO PASS; ",checks," checks");quit(0)
 else:push_error(str(errors));quit(1)
