extends RefCounted
## Counts from API usage; wall-clock timings from real runtime events.
static func normalize(usage: Dictionary) -> Dictionary:
	var known: bool = usage.has("prompt_tokens") or usage.has("input_tokens")
	var input: int = int(usage.get("prompt_tokens",usage.get("input_tokens",0)))
	if not usage.has("prompt_tokens") and usage.has("input_tokens"):
		input += int(usage.get("cache_read_input_tokens",0))+int(usage.get("cache_creation_input_tokens",0))
	var output: int = int(usage.get("completion_tokens",usage.get("output_tokens",0)))
	var details: Dictionary = usage.get("prompt_tokens_details",usage.get("input_tokens_details",{})) if usage.get("prompt_tokens_details",usage.get("input_tokens_details",{})) is Dictionary else {}
	var cached: int = int(usage.get("prompt_cache_hit_tokens",details.get("cached_tokens",usage.get("cache_read_input_tokens",0))))
	var cache_known: bool = usage.has("prompt_cache_hit_tokens") or details.has("cached_tokens") or usage.has("cache_read_input_tokens")
	cached = clampi(cached,0,maxi(0,input))
	var output_details: Dictionary = usage.get("completion_tokens_details",{}) if usage.get("completion_tokens_details") is Dictionary else {}
	return {"known":known,"input":input,"output":output,"output_known":usage.has("completion_tokens") or usage.has("output_tokens"),"total":int(usage.get("total_tokens",input+output)),"cached":cached,
		"cache_known":cache_known,"uncached":input-cached,"reasoning":int(output_details.get("reasoning_tokens",0)),"reasoning_known":output_details.has("reasoning_tokens")}

static func summarize(chat: Dictionary) -> Dictionary:
	var result: Dictionary = {"turns":0,"steps":0,"tools":0,"llm_ms":0,"tool_ms":0,"input":0,"output":0,"total":0,
		"cached":0,"uncached":0,"reasoning":0,"requests":0,"usage_requests":0,"cache_known":false,"reasoning_known":false,"cache_input":0,"api_llm_ms":0,"last":{}}
	for message: Dictionary in chat.get("messages",[]):
		if message.get("role") == "user": result.turns += 1
		for event: Dictionary in message.get("events",[]):
			var elapsed: int = int(event.get("elapsed_ms",0))
			if event.get("status") == "running": elapsed = maxi(0,Time.get_ticks_msec()-int(event.get("started_ms",Time.get_ticks_msec())))
			if event.kind == "step": result.steps += 1; result.llm_ms += elapsed
			elif event.kind == "tool": result.tools += 1; result.tool_ms += elapsed
		for request: Dictionary in message.get("requests",[]):
			result.requests += 1
			result.last = request
			var usage: Dictionary = request.get("tokens",{})
			if not usage.get("known",false): continue
			result.usage_requests += 1
			for field: String in ["input","output","total","cached","uncached","reasoning"]: result[field] += int(usage.get(field,0))
			result.cache_known = result.cache_known or usage.get("cache_known",false)
			if usage.get("cache_known",false): result.cache_input += int(usage.get("input",0))
			result.reasoning_known = result.reasoning_known or usage.get("reasoning_known",false)
			result.api_llm_ms += int(request.get("elapsed_ms",0))
	result["cache_percent"] = 100.0*result.cached/result.cache_input if result.cache_input > 0 else 0.0
	var measured_ms: int = result.api_llm_ms if result.api_llm_ms > 0 else result.llm_ms
	result["tps"] = result.output/(measured_ms/1000.0) if measured_ms > 0 and result.usage_requests > 0 else 0.0
	return result

static func context_parts(request: Dictionary) -> Dictionary:
	var tokens: int = int(request.get("tokens",{}).get("input",0))
	var parts: Dictionary = request.get("parts",{})
	var chars: int = int(parts.get("system",0))+int(parts.get("tools",0))+int(parts.get("messages",0))
	if chars <= 0: return {"system":0,"tools":0,"messages":tokens}
	var system: int = roundi(tokens*float(parts.get("system",0))/chars)
	var tools: int = roundi(tokens*float(parts.get("tools",0))/chars)
	return {"system":system,"tools":tools,"messages":maxi(0,tokens-system-tools)}

static func compact(number: int) -> String:
	if number >= 1000000: return ("%.1fM" % (number/1000000.0)).replace(".0M","M")
	if number >= 1000: return ("%.1fK" % (number/1000.0)).replace(".0K","K")
	return str(number)

static func exact(number: int) -> String:
	var digits: String = str(number)
	var groups := PackedStringArray()
	while digits.length() > 3:
		groups.insert(0,digits.right(3))
		digits = digits.left(digits.length()-3)
	groups.insert(0,digits)
	return " ".join(groups)
