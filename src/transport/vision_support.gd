extends Node
## Auto capability detection. No model-name guesses, keys, OS input or world actions.
const Limits=preload("res://mods/pax_harness/src/transport/provider_limits.gd")
const Vision=preload("res://mods/pax_harness/src/transport/vision_payload.gd")
const Picture=preload("res://mods/pax_harness/src/transport/vision_probe_image.gd")
const PREFIX="mod_pax_harness_vision_probe_"
const TTL=86400
const TIMEOUT_MS=30000
const OUTPUT_BUDGET=2048 # Reasoning tokens also consume the API output budget.
class Check extends RefCounted:
 signal completed
 var result: Dictionary={}
 var finished:=false
 func finish(value: Dictionary) -> void:
  if finished:return
  result=value;finished=true;completed.emit()
var owner_mod: Node
var cache: Dictionary={}
var pending: Dictionary={}
var usage_pending: Dictionary={}
var backoff: Dictionary={}
var last_result: Dictionary={}
func setup(owner: Node) -> void:
 owner_mod=owner;process_mode=Node.PROCESS_MODE_ALWAYS
 var saved: Variant=owner.load_data("vision_support_cache",{})
 if saved is Dictionary:
  for key: Variant in saved:
   var row: Variant=saved[key]
   if cache.size()<64 and key is String and RegEx.create_from_string("^[a-f0-9]{64}$").search(key)!=null and row is Dictionary and row.get("supported") is bool and (row.get("expires") is int or row.get("expires") is float) and row.expires>Time.get_unix_time_from_system() and row.expires<Time.get_unix_time_from_system()+TTL+60:cache[key]=row
static func mode(profile: Dictionary) -> String:
 if profile.get("vision_mode") in ["auto","on","off"]:return profile.vision_mode
 return "on" if profile.get("enabled") is bool and profile.get("enabled")==true and profile.get("vision_input") is bool and profile.get("vision_input")==true else "auto"
static func key(base: String, model: String) -> String:
 var normalized: String=Limits.api_base(base)
 return (normalized+"\n"+model).sha256_text() if normalized!="" and model!="" else ""
func decide(base: String, model: String, profile: Dictionary, metadata: Dictionary) -> Dictionary:
 var selected: String=mode(profile);var id: String=key(base,model)
 var result: Dictionary={"mode":selected,"enabled":false,"verified":false,"needs_probe":false,"state":"disabled","source":"manual","key":id}
 if selected=="off" or id=="":return result
 if selected=="on":result.merge({"enabled":true,"verified":true,"state":"supported"},true);return result
 var row: Dictionary=cache.get(id,{})
 if not row.is_empty() and row.expires<=Time.get_unix_time_from_system():cache.erase(id);row={}
 if not row.is_empty() and not row.supported:result.merge({"state":"unsupported","source":"api_rejection"},true);return result
 if metadata.get("image_input") is bool:
  result.merge({"enabled":metadata.image_input,"verified":metadata.image_input,"state":"supported" if metadata.image_input else "unsupported","source":"catalogue"},true);return result
 if not row.is_empty():result.merge({"enabled":true,"verified":true,"state":"supported","source":"visual_probe"},true);return result
 result.merge({"enabled":true,"state":"unknown","source":"unknown","needs_probe":true},true);return result
func is_probe_channel(channel: String) -> bool:return channel.begins_with(PREFIX)
func _current(record: Dictionary) -> bool:
 if not is_instance_valid(owner_mod) or record.generation!=owner_mod._source_generation or not is_instance_valid(record.provider):return false
 var now: Dictionary=owner_mod.vision_context(record.provider)
 return now.base==record.base and now.model==record.model and now.provider_id==record.provider_id and now.mode=="auto" and now.enabled
func ensure(provider: Node, target: Dictionary={}) -> Dictionary:
 var state: Dictionary=owner_mod.vision_context(provider)
 if not state.enabled:return {"ok":false,"code":"vision_unsupported" if state.state=="unsupported" else "vision_input_disabled"}
 if not state.get("needs_probe",false):return {"ok":true,"source":state.source}
 if int(backoff.get(state.key,0))>Time.get_ticks_msec():return {"ok":false,"code":"vision_check_unconfirmed"}
 var job: Check
 for record: Dictionary in pending.values():
  if record.key==state.key and record.provider_id==state.provider_id:job=record.job;break
 if job==null:
  job=Check.new()
  var suffix: String=Crypto.new().generate_random_bytes(8).hex_encode();var channel: String=PREFIX+suffix
  var picture: Dictionary=Picture.create()
  var prompt: String="Read the six white digits shown in the attached image. Return JSON with exactly code, a string of six digits. The digits exist ONLY in the image. If unreadable, return {\"code\":\"unreadable\"}. No tools, no actions, no explanations."
  var record: Dictionary={"key":state.key,"provider":provider,"provider_id":state.provider_id,"base":state.base,"model":state.model,"generation":owner_mod._source_generation,"started":Time.get_ticks_msec(),"channel":channel,"job":job,"picture":picture,"prompt":prompt,"failure":{},"target":{"chat_id":target.get("chat_id",""),"message_id":target.get("message_id","")},"parts":{"system":prompt.length(),"tools":0,"messages":16}}
  if usage_pending.size()>=32:usage_pending.erase(usage_pending.keys()[0])
  pending[channel]=record;usage_pending[channel]=record.duplicate()
  var accepted: bool=owner_mod.ask_ai("vision_probe_"+suffix,prompt,{"request":"Read the image."},owner_mod._vision_probe_answer.bind(channel),{"temperature":0.0,"max_tokens":OUTPUT_BUDGET,"schema":{"type":"object","properties":{"code":{"type":"string"}},"required":["code"],"additionalProperties":false}})
  if not accepted:usage_pending.erase(channel);_finish(channel,{"ok":false,"code":"vision_check_unavailable"})
 if not job.finished:await job.completed
 return job.result
