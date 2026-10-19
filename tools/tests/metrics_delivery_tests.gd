extends SceneTree
const Router=preload("res://mods/pax_harness/src/transport/provider_router.gd")
const Stream=preload("res://mods/pax_harness/src/transport/chat_stream.gd")
const Metrics=preload("res://mods/pax_harness/src/chat/chat_metrics.gd")
const Store=preload("res://mods/pax_harness/src/chat/chat_store.gd")
class Owner extends Node:
 var _source_generation:=1
 var records: Array=[]
 var _router: RefCounted
 func _chat_current(_task: Dictionary) -> bool:return true
 func _chat_usage(target: Dictionary, request: Dictionary) -> void:records.append({"target":target,"request":request})
class Provider extends Node:
 var model:="original-model"
 var base_url:="https://api.invalid/v1"
 var answers: Array=[]
 func _curl_answer(_destination: HTTPRequest, code: int, bytes: PackedByteArray) -> void:answers.append({"code":code,"bytes":bytes})
var checks:=0
var errors: Array=[]
var owner: Node
var provider: Node
var router: RefCounted
const CHANNEL="mod_pax_harness_agent_slot_0"
func check(value: bool,label_: String) -> void:
 checks+=1
 if not value:errors.append(label_);print("FAIL "+label_)
func pending(id: String, text: String, generation: int=1) -> Dictionary:
 var row: Dictionary={"id":id,"channel":CHANNEL,"provider":provider,"target":{"chat_id":"qa","message_id":id},"generation":generation,"started_ms":Time.get_ticks_msec()-2000,"context_limit":1000000,"parts":{"system":14,"tools":6,"messages":text.length()}}
 router._usage_pending.append(row)
 router._transport[id]={"provider":provider,"task":"task","channel":CHANNEL}
 router.note_usage_request({"channel":CHANNEL,"system":"original instruction","user":text})
 return row
