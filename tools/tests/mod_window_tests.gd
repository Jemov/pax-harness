extends SceneTree
const Interface=preload("res://mods/pax_harness/src/ui/game/mod_interface.gd")
# Fixture scripts are copied to distinct mod resource roots by the test runner.
const Logic=preload("res://mods/qa_window_logic/main.gd")
const ThemeFixture=preload("res://mods/qa_window_theme/main.gd")
const NativeSound=preload("res://src/ui/Sound.gd")
class World extends Node:
	var mod_windows: Array=[]
	var opens:=0
	var native_clicks:=0
	func hud() -> Node:return self
	func toggle_window(window: Control) -> void:opens+=1;window.visible=not window.visible
	func native_press() -> void:native_clicks+=1
class Game extends RefCounted:
	var root: Node
	func scene_root() -> Node:return root
class API extends Node:
	var logic: Node
	var skin: Node
	func get_mod(id: String) -> Node:return logic if id=="qa_window_logic" else skin
var errors: Array=[]
var checks:=0
func check(value: bool,why: String) -> void:
	checks+=1
	if not value:errors.append(why)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=World.new();root.add_child(world)
	var logic:=Logic.new();world.add_child(logic)
	var skin:=ThemeFixture.new();world.add_child(skin)
	var api:=API.new();api.logic=logic;api.skin=skin;root.add_child(api)
	var game:=Game.new();game.root=world
	var interface:=Interface.new();interface.setup(api,game)
	var window:=PanelContainer.new();window.set_meta("window_float_key","mod:Factory controls");world.add_child(window);world.mod_windows.append(window)
	var column:=VBoxContainer.new();window.add_child(column)
	var label:=Label.new();label.text="Actual factory status";column.add_child(label)
	var button:=Button.new();button.text="Factory action";column.add_child(button);button.pressed.connect(logic.clicked);button.mouse_entered.connect(skin.hover)
	var native:=Button.new();native.text="Native action";world.add_child(native);native.pressed.connect(world.native_press);native.mouse_entered.connect(logic.hover)
	window.hide();await process_frame
	var found: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Factory controls"})
	check(found.ok and found.result.total==1 and found.result.controls[0].kind=="RegisteredModPanel","registered lazy window is discoverable while its native navigation is folded")
	var ref: String=found.result.controls[0].ref
	check(interface.act({"ref":ref,"action":"press"}).ok and world.opens==1 and window.visible,"opening uses the real native window-toggle operation")
	check(interface.inspect("qa_window_logic",logic,{"search":"Actual factory status"}).result.total==1,"plain labels in a registered owned window remain readable despite foreign hover decoration")
	found=interface.inspect("qa_window_logic",logic,{"search":"Factory action"});ref=found.result.controls[0].ref
	check("press" in found.result.controls[0].actions and interface.act({"ref":ref,"action":"press"}).ok and logic.clicks==1,"own window actions execute their real mod callbacks")
	found=interface.inspect("qa_window_logic",logic,{"search":"Native action"})
	check(found.result.total==1 and found.result.controls[0].actions==["hover"],"hover decoration cannot grant press access to another owner's button")
	check(not interface.act({"ref":found.result.controls[0].ref,"action":"press"}).ok and world.native_clicks==0,"an attempted press through a hover-only ownership ref is rejected")
	found=interface.inspect("qa_window_logic",logic,{"search":"Factory controls"});ref=found.result.controls[0].ref
	window.set_meta("window_float_key","mod:Changed caption")
	check(not interface.act({"ref":ref,"action":"press"}).ok,"a changed registration caption invalidates navigation refs")
	window.set_meta("window_float_key","mod:Factory controls")
	var foreign:=Button.new();foreign.text="Another mod action";column.add_child(foreign);foreign.pressed.connect(skin.clicked)
	check(interface.inspect("qa_window_logic",logic,{"search":"Factory controls"}).result.total==0,"mixed foreign gameplay callbacks do not become an owned window")
	foreign.queue_free();await process_frame
	found=interface.inspect("qa_window_logic",logic,{"search":"Factory controls"});ref=found.result.controls[0].ref;world.mod_windows.clear()
	check(not interface.act({"ref":ref,"action":"press"}).ok,"a window removed from the game's registry cannot be opened")
	var layer:=CanvasLayer.new();world.add_child(layer)
	var overlay:=VBoxContainer.new();layer.add_child(overlay)
	var sound:=NativeSound.new();world.add_child(sound)
	var status:=Label.new();status.text="Owned overlay status";overlay.add_child(status)
	var action:=Button.new();action.text="Overlay action";overlay.add_child(action);action.pressed.connect(logic.clicked);action.pressed.connect(sound.clicked)
	await process_frame
	check(interface.inspect("qa_window_logic",logic,{"search":"Owned overlay status"}).result.total==1,"native button sound decoration preserves plain overlay labels")
	var native_logic:=Button.new();native_logic.pressed.connect(world.native_press);overlay.add_child(native_logic)
	check(interface.inspect("qa_window_logic",logic,{"search":"Owned overlay status"}).result.total==0,"a foreign gameplay callback still rejects mixed overlay ownership")
	var pointer_label:=Label.new();pointer_label.text="Clickable mod row";pointer_label.mouse_filter=Control.MOUSE_FILTER_STOP;pointer_label.size=Vector2(180,40);world.add_child(pointer_label);pointer_label.gui_input.connect(logic.pointer)
	var caption:=Label.new();caption.text="Actual card resource";pointer_label.add_child(caption)
	var private_field:=LineEdit.new();private_field.secret=true;private_field.text="must-not-appear";pointer_label.add_child(private_field)
	await process_frame
	found=interface.inspect("qa_window_logic",logic,{"search":"Clickable mod row"});ref=found.result.controls[0].ref
	check("click_at" in found.result.controls[0].actions,"plain controls with an observed mod gui_input callback expose click_at")
	check("Actual card resource" in found.result.controls[0].context and not "must-not-appear" in str(found.result.controls[0]),"clickable cards include their rendered captions without exposing private inputs")
	check(interface.act({"ref":ref,"action":"click_at","x":10,"y":10}).ok and logic.pointer_presses==1 and logic.pointer_releases==1 and logic.pointer_position==Vector2(10,10),"click dispatches one press and release through the real gui_input signal")
	check(not interface.act({"ref":ref,"action":"click_at","x":-1,"y":10}).ok and logic.pointer_presses==1,"out-of-bounds pointer input is rejected")
	pointer_label.gui_input.connect(skin.pointer)
	found=interface.inspect("qa_window_logic",logic,{"search":"Clickable mod row"})
	check(not "click_at" in found.result.controls[0].actions and not interface.act({"ref":ref,"action":"click_at","x":10,"y":10}).ok,"a foreign gui_input callback cannot inherit pointer access")
	pointer_label.gui_input.disconnect(skin.pointer);pointer_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	found=interface.inspect("qa_window_logic",logic,{"search":"Clickable mod row"})
	check(not "click_at" in found.result.controls[0].actions,"ignored controls do not expose pointer input")
	var menu:=MenuButton.new();menu.text="Observed profile menu";menu.size=Vector2(160,30);world.add_child(menu)
	var popup:=menu.get_popup();popup.add_item("Actual option",41);popup.add_separator();popup.add_item("Disabled option",87);popup.set_item_disabled(2,true)
	popup.id_pressed.connect(logic.menu_selected);popup.index_pressed.connect(logic.menu_index_selected);menu.about_to_popup.connect(logic.menu_opened)
	# Put it under the fixture mod so its native MenuButton belongs to that mod.
	menu.reparent(logic);await process_frame
	found=interface.inspect("qa_window_logic",logic,{"search":"Observed profile menu"});ref=found.result.controls[0].ref
	check(not "select" in found.result.controls[0].actions and not found.result.controls[0].menu_open,"closed menus do not expose unobserved items")
	check(interface.act({"ref":ref,"action":"press"}).ok and popup.visible and logic.menu_opens==1,"press opens the native menu and invokes its normal population callback")
	found=interface.inspect("qa_window_logic",logic,{"search":"Observed profile menu"});ref=found.result.controls[0].ref
	check("select" in found.result.controls[0].actions and found.result.controls[0].options[0].id==41,"opened menu options are read from the real popup")
	check(not interface.act({"ref":ref,"action":"select","index":1}).ok and not interface.act({"ref":ref,"action":"select","index":2}).ok and logic.menu_id==-1,"separators and disabled menu items cannot be selected")
	popup.set_item_text(0,"Changed option")
	check(not interface.act({"ref":ref,"action":"select","index":0}).ok and logic.menu_id==-1,"changing menu items invalidates their observed snapshot")
	found=interface.inspect("qa_window_logic",logic,{"search":"Observed profile menu"});ref=found.result.controls[0].ref
	check(interface.act({"ref":ref,"action":"select","index":0}).ok and logic.menu_id==41 and logic.menu_index==0 and not popup.visible,"selection uses actual item ID and index signals, then requires readback")
	found=interface.inspect("qa_window_logic",logic,{"search":"Observed profile menu"});interface.act({"ref":found.result.controls[0].ref,"action":"press"})
	popup.id_pressed.connect(skin.menu_selected)
	found=interface.inspect("qa_window_logic",logic,{"search":"Observed profile menu"})
	check(not "select" in found.result.controls[0].actions,"another mod's menu gameplay callback cannot inherit selection access")
	world.queue_free();api.queue_free();await process_frame
	print("MOD_WINDOW_TESTS ","PASS" if errors.is_empty() else errors,"; ",checks," checks");quit(0 if errors.is_empty() else 1)
