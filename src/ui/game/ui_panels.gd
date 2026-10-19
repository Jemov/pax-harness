extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Fixed native navigation only. Never dispatches a model-provided method/path.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const WINDOWS := {"orders":["orders_window","Приказы"],"projects":["projects_window","Проекты"],"development":["development_window_node","Развитие"],"contacts":["contacts_window","Контакты"],"goals":["list_wrapper","Цели и задачи"],"planets":["planets_window","Планеты"],"inbox":["inbox_window","Переписка"],"resources":["resources_window","Ресурсы"],"diplomacy":["diplomacy_window","Дипломатия"],"chronicle":["chronicle_window","Хроника"],"time_machine":["time_machine_window","Машина времени"],"laws":["laws_window","Законы"],"power":["power_window","Власть"],"special_projects":["special_projects_window","Особые проекты"],"mining":["mining_window","Добыча"],"profile":["profile_window","Профиль"],"science":["science_window","Наука"],"world":["world_window","Мировой рынок"],"wars":["wars_window","Войны"],"threats":["threats_window","Угрозы"],"population":["population_window","Население"],"state":["state_window","Государство"],"trade":["trade_window","Торговля"],"output":["output_window","Производство"],"course":["course_window","Курс государства"],"rewind":["rewind_window","Переход во времени"]}
const GROUPS := {"contacts":["links",0],"inbox":["links",1],"diplomacy":["links",2],"development":["power",0],"wars":["power",1],"threats":["power",2],"trade":["power",3],"output":["power",4],"resources":["power",5],"world":["power",6]}
const SETTINGS := {"settings":"","settings.game":"game","settings.graphics":"graphics","settings.sound":"sound","settings.voice":"voice","settings.ai":"нейросеть","settings.studio":"studio","settings.data":"data"}
const SETTINGS_TITLES := {"settings":"Настройки","settings.game":"Настройки · Игра","settings.graphics":"Настройки · Графика","settings.sound":"Настройки · Звук","settings.voice":"Настройки · Голос","settings.ai":"Настройки · Нейросеть","settings.studio":"Настройки · Студия","settings.data":"Настройки · Сохранения"}
const PROVIDERS := {"settings.brain":"brain","settings.photo":"photo","settings.provider_voice":"voice"}
const PROVIDER_TITLES := {"settings.brain":"Подключение ИИ · Модель","settings.photo":"Подключение ИИ · Изображения","settings.provider_voice":"Подключение ИИ · Озвучка"}

static func main_node(game: RefCounted) -> Node:
	if not is_instance_valid(game) or not game.has_method("scene_root"): return null
	var main: Variant = game.call("scene_root")
	return main if main is Node and is_instance_valid(main) and not main.is_queued_for_deletion() else null

static func _hud(main: Node) -> Object:
	if main == null or not main.has_method("hud"): return null
	var hud: Variant = main.call("hud")
	return hud if hud is Object and is_instance_valid(hud) else null

