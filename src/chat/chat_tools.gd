extends RefCounted
## Cross-chat operations are local to the current save and return real receipts.
var owner_mod: Node
func setup(value: Node) -> void: owner_mod = value

func execute(name: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	var store: RefCounted = owner_mod.chat_store
	var source_id: String = str(scope.get("chat_id",""))
	if store == null or store.find(source_id).is_empty() or scope.get("channel") != "assistant": return {"ok":false,"code":"chat.assistant_session_required"}
	if name == "chat.list": return _list(store,args,source_id)
	var resolved: Dictionary = resolve(store,args,source_id)
	if not resolved.ok: return resolved
	var target: Dictionary = resolved.chat
	if name == "chat.read" or name == "chat.history":
		var result: Dictionary = store.history(str(target.id),args)
		result["chat"] = header(store,target)
		return {"ok":true,"result":result}
	if name != "chat.send": return {"ok":false,"code":"chat.unknown_operation"}
	if target.id == source_id: return {"ok":false,"code":"chat.send_requires_another_chat"}
	if int(scope.get("forward_depth",0)) > 0: return {"ok":false,"code":"chat.forwarding_chain_disabled"}
	var text: String = str(args.get("text","")).strip_edges()
	if text == "": return {"ok":false,"code":"chat.empty_message"}
	var key: String = source_id+":"+str(scope.get("message_id",scope.get("request_id","")))+":"+str(scope.get("call_id",""))
	for delivery: Dictionary in store.deliveries:
		if delivery.key == key: return {"ok":true,"submitted":true,"result":delivery_receipt(store,delivery)}
	var queued: int = 0
	for delivery: Dictionary in store.deliveries:
		if delivery.get("status") == "queued": queued += 1
	if queued >= 8: return {"ok":false,"code":"chat.message_queue_full"}
	var source: Dictionary = store.find(source_id)
	var delivery_id: String = store._id("delivery:")
	var user_id: String = store._id("message:")
	var origin: Dictionary = {"chat_id":source_id,"title":source.title,"delivery_id":delivery_id,"depth":1}
	target.messages.append({"id":user_id,"role":"user","text":text,"date":owner_mod._game.date_text(),"status":"queued","events":[],"origin":origin,"references":[{"id":source_id,"title":source.title}],"queue_entry":true})
	var delivery: Dictionary = {"id":delivery_id,"key":key,"source_id":source_id,"target_id":target.id,"user_message_id":user_id,
		"source_message_id":str(scope.get("message_id","")),"status":"queued","text":text,"origin":origin}
	store.deliveries.append(delivery)
	store.changed.emit()
	owner_mod._chat_pump.call_deferred()
	return {"ok":true,"submitted":true,"result":delivery_receipt(store,delivery),"evidence":"Message stored in the target chat. Its reply is queued until the active assistant turn finishes."}

static func resolve(store: RefCounted, args: Dictionary, current: String) -> Dictionary:
	var id: String = str(args.get("chat_id",""))
	if id != "":
		var found: Dictionary = store.find(id)
		return {"ok":true,"chat":found} if not found.is_empty() else {"ok":false,"code":"chat.not_found"}
	var title: String = str(args.get("title","")).strip_edges().trim_prefix("@").to_lower()
	if title == "": return {"ok":true,"chat":store.find(current)}
	var matches: Array = store.chats.filter(func(chat: Dictionary): return str(chat.title).to_lower() == title)
	if matches.size() != 1: return {"ok":false,"code":"chat.ambiguous_title" if matches.size() > 1 else "chat.not_found","result":{"matches":matches.map(func(chat: Dictionary): return header(store,chat))}}
	return {"ok":true,"chat":matches[0]}

static func header(store: RefCounted, chat: Dictionary) -> Dictionary:
	return {"id":chat.id,"title":chat.title,"pinned":chat.get("pinned",false),"section_id":chat.get("section_id",""),
		"section":store.section(str(chat.get("section_id",""))).get("title",""),"messages":chat.messages.size()}

static func delivery_receipt(store: RefCounted, value: Dictionary) -> Dictionary:
	return {"delivery_id":value.id,"chat_id":value.target_id,"title":store.find(str(value.target_id)).get("title",""),
		"status":value.status,"message_id":value.user_message_id,"reply_is_queued":value.status == "queued"}

static func _list(store: RefCounted, args: Dictionary, current: String) -> Dictionary:
	var query: String = str(args.get("query","")).to_lower()
	var section_id: String = str(args.get("section_id",""))
	if section_id == "current": section_id = str(store.find(current).get("section_id",""))
	if args.has("section"):
		var requested: String = str(args.section).to_lower()
		var matches: Array = store.sections.filter(func(section: Dictionary): return str(section.title).to_lower() == requested)
		if matches.size() != 1: return {"ok":false,"code":"chat.section_ambiguous_or_missing"}
		section_id = str(matches[0].id)
	var rows: Array = []
	for chat: Dictionary in store.chats:
		if query != "" and query not in str(chat.title).to_lower(): continue
		if (args.has("section_id") or args.has("section")) and str(chat.get("section_id","")) != section_id: continue
		if args.has("pinned") and bool(chat.get("pinned",false)) != bool(args.pinned): continue
		rows.append(header(store,chat))
	var offset: int = maxi(0,int(args.get("offset",0)))
	var limit: int = clampi(int(args.get("limit",20)),1,100)
	var items: Array = rows.slice(offset,offset+limit)
	return {"ok":true,"result":{"total":rows.size(),"items":items,"returned":items.size(),"next_offset":offset+items.size(),
		"has_more":offset+items.size()<rows.size(),"sections":store.sections.map(func(section: Dictionary): return {"id":section.id,"title":section.title}),"current_chat_id":current}}
