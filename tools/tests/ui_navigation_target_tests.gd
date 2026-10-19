extends SceneTree
const Panels=preload("res://mods/pax_harness/src/ui/game/ui_panels.gd")
class UI extends Node:
	var projects_window: Control
	var projects_button: Button
	var orders_window: Control
	var orders_button: Button
class Main extends Node:
	var ui: UI
	var replacement: Control
	var redirect_enabled:=true
	var toggles:=0
	var last_toggled: Control
	func hud() -> Node:return self
	func toggle_window(window: Control) -> void:
		toggles+=1;last_toggled=window;window.visible=not window.visible
	func redirect_projects() -> void:
		if not redirect_enabled or not ui.projects_window.visible:return
		ui.projects_window.hide()
		if is_instance_valid(replacement) and not replacement.is_queued_for_deletion():replacement.visible=not replacement.visible
class Game extends RefCounted:
	var main: Main
	func scene_root() -> Node:return main
var errors: Array=[]
var checks:=0
var main: Main
var game: Game
func check(value: bool,why: String) -> void:
	checks+=1
	print("UI_NAVIGATION_TARGET_CHECK ",checks,": ",why," => ",value)
	if not value:errors.append(why)
func panel(id: String) -> Dictionary:
	var found: Dictionary=Panels.list_panels(game)
	if not found.get("ok",false):return {}
	for row: Dictionary in found.result.panels:
		if row.id==id:return row
	return {}
func invalid_target(target: Variant,why: String) -> void:
	main.redirect_enabled=false
	main.ui.projects_window.hide()
	main.ui.projects_button.set_meta("win",target)
	if target is Control and is_instance_valid(target):target.show()
	var listed: Dictionary=panel("projects")
	check(listed.is_empty() or not listed.get("visible",false),why+": catalogue never inherits unsafe target visibility")
	if target is Control and is_instance_valid(target):target.hide()
	var before: int=main.toggles
	var opened: Dictionary=Panels.open_panel(game,"projects")
	check((not opened.ok or (opened.result.visible and main.last_toggled==main.ui.projects_window)) and (main.toggles==before or main.last_toggled==main.ui.projects_window),why+": opening never dispatches to an unsafe target")
	if target is Control and is_instance_valid(target):check(not target.visible,why+": unsafe target remains closed")
	main.ui.projects_window.hide()
