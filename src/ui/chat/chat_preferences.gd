extends RefCounted
## Display/input preferences never alter model requests or saved conversation text.
const DEFAULTS := {"dialog_font_size":15,"dialog_display":"detailed","technical_details":true,"busy_send":"queue","usage_display":"detailed"}
const SHORTCUTS := {"send":KEY_ENTER,"new_chat":KEY_MASK_CTRL|KEY_N,"search":KEY_MASK_CTRL|KEY_F,"stop":KEY_MASK_CTRL|KEY_PERIOD}
static func value(owner: Node, key: String) -> Variant:
	var fallback: Variant = DEFAULTS.get(key)
	var result: Variant = owner.get_setting(key,fallback) if owner.has_method("get_setting") else fallback
	if key == "dialog_font_size": return clampi(int(result),10,28)
	var choices: Dictionary = {"dialog_display":["detailed","compact","answers"],"busy_send":["queue","interrupt","wait"],"usage_display":["detailed","basic","hidden"]}
	if choices.has(key) and not result in choices[key]: return fallback
	return result
static func shortcut(owner: Node, action: String) -> int:
	return int(owner.get_setting("shortcut_"+action,SHORTCUTS[action])) if owner.has_method("get_setting") else int(SHORTCUTS[action])
static func matches(owner: Node, action: String, event: InputEventKey) -> bool:
	return event.pressed and not event.echo and int(event.get_keycode_with_modifiers()) == shortcut(owner,action)
static func label(code: int) -> String:
	var event := InputEventKey.new(); event.keycode = code & KEY_CODE_MASK
	event.ctrl_pressed = (code & KEY_MASK_CTRL) != 0; event.alt_pressed = (code & KEY_MASK_ALT) != 0
	event.shift_pressed = (code & KEY_MASK_SHIFT) != 0; event.meta_pressed = (code & KEY_MASK_META) != 0
	return event.as_text_keycode()
