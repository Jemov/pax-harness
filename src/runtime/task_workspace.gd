extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Durable goals and explicit player rules, scoped to the save and chat.
static func revision(value: Variant) -> String: return JSON.stringify(value).sha256_text()

static func execute(store: RefCounted, name: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	var chat: Dictionary = store.find(str(scope.get("chat_id","")))
	if chat.is_empty() or scope.get("channel") != "assistant": return {"ok":false,"code":"workspace.assistant_required"}
	var rules: bool = name.begins_with("instructions.")
	var campaign: bool = rules and args.get("scope","chat") == "campaign"
	var value: Variant = store.campaign_instructions if campaign else chat.get("instructions","") if rules else chat.get("plan",{})
	if name.ends_with(".read"): return {"ok":true,"result":{"value":value,"revision":revision(value),"scope":"campaign" if campaign else "chat"}}
	if int(scope.get("forward_depth",0)) > 0: return {"ok":false,"code":"workspace.forwarded_edit_disabled"}
	if str(args.get("expected_revision","")) != revision(value): return {"ok":false,"code":"workspace.source_changed_read_again"}
	var before: Variant = value.duplicate(true) if value is Dictionary else value
	if rules:
		if campaign: store.campaign_instructions = str(args.text)
		else: chat.instructions = str(args.text)
	else:
		var candidate: Dictionary = args.plan.duplicate(true)
		var ids := {}
		for step: Dictionary in candidate.steps:
			if ids.has(step.id): return {"ok":false,"code":"plan.duplicate_step_id"}
			ids[step.id] = true
			if step.status == "done" and str(step.get("evidence","")).strip_edges() == "": return {"ok":false,"code":"plan.completion_evidence_required"}
		if candidate.status == "completed" and candidate.steps.any(func(step: Dictionary): return step.status != "done"):
			return {"ok":false,"code":"plan.unfinished_steps"}
		chat.plan = candidate
		value = candidate
	if rules: value = str(args.text)
	store.changed.emit()
	return {"ok":true,"before":{"value":before},"after":{"value":value},"result":{"saved":true,"revision":revision(value),"value":value,"auto_execution":false}}

static func context(store: RefCounted, chat_id: String) -> Dictionary:
	var chat: Dictionary = store.find(chat_id)
	return {"plan":chat.get("plan",{}).duplicate(true),"campaign_instructions":store.campaign_instructions,"chat_instructions":chat.get("instructions","")}

static func trace(store: RefCounted, name: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	var chat: Dictionary = store.find(str(scope.get("chat_id","")))
	var events: Array = []
	for message: Dictionary in chat.get("messages",[]):
		if args.get("message_id","") != "" and message.id != args.message_id: continue
		for event: Dictionary in message.get("events",[]):
			if args.get("call_id","") != "" and event.get("id","") != args.call_id: continue
			events.append({"message_id":message.id,"date":message.get("date",""),"event":event.duplicate(true)})
	if name == "trace.replay":
		return {"ok":not events.is_empty(),"code":"trace.record_not_found" if events.is_empty() else "complete","result":{"recorded_observations":events,"executed":false,"historical":true,"current_world_verified":false}}
	if args.has("field"):
		if args.get("call_id","") == "": return {"ok":false,"code":"trace.call_id_required"}
		if events.is_empty(): return {"ok":false,"code":"trace.record_not_found","result":{"message":L.text("Запись с этим ID не найдена в данном чате. Проверьте ID. Вызов, отклонённый до выполнения, не имеет результата инструмента.")}}
		var event: Dictionary = events[0].event
		var receipt: Dictionary = event.get("receipt",event)
		var field: String = str(args.field)
		var selected: Variant = event.get("arguments",{}) if field == "arguments" else receipt.get(field,{})
		var path: String = str(args.get("path",""))
		if path != "":
			if not path.begins_with("/"): return {"ok":false,"code":"trace.invalid_path"}
			for encoded: String in path.substr(1).split("/"):
				var key: String = encoded.replace("~1","/").replace("~0","~")
				if selected is Dictionary and selected.has(key): selected = selected[key]
				elif selected is Array and key.is_valid_int() and int(key)>=0 and int(key)<selected.size(): selected = selected[int(key)]
				else: return {"ok":false,"code":"trace.path_not_found"}
		var raw: String = JSON.stringify(selected)
		var start: int = int(args.get("start",0))
		var limit: int = int(args.get("max_chars",4000))
		return {"ok":true,"result":{"field":field,"json_fragment":raw.substr(start,limit),"start":start,"next_start":mini(raw.length(),start+limit),"total_characters":raw.length(),"has_more":start+limit<raw.length(),"historical":true}}
	var offset: int = int(args.get("offset",0))
	var limit: int = int(args.get("limit",20))
	return {"ok":true,"result":{"total":events.size(),"items":events.slice(offset,offset+limit),"next_offset":offset+mini(limit,maxi(0,events.size()-offset)),"has_more":offset+limit<events.size()}}
