extends SceneTree
const Interface=preload("res://mods/pax_harness/src/ui/game/mod_interface.gd")
const Logic=preload("res://mods/qa_window_logic/main.gd")
const Foreign=preload("res://mods/qa_window_theme/main.gd")
class World extends Node:
	var mod_windows: Array=[]
	var opens:=0
	func hud() -> Node:return self
	func toggle_window(window: Control) -> void:opens+=1;window.visible=not window.visible
class Game extends RefCounted:
	var world: Node
	func scene_root() -> Node:return world
class API extends Node:
	var mods: Dictionary={}
	func get_mod(id: String) -> Node:return mods.get(id)
class TabMod extends Node:
	var tab_caption:="Lazy stable tab"
	var tabs_enabled:=true
	var opens:=0
	func open_tab() -> void:opens+=1
	func ui_tabs() -> Array:return [{"id":"lazy","caption":tab_caption,"fn":Callable(self,"open_tab")}] if tabs_enabled else []
var checks:=0
var failures: Array=[]
var interface: RefCounted
var tab_mod: TabMod
var logic: Node
func check(value: bool,why: String) -> void:
	checks+=1
	if not value:failures.append(why)
func inspect_tab(search: String="") -> Dictionary:return interface.inspect("qa_stable_tabs",tab_mod,{"search":search,"limit":100})
func row(search: String,kind: String="") -> Dictionary:
	for control: Dictionary in inspect_tab(search).result.controls:
		if kind=="" or control.kind==kind:return control
	return {}