func _initialize() -> void:run.call_deferred()
func run() -> void:
	main=Main.new();root.add_child(main)
	main.ui=UI.new();main.add_child(main.ui)
	main.ui.projects_window=PanelContainer.new();main.add_child(main.ui.projects_window);main.ui.projects_window.hide()
	main.ui.projects_button=Button.new();main.ui.projects_button.text="Planning console";main.ui.projects_button.tooltip_text="Current native planning view";main.add_child(main.ui.projects_button)
	main.ui.orders_window=PanelContainer.new();main.add_child(main.ui.orders_window);main.ui.orders_window.hide()
	main.ui.orders_button=Button.new();main.ui.orders_button.text="Orders native button";main.add_child(main.ui.orders_button)
	main.replacement=PanelContainer.new();main.add_child(main.replacement);main.replacement.hide()
	main.ui.projects_button.set_meta("win",main.replacement)
	main.ui.projects_window.visibility_changed.connect(main.redirect_projects)
	game=Game.new();game.main=main
	await process_frame
	var listed: Dictionary=panel("projects")
	check(listed.get("id","")=="projects" and listed.get("title","")=="Planning console" and not listed.get("visible",true),"redirected catalogue keeps stable ID and uses the actual native navigation caption")
	var opened: Dictionary=Panels.open_panel(game,"projects")
	check(opened.get("ok",false) and opened.result.get("visible",false) and main.replacement.visible and not main.ui.projects_window.visible,"opening native navigation accepts actual replacement visibility instead of panel_not_visible")
	check(main.toggles==1 and main.last_toggled==main.ui.projects_window,"redirected opening uses the registered native window navigation route")
	listed=panel("projects")
	check(listed.get("visible",false),"catalogue reads visible replacement while the superseded native window remains hidden")
	var before: int=main.toggles
	opened=Panels.open_panel(game,"projects")
	check(opened.get("ok",false) and opened.result.get("visible",false) and main.replacement.visible and main.toggles==before,"reopening an effective visible target is idempotent and cannot close it")
	main.ui.projects_button.text=""
	listed=panel("projects")
	check(listed.get("title","")=="Current native planning view","a redirected native icon-only button supplies its observed tooltip as the title")
	main.ui.projects_button.text="Planning console"
	var old_target: Control=main.replacement
	var rebound:=PanelContainer.new();main.add_child(rebound);rebound.hide()
	main.ui.projects_button.set_meta("win",rebound);main.replacement=rebound
	listed=panel("projects")
	check(not listed.get("visible",true),"rebinding native metadata does not inherit the old visible target")
	opened=Panels.open_panel(game,"projects")
	check(opened.get("ok",false) and rebound.visible and old_target.visible and main.last_toggled==main.ui.projects_window,"opening resolves rebound metadata afresh and uses native navigation")
	main.redirect_enabled=false;main.ui.projects_window.show();rebound.hide();main.redirect_enabled=true
	before=main.toggles;opened=Panels.open_panel(game,"projects")
	check(opened.get("ok",false) and rebound.visible and main.ui.projects_window.visible and main.toggles==before+1 and main.last_toggled==rebound,"a hidden effective target can open through native HUD when the superseded native panel is already visible")
	main.ui.projects_window.hide()
	before=main.toggles
	opened=Panels.open_panel(game,"orders")
	check(opened.get("ok",false) and main.ui.orders_window.visible and main.toggles==before+1 and main.last_toggled==main.ui.orders_window,"regular native panels retain their original opening behavior")
	before=main.toggles;opened=Panels.open_panel(game,"orders")
	check(opened.get("ok",false) and main.ui.orders_window.visible and main.toggles==before,"regular native panel opening remains idempotent")
	check(panel("orders").get("title","")==Panels.L.text(Panels.WINDOWS["orders"][1]),"ordinary panels keep their fixed native catalogue title")
	check(not Panels.open_panel(game,"arbitrary/path").ok,"model-supplied paths are not panel IDs")
	var foreign_root:=Node.new();root.add_child(foreign_root)
	var foreign:=PanelContainer.new();foreign_root.add_child(foreign)
	invalid_target(foreign,"foreign-root metadata")
	var orphan:=PanelContainer.new()
	invalid_target(orphan,"orphan metadata")
	orphan.free()
	var deleting:=PanelContainer.new();main.add_child(deleting);deleting.queue_free()
	invalid_target(deleting,"queued-for-deletion metadata")
	var noncontrol:=Node.new();main.add_child(noncontrol)
	invalid_target(noncontrol,"non-Control node metadata")
	invalid_target("res://mods/anything/arbitrary.gd","path-string metadata")
	var freed:=PanelContainer.new();main.add_child(freed);main.ui.projects_button.set_meta("win",freed);freed.free()
	listed=panel("projects")
	check(listed.is_empty() or not listed.get("visible",false),"freed metadata cannot supply effective window visibility")
	opened=Panels.open_panel(game,"projects")
	check(not opened.ok or (opened.result.visible and main.last_toggled==main.ui.projects_window),"freed metadata cannot be used as an action target")
	main.ui.projects_window.hide()
	var viewport:=SubViewport.new();main.add_child(viewport)
	var other_viewport:=PanelContainer.new();viewport.add_child(other_viewport)
	invalid_target(other_viewport,"different-viewport metadata")
	main.ui.projects_button.remove_meta("win");main.redirect_enabled=false
	opened=Panels.open_panel(game,"projects")
	check(opened.get("ok",false) and main.ui.projects_window.visible,"missing native metadata falls back to the registered native panel")
	main.queue_free();foreign_root.queue_free();await process_frame
	print("UI_NAVIGATION_TARGET_TESTS ","PASS" if errors.is_empty() else errors,"; ",checks," checks");quit(0 if errors.is_empty() else 1)
