extends RefCounted
## Save-owned sessions. UI and model context are projections of these records.
signal changed
const Metrics = preload("res://mods/pax_harness/src/chat/chat_metrics.gd")
const Markdown = preload("res://mods/pax_harness/src/ui/markdown/chat_markdown.gd")
var deliveries: Array = []
var sections: Array = []
var chats: Array = []
var selected: String = ""
var sequence: int = 0
var seeded: bool = false
var campaign_instructions: String = ""

func _id(prefix: String) -> String:
	sequence += 1
	return prefix+str(sequence)

func snapshot() -> Dictionary:
	return {"version":4,"campaign_instructions":campaign_instructions,"deliveries":deliveries.duplicate(true),"sections":sections.duplicate(true),"chats":chats.duplicate(true),"selected":selected,"sequence":sequence,"seeded":seeded}

func restore(data: Dictionary) -> void:
	campaign_instructions = str(data.get("campaign_instructions",""))
	deliveries = data.get("deliveries",[]).duplicate(true) if data.get("deliveries") is Array else []
	for delivery: Dictionary in deliveries:
		if delivery.get("status") in ["queued","running"]: delivery.status = "interrupted"
	sections = data.get("sections",[]).duplicate(true) if data.get("sections") is Array else []
	chats = data.get("chats",[]).duplicate(true) if data.get("chats") is Array else []
	selected = str(data.get("selected",""))
	sequence = int(data.get("sequence",0))
	seeded = bool(data.get("seeded",false))
	# Restoring a save never replays a model request or a tool operation.
	for chat: Dictionary in chats:
		chat["pinned"] = bool(chat.get("pinned",false))
		if section(str(chat.get("section_id",""))).is_empty(): chat["section_id"] = ""
		for message: Dictionary in chat.get("messages",[]):
			if message.get("status") not in ["running","queued"]: continue
			message.status = "interrupted"
			if message.get("kind") == "compaction": message.text = "Сжатие прервано при выходе"
			if str(message.get("stream",{}).get("text", "")) != "": message.text = message.stream.text
			message.erase("stream")
			if str(message.get("text","")).is_empty(): message.text = "Ответ был прерван при выходе из игры. Можно отправить вопрос ещё раз."
			for event: Dictionary in message.get("events",[]):
				if event.get("status") == "running": event.status = "interrupted"
	if find(selected).is_empty() and not chats.is_empty(): selected = str(chats[0].id)
	changed.emit()

func find(id: String) -> Dictionary:
	for chat: Dictionary in chats:
		if chat.get("id") == id: return chat
	return {}

func current() -> Dictionary: return find(selected)

func create(title: String = "Новый чат") -> String:
	var id: String = _id("chat:")
	chats.push_front({"id":id,"title":title,"auto_title":true,"created":Time.get_unix_time_from_system(),
		"updated":Time.get_unix_time_from_system(),"messages":[],"draft":"","pinned":false,"section_id":"","draft_refs":[]})
	selected = id
	seeded = true
	changed.emit()
	return id

func select(id: String) -> bool:
	if find(id).is_empty(): return false
	selected = id
	changed.emit()
	return true

func rename(id: String, title: String) -> void:
	var chat: Dictionary = find(id)
	if chat.is_empty() or title.strip_edges().is_empty(): return
	chat.title = title.strip_edges().left(100)
	chat.auto_title = false
	chat["title_from_question"] = false
	chat["title_pending"] = false
	changed.emit()

func needs_title(id: String) -> bool:
	var chat: Dictionary = find(id)
	if chat.is_empty(): return false
	return bool(chat.get("title_pending",false)) or bool(chat.get("auto_title",false)) or bool(chat.get("title_from_question",false)) or title_tooltip(chat) != str(chat.get("title",""))

func apply_title(id: String, proposed: Variant) -> bool:
	if not needs_title(id) or not proposed is String: return false
	var title: String = proposed.strip_edges().trim_prefix("\"").trim_suffix("\"").strip_edges()
	if title.length() < 2 or title.length() > 64 or "\n" in title or "\r" in title or "```" in title or title.split(" ",false).size() > 10: return false
	var chat: Dictionary = find(id)
	chat.title = title
	chat.auto_title = false; chat["title_from_question"] = false; chat["title_pending"] = false
	changed.emit()
	return true

func title_tooltip(chat: Dictionary) -> String:
	var title: String = str(chat.get("title",""))
	for message: Dictionary in chat.get("messages",[]):
		if message.get("role") != "user": continue
		var question: String = str(message.get("text",""))
		if chat.get("title_from_question",title == question.replace("\n"," ").left(52)): return question
		break
	return title