static func definitions() -> Array:
	var result: Array = []
	for item: Array in [["ui.panels","List actual available game panels with stable IDs. Read this catalogue before ui.open. No UI change, no screenshots.",{},[]],["ui.open","Open ONE registered game panel or settings page by its stable ID from ui.panels. Navigation only: never clicks confirmation/action buttons, changes settings, loads games, or advances time.",{"panel":{"type":"string","minLength":1,"maxLength":80}},["panel"]],["ui.screenshot","Capture the actual GAME viewport once, with Harness chat temporarily hidden. Only for the exact active model with explicit image-input permission. Returns an expiring image attachment reference; never desktop pixels, file paths or base64 text.",{},[]]]:
		result.append({"name":item[0],"id":item[0],"description":item[1],"arguments_schema":{"type":"object","properties":item[2],"required":item[3],"additionalProperties":false},"mutates_world":false,"handler_kind":"public_game_facade","capability":"game_ui_navigation" if item[0]!="ui.screenshot" else "explicit_model_vision","after_state":"Actual available panels, visible UI state, or bounded game-viewport image metadata."})
	result.append({"name":"ui.pointer","id":"ui.pointer","description":"Visible virtual game cursor fallback ONLY when no suitable declared API or observed UI control exists. FIRST receive an actual ui.screenshot image. Use image_id and image-pixel x/y. One action consumes the frame; returns a NEW image for verification. Never uses the system mouse. Player input interrupts. Delivery does not prove gameplay success. Do not click destructive/paid/confirmation actions without player authorization.","arguments_schema":{"type":"object","properties":{"image_id":{"type":"string","minLength":1,"maxLength":64},"action":{"type":"string","enum":["move","click","double_click","drag","scroll"]},"x":{"type":"number","minimum":0},"y":{"type":"number","minimum":0},"to_x":{"type":"number","minimum":0},"to_y":{"type":"number","minimum":0},"button":{"type":"string","enum":["left","right","middle"]},"direction":{"type":"string","enum":["up","down","left","right"]},"amount":{"type":"integer","minimum":1,"maximum":8}},"required":["image_id","action","x","y"],"additionalProperties":false},"mutates_world":true,"handler_kind":"public_game_facade","capability":"explicit_model_vision","after_state":"Input dispatch receipt plus a fresh game image. Read the image and native state to verify effects; never infer a completed transaction from a click."})
	result.append({"name":"ui.keyboard","id":"ui.keyboard","description":"Type Unicode text or an allowed editing/navigation key into the field last focused by ui.pointer. Requires a NEW observed game image_id for each action; returns next screenshot. Viewport only; no system keyboard/clipboard. No Ctrl+C/V/X or system shortcuts. Player input interrupts.","arguments_schema":{"type":"object","properties":{"image_id":{"type":"string","minLength":1,"maxLength":64},"action":{"type":"string","enum":["text","key"]},"text":{"type":"string","minLength":1,"maxLength":2000},"key":{"type":"string","enum":["Enter","Escape","Tab","Backspace","Delete","Left","Right","Up","Down","Home","End","PageUp","PageDown","Space","Ctrl+A","Ctrl+Z","Ctrl+Y"]}},"required":["image_id","action"],"additionalProperties":false},"mutates_world":true,"handler_kind":"public_game_facade","capability":"explicit_model_vision","after_state":"Input dispatch receipt plus a fresh game image; verify the actual field value and outcome."})
	return result

static func list_panels(game: RefCounted) -> Dictionary:
	var main: Node = main_node(game)
	if main == null: return Data.failed("ui.game_unavailable")
	var ui: Variant = Data.property(main,"ui")
	var hud: Object = _hud(main)
	var rows: Array = []
	for id: String in WINDOWS:
		var window: Variant = Data.property(ui,WINDOWS[id][0])
		if window is Control and is_instance_valid(window) and not window.is_queued_for_deletion() and hud != null and hud.has_method("toggle_window"):
			rows.append({"id":id,"title":L.text(WINDOWS[id][1]),"visible":window.is_visible_in_tree()})
	var menu: Variant = Data.property(ui,"menu_node")
	if menu is Node and is_instance_valid(menu) and menu.has_method("_settings_screen") and menu.has_method("open_pause"):
		for id: String in SETTINGS: rows.append({"id":id,"title":L.text(SETTINGS_TITLES[id])})
		if menu.has_method("_provider_screen"):
			for id: String in PROVIDERS: rows.append({"id":id,"title":L.text(PROVIDER_TITLES[id])})
	return Data.success({"panels":rows,"navigation_only":true,"arbitrary_paths_supported":false})

static func open_panel(game: RefCounted, id: String) -> Dictionary:
	if not WINDOWS.has(id) and not SETTINGS.has(id) and not PROVIDERS.has(id): return Data.failed("ui.unknown_panel")
	var found: Dictionary = list_panels(game)
	if not found.get("ok",false): return found
	if not found.result.panels.any(func(row: Dictionary):return row.id==id): return Data.failed("ui.panel_unavailable")
	var main: Node = main_node(game)
	var ui: Variant = Data.property(main,"ui")
	var menu: Variant = Data.property(ui,"menu_node")
	if SETTINGS.has(id) or PROVIDERS.has(id):
		menu.call("open_pause")
		if SETTINGS.has(id): menu.call("_settings_screen",SETTINGS[id] if id!="settings" else "нейросеть")
		else: menu.call("_provider_screen",PROVIDERS[id])
		return Data.success({"panel":id,"visible":bool(Data.property(menu,"visible")),"navigation_only":true,"settings_modified":false})
	var window: Control = Data.property(ui,WINDOWS[id][0])
	var hud: Object = _hud(main)
	if menu is Node and bool(Data.property(menu,"visible")):
		if not menu.has_method("close_button"): return Data.failed("ui.menu_close_unavailable")
		menu.call("close_button")
	if not window.visible:
		if GROUPS.has(id) and hud.has_method("open_from_group"): hud.call("open_from_group",GROUPS[id][0],GROUPS[id][1])
		else: hud.call("toggle_window",window)
	var visible: bool = window.visible
	return Data.success({"panel":id,"visible":visible,"navigation_only":true,"settings_modified":false}) if visible else Data.failed("ui.panel_not_visible")