func menu_row() -> Dictionary:return interface.inspect("qa_window_logic",logic,{"search":"Stable menu"}).result.controls[0]
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=World.new();root.add_child(world)
	logic=Logic.new();world.add_child(logic)
	var foreign:=Foreign.new();world.add_child(foreign)
	tab_mod=TabMod.new();world.add_child(tab_mod)
	var api:=API.new();api.mods={"qa_stable_tabs":tab_mod,"qa_window_logic":logic};root.add_child(api)
	var game:=Game.new();game.world=world
	interface=Interface.new();interface.setup(api,game)
	var action:=Button.new();action.text="Stable action";tab_mod.add_child(action);action.pressed.connect(logic.clicked)
	var same_caption:=Button.new();same_caption.text="Stable action";tab_mod.add_child(same_caption)
	var grid:=GridContainer.new();grid.columns=2;tab_mod.add_child(grid)
	var caption:=Label.new();caption.text="Water stable row";grid.add_child(caption)
	var value:=SpinBox.new();value.min_value=0;value.max_value=100;value.value=7;grid.add_child(value)
	var menu:=MenuButton.new();menu.text="Stable menu";logic.add_child(menu)
	var popup:=menu.get_popup();popup.add_item("First actual option",41);popup.id_pressed.connect(logic.menu_selected)
	var registered:=PanelContainer.new();registered.set_meta("window_float_key","mod:Registered stable panel");world.add_child(registered);registered.hide();world.mod_windows.append(registered)
	var registered_action:=Button.new();registered_action.text="Registered action";registered.add_child(registered_action);registered_action.pressed.connect(logic.clicked)
	await process_frame
	var first:=inspect_tab();var second:=inspect_tab()
	check(first.result==second.result,"two unchanged inspections have identical result payloads and opaque refs")
	var ref_count: int=interface.refs.size();var unchanged:=true
	for iteration: int in 25:
		if inspect_tab().result!=second.result:unchanged=false
	check(unchanged and interface.refs.size()==ref_count,"repeated unchanged reads stay stable without allocating additional references")
	var duplicates: Array=inspect_tab("Stable action").result.controls
	check(duplicates.size()==2 and duplicates[0].ref!=duplicates[1].ref,"different controls with the same caption never share a reference")
	var own_action: Dictionary=row("Stable action")
	var other_owner: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Stable action"})
	check(other_owner.result.total==1 and other_owner.result.controls[0].ref!=own_action.ref,"one observed control receives distinct references for different mod identities")
	check(row("Stable action").ref==own_action.ref,"inspection by a different mod does not replace the original mod's stable ref")
	var old_action_ref: String=own_action.ref
	action.text="Changed stable action"
	var changed_action: Dictionary=row("Changed stable action")
	check(changed_action.ref!=old_action_ref and changed_action.text=="Changed stable action","changed control labels are visible and get a fresh ref")
	check(not interface.act({"ref":old_action_ref,"action":"press"}).ok and logic.clicks==0,"a reused-control label change still rejects the obsolete ref")
	check(row("Changed stable action").ref==changed_action.ref,"a changed label's new snapshot becomes stable on subsequent inspection")
	var old_value: Dictionary=row("Water stable row","SpinBox")
	value.value=9
	var changed_value: Dictionary=row("Water stable row","SpinBox")
	check(old_value.value==7 and changed_value.value==9 and old_value!=changed_value,"an actual value change remains visible in the result used by loop detection")
	check(row("Water stable row","SpinBox")==changed_value,"a new numeric value then produces identical repeated observations")
	caption.text="Fuel stable row"
	var changed_context: Dictionary=row("Fuel stable row","SpinBox")
	check(changed_context.ref!=changed_value.ref and changed_context.context==["Fuel stable row"],"changed row context gets a fresh ref and current rendered identity")
	check(not interface.act({"ref":changed_value.ref,"action":"set_number","number":10}).ok and value.value==9,"an obsolete row context cannot redirect a numerical action")
	var tab: Dictionary=row("Lazy stable tab","ModPanel")
	check(row("Lazy stable tab","ModPanel")==tab,"unchanged declared lazy tabs reuse their references")
	tab_mod.tab_caption="Renamed stable tab"
	var changed_tab: Dictionary=row("Renamed stable tab","ModPanel")
	check(changed_tab.ref!=tab.ref and not interface.act({"ref":tab.ref,"action":"press"}).ok,"changed declared tab captions get new refs and invalidate the old navigation ref")
	check(interface.act({"ref":changed_tab.ref,"action":"press"}).ok and tab_mod.opens==1,"a current stable lazy-tab ref still dispatches its current callback")
	var closed_menu: Dictionary=menu_row()
	check(menu_row()==closed_menu,"closed native menus produce stable observations")
	interface.act({"ref":closed_menu.ref,"action":"press"})
	var open_menu: Dictionary=menu_row()
	check(open_menu!=closed_menu and open_menu.menu_open and open_menu.options[0].id==41,"opening a menu exposes its real state and items as changed observation")
	check(menu_row()==open_menu,"an unchanged open native popup reuses its observed item snapshot ref")
	popup.set_item_text(0,"Updated actual option")
	var changed_menu: Dictionary=menu_row()
	check(changed_menu.ref!=open_menu.ref and changed_menu.options[0].text=="Updated actual option","an actual popup-item change gets a fresh reference and visible result")
	check(not interface.act({"ref":open_menu.ref,"action":"select","index":0}).ok and logic.menu_id==-1,"an obsolete menu item snapshot remains rejected after ref reuse")
	check(interface.act({"ref":changed_menu.ref,"action":"select","index":0}).ok and logic.menu_id==41,"the new stable popup snapshot still dispatches its actual native item")
	popup.hide()
	var registered_first: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Registered stable panel"})
	var registered_second: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Registered stable panel"})
	check(registered_first.result==registered_second.result,"unchanged registered native mod panels reuse their refs and results")
	var registered_ref: String=registered_first.result.controls[0].ref
	interface.act({"ref":registered_ref,"action":"press"})
	var registered_visible: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Registered stable panel"})
	check(registered_visible.result.controls[0].visible and registered_visible.result!=registered_first.result,"registered native window visibility changes remain visible in loop-detection results")
	registered.set_meta("window_float_key","mod:Renamed registered panel")
	var renamed_registered: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Renamed registered panel"})
	check(renamed_registered.result.controls[0].ref!=registered_ref and not interface.act({"ref":registered_ref,"action":"press"}).ok,"registered caption changes allocate a fresh ref and invalidate old navigation")
	registered_ref=renamed_registered.result.controls[0].ref
	var mixed:=Button.new();registered.add_child(mixed);mixed.pressed.connect(foreign.clicked)
	check(interface.inspect("qa_window_logic",logic,{"search":"Renamed registered panel"}).result.total==0 and not interface.act({"ref":registered_ref,"action":"press"}).ok,"foreign gameplay callbacks still revoke cached registered-panel ownership")
	mixed.queue_free();await process_frame
	registered_ref=interface.inspect("qa_window_logic",logic,{"search":"Renamed registered panel"}).result.controls[0].ref
	world.mod_windows.clear()
	check(not interface.act({"ref":registered_ref,"action":"press"}).ok,"a cached panel ref cannot outlive native registry removal")
	var before_hide: Dictionary=row("Changed stable action")
	action.hide()
	check(not interface.act({"ref":before_hide.ref,"action":"press"}).ok,"a stable control ref cannot bypass current visibility checks")
	action.show();api.mods.erase("qa_stable_tabs")
	check(not interface.act({"ref":before_hide.ref,"action":"press"}).ok,"unloading a mod rejects its previously stable control ref")
	api.mods["qa_stable_tabs"]=tab_mod
	interface.setup(api,game)
	check(not interface.act({"ref":before_hide.ref,"action":"press"}).ok and row("Changed stable action").ref!=before_hide.ref,"setup clears reference reuse and expires prior-world refs")
	var removed: Dictionary=row("Changed stable action");action.queue_free();await process_frame
	check(not interface.act({"ref":removed.ref,"action":"press"}).ok,"freed controls cannot retain an actionable stable ref")
	world.queue_free();api.queue_free();await process_frame
	print("STABLE_REF_TESTS ","PASS" if failures.is_empty() else failures,"; ",checks," checks");quit(0 if failures.is_empty() else 1)