func remove(id: String) -> bool:
	var chat: Dictionary = find(id)
	if chat.is_empty() or running(id): return false
	chats.erase(chat)
	if selected == id: selected = str(chats[0].id) if not chats.is_empty() else ""
	if chats.is_empty(): create()
	changed.emit()
	return true

func import_native(history: Array, date: String) -> void:
	if seeded: return
	seeded = true
	create("Предыдущий разговор" if not history.is_empty() else "Новый чат")
	for row: Dictionary in history:
		var role: String = "user" if row.get("who") == "player" else "assistant"
		current().messages.append({"id":_id("message:"),"role":role,"text":str(row.get("what","")),"date":date,"status":"complete","events":[]})
	changed.emit()

func context(id: String = "", limit: int = 12) -> Array:
	var result: Array = []
	var chat: Dictionary = find(selected if id == "" else id)
	for message: Dictionary in chat.get("messages",[]):
		if message.get("status") in ["running","queued"] or str(message.get("text","")).is_empty(): continue
		if message.get("role") not in ["user","assistant"]: continue
		result.append({"who":"player" if message.role == "user" else "ВИ","what":message.text})
	return result.slice(maxi(0,result.size()-limit))

func history(id: String, options: Dictionary = {}) -> Dictionary:
	var records: Array = []
	var query: String = str(options.get("query","")).to_lower()
	for row: Dictionary in find(id).get("messages",[]):
		if (row.get("status") == "queued" or (row.get("status") == "running" and not options.get("include_tools",false))) or (query != "" and query not in str(row.get("text","")).to_lower()): continue
		records.append({"role":row.role,"text":row.text,"date":row.get("date",""),"status":row.status,"references":row.get("references",[]).duplicate(true),"origin":row.get("origin",{}).duplicate(true),"tools":row.get("events",[]).filter(func(event: Dictionary): return event.get("kind") == "tool") if options.get("include_tools",false) else []})
	var offset: int = maxi(0,int(options.get("offset",0)))
	var limit: int = clampi(int(options.get("limit",20)),1,100)
	var end: int = maxi(0,records.size()-offset)
	var page: Array = records.slice(maxi(0,end-limit),end)
	return {"total":records.size(),"returned":page.size(),"items":page,"offset":offset,"limit":limit,
		"has_more":end-page.size()>0,"next_offset":offset+page.size(),"order":"newest_page_in_chronological_order",
		"note":"Only the captured chat is searched. These are prior messages, not proof of current game facts."}

func begin(question: String, date: String, chat_id: String = "", refs: Array = [], origin: Dictionary = {}, existing_user: String = "") -> Dictionary:
	if chat_id == "" and current().is_empty(): create()
	var id: String = selected if chat_id == "" else chat_id
	var chat: Dictionary = find(id)
	if chat.is_empty(): return {}
	if chat.get("auto_title",true):
		chat.title = "Новый разговор"
		chat.auto_title = false
		chat["title_from_question"] = false
		chat["title_pending"] = true
	chat.updated = Time.get_unix_time_from_system()
	chat.draft = ""
	chat["draft_refs"] = []
	var headers: Array = reference_headers(refs)
	var user_id: String = existing_user
	if user_id == "":
		user_id = _id("message:")
		chat.messages.append({"id":user_id,"role":"user","text":question,"date":date,"status":"complete","events":[],"references":headers,"origin":origin.duplicate(true)})
	else:
		for row: Dictionary in chat.messages:
			if row.id == user_id:
				row.status = "complete"
				headers = row.get("references",[]).duplicate(true)
	var message_id: String = _id("message:")
	chat.messages.append({"id":message_id,"role":"assistant","text":"","date":date,"status":"running","events":[],"started_ms":Time.get_ticks_msec(),"elapsed_ms":0})
	changed.emit()
	return {"chat_id":id,"message_id":message_id,"user_message_id":user_id,"references":headers,"origin":origin.duplicate(true)}

func reference_headers(ids: Array) -> Array:
	var rows: Array = []
	for value: Variant in ids:
		var id: String = str(value.get("id","")) if value is Dictionary else str(value)
		var chat: Dictionary = find(id)
		if not chat.is_empty() and not rows.any(func(row: Dictionary): return row.id == id): rows.append({"id":id,"title":chat.title})
	return rows

func model_context(chat_id: String) -> Array:
	var chat: Dictionary = find(chat_id)
	var checkpoint: Dictionary = chat.get("checkpoint",{})
	var through: String = str(checkpoint.get("through",""))
	var started: bool = through == "" or not chat.get("messages",[]).any(func(row: Dictionary): return row.id == through)
	var result: Array = []
	if through != "" and not started:
		result.append(checkpoint_message(str(checkpoint.get("summary",""))))
	for row: Dictionary in chat.get("messages",[]):
		if not started:
			if row.id == through: started = true
			continue
		if row.get("role") not in ["user","assistant"] or row.get("status") in ["running","queued"] or str(row.get("text","")).is_empty(): continue
		result.append({"who":"player" if row.role == "user" else "ВИ","what":row.text,"references":row.get("references",[]),"origin":row.get("origin",{})})
	return result

