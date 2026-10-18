extends Node
const MOD_ID := "pax_harness"
## Scoped presentation translations. Never writes user text or world identities.
static var _ru: Dictionary = {}
static var _en: Dictionary = {}
static var _keys: Dictionary = {}
static var _reverse: Dictionary = {}
static var _pattern: RegEx
static var forced_language := ""
var roots: Callable
var _elapsed := 0.0
var _language := ""
var _language_source: WeakRef
signal language_changed
static func configure(ru: Dictionary, en: Dictionary) -> void:
	_ru = ru; _en = en; _keys.clear(); _reverse.clear()
	var fragments: Array = []
	for key: String in ru:
		_keys[str(ru[key])] = key
		if key.ends_with("_language"): continue
		if en.has(key): _reverse[str(en[key])] = str(ru[key])
		if str(ru[key]).length() >= 4 and not str(ru[key]).contains("%"):
			fragments.append(str(ru[key]))
	fragments.sort_custom(func(a: String,b: String): return a.length() > b.length())
	var alternatives: PackedStringArray = []
	for fragment: String in fragments:
		var escaped := ""
		for character: String in fragment:
			if character in "\\.^$|?*+()[]{}": escaped += "\\"
			escaped += character
		alternatives.append(escaped)
	_pattern = RegEx.new()
	if not alternatives.is_empty(): _pattern.compile("|".join(alternatives))
static func language() -> String:
	if forced_language != "": return normalize_language(forced_language)
	var tree: MainLoop = Engine.get_main_loop()
	if tree is SceneTree:
		var api: Node = tree.root.get_node_or_null("Pax")
		if api != null:
			var game: Variant = api.get("game")
			if game is Object and game.has_method("language"):
				return normalize_language(str(game.call("language")))
			if api.has_method("tr_key"):
				var code: String = str(api.call("tr_key","pax_harness_language"))
				if code in ["ru","en"]: return normalize_language(code)
	return "en"
static func normalize_language(code: String) -> String:
	return "ru" if code.to_lower().begins_with("ru") else "en"
static func text(source: String) -> String:
	if language() == "ru": return _native_text(str(_keys[source]),source) if _keys.has(source) else source
	if _keys.has(source): return _native_text(str(_keys[source]),str(_en.get(_keys[source],source)))
	if _pattern == null or not _pattern.is_valid(): return source
	var result := ""; var offset := 0
	for match_: RegExMatch in _pattern.search_all(source):
		result += source.substr(offset,match_.get_start()-offset)+text(match_.get_string())
		offset = match_.get_end()
	return result+source.substr(offset)
static func _native_text(key: String, fallback: String) -> String:
	if forced_language != "": return fallback
	var tree: MainLoop = Engine.get_main_loop()
	if tree is SceneTree:
		var api: Node = tree.root.get_node_or_null("Pax")
		if api != null and api.has_method("tr_key"):
			var translated: String = str(api.call("tr_key",key))
			if translated != key: return translated
	return fallback
func _listen_to_game_language() -> void:
	var source: Object
	var tree: MainLoop = Engine.get_main_loop()
	if tree is SceneTree:
		var api: Node = tree.root.get_node_or_null("Pax")
		var game: Variant = api.get("game") if api != null else null
		if game is Object and game.has_method("scene_root"):
			var main: Variant = game.call("scene_root")
			if main is Node and "ui" in main and main.ui is Object and "menu_node" in main.ui:
				source = main.ui.menu_node
	if source == null or not source.has_signal("language_changed"): return
	if _language_source != null and _language_source.get_ref() == source: return
	_language_source = weakref(source)
	if not source.is_connected("language_changed",_game_language_changed):
		source.connect("language_changed",_game_language_changed,CONNECT_DEFERRED)
func _game_language_changed(_code: String) -> void:
	_language = language(); refresh(true)
	language_changed.emit()
static func canonical(source: String) -> String:
	return str(_reverse.get(source,source))
static func bind(node: Node, property: String, parts: Array) -> void:
	# Canonical UI fragments and opaque values stay separate in both directions.
	node.set_meta("mod_i18n_binding_"+MOD_ID+"_"+property,parts.duplicate(true))
	node.set(property,render_parts(parts))
static func render_parts(parts: Array) -> String:
	var result := ""
	for part: Variant in parts:
		if part is Dictionary and part.has("value"): result += str(part.value)
		elif part is Dictionary and part.has("format"): result += text(str(part.format)) % part.get("args",[])
		else: result += text(str(part))
	return result
func setup(provider: Callable) -> void:
	roots = provider; process_mode = Node.PROCESS_MODE_ALWAYS
	_language = language(); refresh.call_deferred()
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.3: return
	_elapsed = 0.0
	_listen_to_game_language()
	var changed: bool = _language != language()
	_language = language()
	refresh(changed)
	if changed: language_changed.emit()
func refresh(redraw: bool = false) -> void:
	if not roots.is_valid(): return
	for root: Variant in roots.call():
		if not root is Node or not is_instance_valid(root): continue
		var controls: Array = [root]
		if MOD_ID != "adam_eve": root.set_meta("mod_i18n_scope",MOD_ID)
		while not controls.is_empty():
			var node: Node = controls.pop_back()
			if node is Node3D or node is SubViewport: continue
			if node.is_queued_for_deletion() or node.get_meta("mod_i18n_scope",MOD_ID) != MOD_ID: continue
			controls.append_array(node.get_children())
			if not node is Control and not node is Window: continue
			if not node.get_meta("mod_user_text",false) or node.has_meta("mod_i18n_binding_"+MOD_ID+"_text"):
				if node is Label or node is Button or node is RichTextLabel: _property(node,"text")
			if not node.get_meta("mod_user_tooltip",false) or node.has_meta("mod_i18n_binding_"+MOD_ID+"_tooltip_text"): _property(node,"tooltip_text")
			if node is Window: _property(node,"title")
			if node is AcceptDialog and not node.get_meta("mod_user_text",false): _property(node,"dialog_text")
			if node is LineEdit or node is TextEdit: _property(node,"placeholder_text")
			if node is OptionButton or node is PopupMenu:
				for index: int in node.item_count:
					var current: String = node.get_item_text(index)
					var key: String = "item_"+str(index)
					node.set_item_text(index,_translated(node,key,current))
			if redraw and node is Control:
				if node.has_method("refresh_locale"): node.call("refresh_locale")
				node.queue_redraw()
func _property(node: Node, property: String) -> void:
	if not property in node: return
	var binding: Variant = node.get_meta("mod_i18n_binding_"+MOD_ID+"_"+property) if node.has_meta("mod_i18n_binding_"+MOD_ID+"_"+property) else null
	if binding is Array:
		node.set(property,render_parts(binding)); return
	var value: Variant = node.get(property)
	if value is String: node.set(property,_translated(node,property,value))
func _translated(node: Node, property: String, current: String) -> String:
	var key := "mod_i18n_"+MOD_ID+"_"+property
	var previous: Array = node.get_meta(key,[])
	var source: String = str(previous[0]) if previous.size() == 3 and current == previous[1] else str(_reverse.get(current,current))
	if previous.size() == 3 and current == previous[1] and _language == previous[2]: return current
	var result: String = text(source)
	node.set_meta(key,[source,result,_language]); return result
