extends RefCounted
## Prefer this mod's explicit state, even when its chat list is intentionally empty.
static func choose(own: Dictionary, all_mods: Dictionary) -> Dictionary:
	if own.has("chat_sessions"): return own.duplicate(true)
	var legacy: Variant = all_mods.get("prompt_lab_local",{})
	if legacy is Dictionary and legacy.has("chat_sessions"):
		return {"chat_sessions":legacy.chat_sessions.duplicate(true),"order_archive":legacy.get("order_archive",{}).duplicate(true),"imported_from":"prompt_lab_local"}
	return own.duplicate(true)