func cancel_deliveries(source_message_id: String) -> void:
	for delivery: Dictionary in deliveries:
		if delivery.get("source_message_id") != source_message_id or delivery.get("status") != "queued": continue
		delivery.status = "interrupted"
		for row: Dictionary in find(str(delivery.target_id)).get("messages",[]):
			if row.id == delivery.user_message_id: row.status = "interrupted"
	changed.emit()

func message(target: Dictionary) -> Dictionary:
	for row: Dictionary in find(str(target.get("chat_id",""))).get("messages",[]):
		if row.get("id") == target.get("message_id"): return row
	return {}

func running(id: String = "") -> bool:
	for chat: Dictionary in chats:
		if id != "" and chat.id != id: continue
		for row: Dictionary in chat.get("messages",[]):
			if row.get("status") == "running": return true
	return false

func record_usage(target: Dictionary, request: Dictionary) -> void:
	var row: Dictionary = message(target)
	if row.is_empty(): return
	if not row.has("requests"): row["requests"] = []
	if row.requests.any(func(old: Dictionary): return old.id == request.id): return
	var copy: Dictionary = request.duplicate(true)
	copy["tokens"] = Metrics.normalize(copy.get("usage",{}))
	copy.erase("usage")
	row.requests.append(copy)
	changed.emit()

func record(target: Dictionary, kind: String, payload: Dictionary) -> void:
	var row: Dictionary = message(target)
	if row.is_empty() or row.get("status") != "running": return
	var now: int = Time.get_ticks_msec()
	var events: Array = row.events
	if kind in ["step.start","assistant.note","format.error"]: row.erase("stream")
	if kind != "tool.result":
		for event: Dictionary in events:
			if event.kind == "step" and event.status == "running":
				event.status = "complete"
				event.elapsed_ms = now-int(event.started_ms)
	match kind:
		"step.start": events.append({"kind":"step","round":payload.get("round",1),"status":"running","started_ms":now,"elapsed_ms":0})
		"assistant.note":
			if not str(payload.get("text","")).strip_edges().is_empty(): events.append({"kind":"note","text":str(payload.text)})
		"format.error":
			var chart_error: bool = payload.get("code") == "charts.invalid_response"
			var text: String = ("Исправление диаграммы" if chart_error else "Исправление формата вызова")+" · попытка "+str(payload.attempt)
			if chart_error and not payload.get("errors",[]).is_empty(): text += "\n"+str(payload.errors[0].get("reason",""))
			events.append({"kind":"note","text":text,"validation":payload.duplicate(true)})
		"network.retry": events.append({"kind":"note","text":"Повтор запроса к модели · попытка "+str(payload.attempt)+" · через "+str(ceili(float(payload.delay_ms)/1000))+" с","retry":payload.duplicate(true)})
		"loop.warning": events.append({"kind":"note","text":"Проверка повторяющихся действий","diagnostic":payload.duplicate(true)})
		"tool.call": events.append({"kind":"tool","id":payload.id,"name":payload.name,"arguments":payload.arguments.duplicate(true),"status":"running","started_ms":now,"elapsed_ms":0})
		"tool.result":
			for event: Dictionary in events:
				if event.kind == "tool" and event.id == payload.id:
					var receipt: Dictionary = payload.get("receipt",{})
					event.status = receipt.get("status","failed")
					event.elapsed_ms = now-int(event.started_ms)
					event["result"] = receipt.get("result",{}).duplicate(true) if receipt.get("result") is Dictionary or receipt.get("result") is Array else receipt.get("result")
					event["errors"] = Array(receipt.get("errors",[]))
					event["mutates_world"] = receipt.get("mutates_world",false)
					event["receipt"] = receipt.duplicate(true)
					break
	changed.emit()

func finish(target: Dictionary, text: String, ok: bool = true, code: String = "") -> void:
	var row: Dictionary = message(target)
	if row.is_empty() or row.get("status") != "running": return
	var partial: String = str(row.get("stream",{}).get("text",""))
	row.erase("stream")
	row.text = partial+"\n\n"+text if not ok and partial != "" else text
	row.status = "complete" if ok else ("cancelled" if code == "cancelled" else "failed")
	row["error_code"] = code
	row.elapsed_ms = maxi(0,Time.get_ticks_msec()-int(row.get("started_ms",Time.get_ticks_msec())))
	for event: Dictionary in row.events:
		if event.get("status") != "running": continue
		event.status = "complete" if ok and event.kind == "step" else "interrupted"
		event.elapsed_ms = maxi(0,Time.get_ticks_msec()-int(event.get("started_ms",Time.get_ticks_msec())))
	find(str(target.chat_id)).updated = Time.get_unix_time_from_system()
	changed.emit()