func _initialize() -> void:call_deferred("run")
func run() -> void:
 owner=Owner.new();root.add_child(owner);provider=Provider.new();root.add_child(provider);router=Router.new();router.setup(owner);owner._router=router
 router._tasks.task={"generation":1,"provider":provider,"game":null,"channel":"assistant","chat_target":{}}
 var final_request: Dictionary={"channel":CHANNEL,"system":"original instruction + native schema","user":"question"}
 var first:=pending("first","question")
 check(first.fingerprint!=router._usage_fingerprint(final_request),"native prompt change reproduces the original fingerprint mismatch")
 router.note_final_usage_request(final_request)
 router._transport.erase("first")
 var event: Dictionary=final_request.duplicate();event.usage={"prompt_tokens":200,"completion_tokens":50,"prompt_tokens_details":{"cached_tokens":128}}
 router.record_usage(event)
 check(owner.records.size()==1 and owner.records[0].request.usage.prompt_tokens==200,"final hook usage survives prompt mutation and callback retirement")
 router.record_usage(event);check(owner.records.size()==1,"duplicate answer hook is not counted twice")
 check(owner.records[0].request.parts.system>0 and owner.records[0].request.parts.tools==6,"context uses only advertised tool definitions")
 var second:=pending("second","image question")
 var query: Array=["https://wire.invalid/v1/chat/completions",[],{"model":"wire-model","messages":[{"role":"system","content":"rules and actual schemas"},{"role":"user","content":[{"type":"text","text":"hello"},{"type":"image_url","image_url":{"url":"data:image/png;base64,not-counted-as-text"}}]}]}]
 var key: String=router.note_transport_query(CHANNEL,provider,query)
 check(key=="second" and second.model=="wire-model" and second.provider_host=="wire.invalid","actual outgoing query is bound to its transport ID and safe identity")
 check(second.parts.messages==5 and second.parts.system+second.parts.tools==24,"image bytes are excluded from textual context proportions")
 var bytes: PackedByteArray=JSON.stringify({"choices":[{"message":{"content":"reply"}}],"usage":{"prompt_tokens":1000,"completion_tokens":100,"prompt_tokens_details":{"cached_tokens":800}}}).to_utf8_buffer()
 var stream:=Stream.new();root.add_child(stream);stream.setup(owner)
 var destination:=HTTPRequest.new();root.add_child(destination)
 stream.active[CHANNEL]={"client":HTTPClient.new(),"provider":provider,"destination":destination,"usage_request_id":key}
 stream._deliver(CHANNEL,200,bytes)
 check(owner.records.size()==2 and owner.records[1].request.usage.prompt_tokens==1000,"actual streaming/complete response reaches saved usage before native parsing")
 check(not router._usage_pending.has(second),"raw usage retires exactly its pending record")
 router.record_usage({"channel":CHANNEL,"system":"original instruction","user":"image question","usage":{"prompt_tokens":1000}})
 check(owner.records.size()==2,"late native hook cannot duplicate a transport receipt")
 await process_frame
 check(provider.answers.size()==1,"usage observation preserves the original provider callback")
 router._transport.erase("second")
 var old:=pending("old","older");router._transport.erase("old")
 var newer:=pending("new","newer")
 router.record_transport_usage("old",200,bytes)
 router.record_transport_usage("new",200,bytes)
 check(owner.records[-2].request.id=="old" and owner.records[-1].request.id=="new","late old-slot delivery cannot steal a reused slot's usage")
 router._transport.erase("new")
 pending("stale","different world",0);router.record_transport_usage("stale",200,bytes)
 check(owner.records.size()==4,"a different world generation cannot receive usage")
 router._transport.erase("stale")
 var missing:=pending("missing","no usage")
 router.record_transport_usage("missing",500,bytes)
 check(router._usage_pending.has(missing),"failed HTTP is not treated as successful usage")
 router.record_transport_usage("missing",200,JSON.stringify({"choices":[]}).to_utf8_buffer())
 check(owner.records.size()==5 and owner.records[-1].request.usage.is_empty(),"API omission stays unknown instead of invented token counts")
 router._transport.erase("missing")
 var messages:=pending("messages","anthropic")
 query=["https://messages.invalid/v1/messages",[],{"model":"messages-model","system":[{"type":"text","text":"system schema"}],"messages":[{"role":"user","content":"hello"}]}]
 router.note_transport_query(CHANNEL,provider,query)
 check(messages.parts.system+messages.parts.tools==13 and messages.parts.messages==5,"Messages protocol system text is included in context proportions")
 router.record_transport_usage("messages",200,JSON.stringify({"usage":{"input_tokens":100,"cache_read_input_tokens":200,"output_tokens":50}}).to_utf8_buffer())
 var store:=Store.new();store.create();var target: Dictionary=store.begin("qa","date");store.finish(target,"ok")
 for record: Dictionary in owner.records:store.record_usage(target,record.request)
 var summary: Dictionary=Metrics.summarize(store.current())
 check(summary.usage_requests==5 and summary.input==3500 and summary.output==400 and summary.cached==2728,"saved metrics aggregate actual OpenAI and Messages usage without duplication")
 check(summary.tps>0 and summary.last.model=="messages-model","TPS and last-model metadata are available")
 var parts: Dictionary=Metrics.context_parts(summary.last)
 check(parts.system+parts.tools+parts.messages==300 and parts.tools>0 and parts.messages>0,"displayed approximate split sums to actual API input")
 var restored:=Store.new();restored.restore(JSON.parse_string(JSON.stringify(store.snapshot())))
 check(Metrics.summarize(restored.current()).total==summary.total,"statistics survive save/load")
 owner.queue_free();provider.queue_free();stream.queue_free();destination.queue_free();await process_frame
 print("METRICS_DELIVERY_TESTS "+("PASS" if errors.is_empty() else str(errors))+"; "+str(checks)+" checks")
 quit(0 if errors.is_empty() else 1)