func validate(provider: Node, channel: String) -> Dictionary:
 if not pending.has(channel) or pending[channel].provider!=provider or not _current(pending[channel]):return {"ok":false,"code":"vision_request_expired","errors":["vision_request_expired"]}
 return {"ok":true}
func prepare_request(event: Dictionary) -> void:
 var channel: String=str(event.get("channel",""))
 if not is_probe_channel(channel):return
 if not pending.has(channel) or not _current(pending[channel]):event["cancel"]=true;return
 event["system"]=pending[channel].prompt;event["user"]="Read the image.";event["dossier"]="";event["max_tokens"]=OUTPUT_BUDGET
func prepare(provider: Node, query: Array, channel: String) -> Dictionary:
 var valid: Dictionary=validate(provider,channel)
 if not valid.ok:return valid
 var record: Dictionary=pending[channel]
 if usage_pending.has(channel) and query.size()==3:
  usage_pending[channel].model=str(query[2].get("model",record.model));usage_pending[channel].provider_host=Limits.hostname(str(query[0]))
 var resolver: Callable=func(handle: Dictionary) -> Dictionary:
  return {"ok":true,"bytes":record.picture.bytes,"mime_type":"image/png","width":224,"height":64} if handle.id==record.picture.handle.id else {"ok":false}
 return Vision.apply(query,[record.picture.handle],resolver,true,record.model)
func receive(response: Dictionary, channel: String) -> void:
 if not pending.has(channel):return
 var record: Dictionary=pending[channel]
 if not _current(record):_finish(channel,{"ok":false,"code":"vision_model_changed"});return
 if str(response.get("code",""))==record.picture.code:
  remember(record.base,record.model,true);_finish(channel,{"ok":true,"source":"visual_probe"});return
 if Vision.unsupported_error(response) or record.failure.get("unsupported",false):remember(record.base,record.model,false);_finish(channel,{"ok":false,"code":"vision_unsupported"});return
 if backoff.size()>=64:backoff.erase(backoff.keys()[0])
 backoff[record.key]=Time.get_ticks_msec()+60000
 _finish(channel,{"ok":false,"code":"vision_check_unconfirmed"})
func remember(base: String, model: String, supported: bool) -> void:
 var id: String=key(base,model)
 if id=="":return
 if cache.size()>=64 and not cache.has(id):cache.erase(cache.keys()[0])
 cache[id]={"supported":supported,"expires":Time.get_unix_time_from_system()+(TTL if supported else 3600)}
 owner_mod.save_data("vision_support_cache",cache)
func response(channel: String, code: int, bytes: PackedByteArray, identity: Dictionary={}) -> void:
 var body: Variant=JSON.parse_string(bytes.get_string_from_utf8())
 if pending.has(channel) and body is Dictionary and Vision.unsupported_error(body):pending[channel].failure["unsupported"]=true
 if not is_probe_channel(channel) and body is Dictionary and Vision.unsupported_error(body) and identity.get("mode")=="auto" and identity.get("world_generation")==owner_mod._source_generation:remember(str(identity.get("base","")),str(identity.get("model","")),false)
 if code>=200 and code<300 and body is Dictionary:record_usage({"channel":channel,"usage":body.get("usage",{})})
func record_usage(event: Dictionary) -> void:
 var channel: String=str(event.get("channel",""))
 if not usage_pending.has(channel):return
 var row: Dictionary=usage_pending[channel];usage_pending.erase(channel)
 if row.generation!=owner_mod._source_generation or str(row.target.message_id)=="":return
 owner_mod._chat_usage(row.target,{"id":channel,"elapsed_ms":maxi(1,Time.get_ticks_msec()-int(row.started)),"usage":event.get("usage",{}) if event.get("usage") is Dictionary else {},"context_limit":0,"parts":row.parts,"model":row.model,"provider_host":row.get("provider_host",Limits.hostname(row.base)),"kind":"vision_check"})
func transport_failure(channel: String, code: String, usage: Dictionary={}) -> void:
 if not pending.has(channel):return
 pending[channel].failure["code"]=code
 if not usage.is_empty():record_usage({"channel":channel,"usage":usage})
func _finish(channel: String, result: Dictionary) -> void:
 if not pending.has(channel):return
 var record: Dictionary=pending[channel];pending.erase(channel)
 last_result={"ok":result.get("ok",false),"code":result.get("code",""),"source":result.get("source",""),"transport_code":record.failure.get("code","")}
 record.job.finish(result)
func _process(_delta: float) -> void:
 for channel: String in pending.keys():
  var record: Dictionary=pending[channel]
  if not _current(record) or Time.get_ticks_msec()-int(record.started)>=TIMEOUT_MS:
   _finish(channel,{"ok":false,"code":"vision_check_unconfirmed"})
   if is_instance_valid(owner_mod.chat_stream):owner_mod.chat_stream.cancel(channel)
func cancel_all() -> void:
 for channel: String in pending.keys():
  _finish(channel,{"ok":false,"code":"cancelled"})
  if is_instance_valid(owner_mod.chat_stream):owner_mod.chat_stream.cancel(channel)
func _exit_tree() -> void:cancel_all()