func stream_update(target: Dictionary, request_id: String, text: String) -> void:
	var row: Dictionary = message(target)
	if row.is_empty() or row.get("status") != "running": return
	row["stream"] = {"request_id":request_id,"text":text}
	changed.emit()

func section(id: String) -> Dictionary:
	for row: Dictionary in sections:
		if row.id == id: return row
	return {}

func create_section(title: String, chat_id: String = "") -> String:
	if title.strip_edges().is_empty(): return ""
	var id: String = _id("section:")
	sections.append({"id":id,"title":title.strip_edges().left(100),"collapsed":false})
	if not find(chat_id).is_empty(): find(chat_id)["section_id"] = id
	changed.emit()
	return id

func rename_section(id: String, title: String) -> void:
	var row: Dictionary = section(id)
	if row.is_empty() or title.strip_edges().is_empty(): return
	row.title = title.strip_edges().left(100)
	changed.emit()

func remove_section(id: String) -> bool:
	var row: Dictionary = section(id)
	if row.is_empty(): return false
	sections.erase(row)
	for chat: Dictionary in chats:
		if chat.get("section_id") == id: chat.section_id = ""
	changed.emit()
	return true

func toggle_section(id: String) -> void:
	var row: Dictionary = section(id)
	if row.is_empty(): return
	row["collapsed"] = not row.get("collapsed",false)
	changed.emit()

func move_to_section(chat_id: String, section_id: String) -> bool:
	var chat: Dictionary = find(chat_id)
	if chat.is_empty() or (section_id != "" and section(section_id).is_empty()): return false
	chat["section_id"] = section_id
	changed.emit()
	return true

func set_pinned(id: String, pinned: bool) -> void:
	var chat: Dictionary = find(id)
	if chat.is_empty(): return
	chat["pinned"] = pinned
	changed.emit()

func sidebar_groups(query: String = "") -> Array:
	var pinned: Array = []
	var regular: Array = []
	var groups: Array = []
	query = query.strip_edges().to_lower()
	for chat: Dictionary in chats:
		if query != "" and query not in str(chat.title).to_lower(): continue
		if chat.get("pinned",false): pinned.append(chat)
		else: regular.append(chat)
	if not pinned.is_empty(): groups.append({"id":"pinned","title":"Закреплённые","items":pinned,"collapsed":false})
	for group: Dictionary in sections:
		var items: Array = regular.filter(func(chat: Dictionary): return chat.get("section_id","") == group.id)
		if query != "" and items.is_empty() and query not in str(group.title).to_lower(): continue
		groups.append({"id":group.id,"title":group.title,"items":items,"collapsed":false if query != "" else group.get("collapsed",false)})
	var ungrouped: Array = regular.filter(func(chat: Dictionary): return section(str(chat.get("section_id",""))).is_empty())
	if not ungrouped.is_empty(): groups.append({"id":"","title":"Чаты" if not groups.is_empty() else "","items":ungrouped,"collapsed":false})
	return groups

func export_chat(id: String, format: String = "markdown") -> String:
	var chat: Dictionary = find(id)
	if chat.is_empty(): return ""
	if format == "json": return JSON.stringify({"version":1,"chat":chat.duplicate(true)},"  ")
	var rows: Array = chat.get("messages",[])
	if format == "last":
		for index: int in range(rows.size()-1,-1,-1):
			if rows[index].get("role") != "assistant": continue
			var value: String = str(rows[index].get("text",""))
			if value == "": value = str(rows[index].get("stream",{}).get("text",""))
			if value != "": return Markdown.expand_chart_references(value,rows[index].get("events",[]))
		return ""
	var out := PackedStringArray()
	out.append(("# " if format == "markdown" else "")+str(chat.title))
	for row: Dictionary in rows:
		var text: String = str(row.get("text",""))
		if text == "": text = str(row.get("stream",{}).get("text",""))
		if text == "": continue
		var speaker: String = "Вы" if row.get("role") == "user" else "ВИ"
		var date: String = str(row.get("date",""))
		out.append(("## " if format == "markdown" else "")+speaker+(" — "+date if date != "" else ""))
		out.append(Markdown.plain_text(text,row.get("events",[])) if format == "text" and row.get("role") == "assistant" else Markdown.expand_chart_references(text,row.get("events",[])))
	return "\n\n".join(out)+"\n"

func checkpoint_message(summary: String) -> Dictionary:
	return {"who":"ВИ","what":"Earlier conversation checkpoint. Historic context, not proof of current world facts:\n<compacted-summary>\n"+summary+"\n</compacted-summary>"}
