extends RefCounted
## Model-aware local-window overrides. Never owns nonzero external settings.
## Call after native settings reload, before compaction/fit and usage snapshots.
## Canonical configured API base. HTTP is allowed only on loopback.
## No redirects/userinfo/query/fragment may widen a discovered capability scope.
static func api_base(base_url: String) -> String:
	var base: String = base_url.strip_edges()
	while base.ends_with("/"): base = base.left(-1)
	if "?" in base or "#" in base or "\\" in base: return ""
	for character: String in base:
		if character.unicode_at(0) <= 32 or character.unicode_at(0) == 127: return ""
	var tls: bool = base.begins_with("https://")
	if not tls and not base.begins_with("http://"): return ""
	var rest: String = base.substr(8 if tls else 7)
	var slash: int = rest.find("/")
	var authority: String = rest if slash < 0 else rest.left(slash)
	var path: String = "" if slash < 0 else rest.substr(slash)
	if authority.is_empty() or "@" in authority: return ""
	var match_: RegExMatch = RegEx.create_from_string("^(\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?$").search(authority)
	if match_ == null: return ""
	var host: String = match_.get_string(1).to_lower()
	if ".." in host: return ""
	var port: String = match_.get_string(2)
	if port != "" and (int(port) < 1 or int(port) > 65535): return ""
	if not tls and host not in ["localhost","127.0.0.1","[::1]"]: return ""
	return ("https://" if tls else "http://")+host+(":"+port if port != "" else "")+path

## Backwards-compatible name for generic URL validation; no vendor allowlist.
static func matches_metadata_base(base_url: String) -> bool:
	return api_base(base_url) != ""

## Return independent metadata so query adaptation cannot alter the defaults.
## Entries without provider_host are deliberately unscoped local fixtures.
static func resolve(base_url: String, model: String, defaults: Dictionary) -> Dictionary:
	var selected: String = model.strip_edges()
	var entry: Variant = defaults.get(selected,{})
	if not defaults.has(selected):
		var legacy: Variant = defaults.get(selected.to_lower(),{})
		# Case-folded lookup is only for explicit unscoped old fixtures, never discovery.
		if legacy is Dictionary and not legacy.has("api_base") and not legacy.has("provider_host"): entry = legacy
	if not entry is Dictionary: return {}
	if entry.has("api_base"):
		if not entry.api_base is String: return {}
		var actual: String = api_base(base_url)
		if actual == "" or actual != api_base(entry.api_base): return {}
	elif entry.has("provider_host"):
		# A host alone cannot scope API paths/accounts; old shipped metadata is obsolete.
		return {}
	return entry.duplicate(true)

var _provider: Node
var _owned := false
var _owned_value := 0
var _prior_value := 0
var _signature := ""

func sync(provider: Node, defaults: Dictionary) -> Dictionary:
	if not is_instance_valid(provider):
		detach()
		return {"changed":false,"owned":false,"context_tokens":0,"reason":"provider_unavailable"}
	if _provider != provider:
		detach()
		_provider = provider
	var model: String = str(provider.get("model")).strip_edges()
	var base: String = str(provider.get("base_url")).strip_edges()
	var signature: String = base+"|"+model
	var current: int = int(provider.get("local_window"))
	var entry: Dictionary = resolve(base,model,defaults)
	var tokens := 0
	if entry is Dictionary:
		var raw: Variant = entry.get("context_tokens",0)
		if (raw is int or raw is float) and is_finite(float(raw)) and float(raw) == floorf(float(raw)) and raw > 0 and raw <= 10000000:
			tokens = int(raw)
	# A live external/LM-Studio/user update supersedes our earlier override.
	# A native reset to zero is eligible for reapplying this model's metadata.
	if _owned and current != _owned_value:
		_owned = false
		_owned_value = 0
		_prior_value = current
	var changed := false
	if tokens > 0 and (current == 0 or _owned):
		if not _owned: _prior_value = current
		changed = current != tokens
		if changed: provider.set("local_window",tokens)
		_owned = true
		_owned_value = tokens
	elif _owned:
		# Unknown model or mismatching endpoint: never retain a previous model's 1M.
		changed = current != _prior_value
		if changed: provider.set("local_window",_prior_value)
		_owned = false
		_owned_value = 0
	_signature = signature
	return {"changed":changed,"owned":_owned,"context_tokens":int(provider.get("local_window")),"metadata_context_tokens":tokens,"model":model,"provider_host":hostname(base),"reason":"model_metadata" if _owned else "external_window" if int(provider.get("local_window")) > 0 else "native_fallback"}

func detach() -> void:
	if is_instance_valid(_provider) and _owned and int(_provider.get("local_window")) == _owned_value:
		_provider.set("local_window",_prior_value)
	_provider = null
	_owned = false
	_owned_value = 0
	_prior_value = 0
	_signature = ""

static func hostname(base: String) -> String:
	var authority: String = base.strip_edges().to_lower()
	var scheme: int = authority.find("://")
	if scheme >= 0: authority = authority.substr(scheme+3)
	authority = authority.get_slice("/",0).get_slice("?",0).get_slice("#",0)
	var at: int = authority.rfind("@")
	if at >= 0: authority = authority.substr(at+1)
	if authority.begins_with("["):
		var end: int = authority.find("]")
		return authority.substr(0,end+1) if end >= 0 else ""
	return authority.get_slice(":",0).trim_suffix(".")
