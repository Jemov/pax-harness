extends SceneTree
const Interface=preload("res://mods/pax_harness/src/ui/game/mod_interface.gd")
const Logic=preload("res://mods/qa_window_logic/main.gd")
const Foreign=preload("res://mods/qa_window_theme/main.gd")
const NativeSound=preload("res://src/ui/Sound.gd")
class World extends Node:
	var mod_windows: Array=[]
	func hud() -> Node:return self
	func toggle_window(window: Control) -> void:window.visible=not window.visible
class Game extends RefCounted:
	var world: Node
	func scene_root() -> Node:return world
class API extends Node:
	var logic: Node
	func get_mod(id: String) -> Node:return logic if id=="qa_window_logic" else null
var checks:=0
var failures: Array=[]
var interface: RefCounted
var logic: Node
func check(value: bool,why: String) -> void:
	checks+=1
	if not value:failures.append(why)
func row(search: String) -> Dictionary:
	var found: Dictionary=interface.inspect("qa_window_logic",logic,{"search":search})
	return found.result.controls[0] if found.result.total>0 else {}
func _initialize() -> void:run.call_deferred()
func run() -> void:
	Logic.static_pointer_presses=0;Logic.static_pointer_releases=0;Logic.static_pointer_position=Vector2.ZERO;Logic.static_menu_id=-1;Logic.static_clicks=0
	var world:=World.new();root.add_child(world)
	logic=Logic.new();world.add_child(logic)
	var api:=API.new();api.logic=logic;root.add_child(api)
	var game:=Game.new();game.world=world
	interface=Interface.new();interface.setup(api,game)
	var card:=Label.new();card.text="Static owned card";card.size=Vector2(180,40);card.mouse_filter=Control.MOUSE_FILTER_STOP;world.add_child(card);card.gui_input.connect(Logic.static_pointer)
	var caption:=Label.new();caption.text="Actual static card resource";card.add_child(caption)
	var private_field:=LineEdit.new();private_field.secret=true;private_field.text="static-secret-not-exposed";card.add_child(private_field)
	var callback: Callable=card.get_signal_connection_list("gui_input")[0].callable
	check(callback.get_object() is Script and callback.get_object().resource_path=="res://mods/qa_window_logic/main.gd","fixture uses a genuine static callable whose owner is the actual mod GDScript resource")
	await process_frame
	var found:=row("Static owned card");var pointer_ref: String=found.get("ref","")
	check("click_at" in found.get("actions",[]),"a plain card with an observed owned static gui_input callback exposes click_at")
	check(interface.act({"ref":pointer_ref,"action":"click_at","x":10,"y":10}).ok and Logic.static_pointer_presses==1 and Logic.static_pointer_releases==1 and Logic.static_pointer_position==Vector2(10,10),"static gui_input receives one actual press and release at the requested local point")
	check("Actual static card resource" in found.get("context",[]) and not "static-secret-not-exposed" in str(found),"a static-owned card keeps rendered context and private-input redaction")
	var before: int=Logic.static_pointer_presses
	card.gui_input.connect(Foreign.static_pointer);found=row("Static owned card")
	check(not "click_at" in found.get("actions",[]) and not interface.act({"ref":pointer_ref,"action":"click_at","x":10,"y":10}).ok and Logic.static_pointer_presses==before,"adding a foreign static gui_input owner revokes pointer access through an existing ref")
	card.gui_input.disconnect(Foreign.static_pointer)
	var menu:=MenuButton.new();menu.text="Static owned menu";logic.add_child(menu)
	var popup:=menu.get_popup();popup.add_item("Actual static option",42);popup.id_pressed.connect(Logic.static_menu_selected)
	await process_frame
	found=row("Static owned menu");interface.act({"ref":found.ref,"action":"press"});found=row("Static owned menu")
	check("select" in found.get("actions",[]) and found.get("menu_open",false),"an opened menu with an owned static ID callback exposes selection")
	check(interface.act({"ref":found.ref,"action":"select","index":0}).ok and Logic.static_menu_id==42,"static menu selection receives the actual native item ID")
	found=row("Static owned menu");interface.act({"ref":found.ref,"action":"press"});found=row("Static owned menu");var menu_ref: String=found.ref
	popup.id_pressed.connect(Foreign.static_menu_selected);found=row("Static owned menu")
	check(not "select" in found.get("actions",[]) and not interface.act({"ref":menu_ref,"action":"select","index":0}).ok,"a foreign static menu callback cannot inherit another mod's selection access")
	popup.id_pressed.disconnect(Foreign.static_menu_selected)
	popup.id_pressed.connect(NativeSound.static_clicked.unbind(1));found=row("Static owned menu")
	check(not "select" in found.get("actions",[]) and not interface.act({"ref":menu_ref,"action":"select","index":0}).ok,"native sound's static decoration exception does not grant menu gameplay ownership")
	popup.id_pressed.disconnect(NativeSound.static_clicked.unbind(1));popup.hide()
	var layer:=CanvasLayer.new();world.add_child(layer)
	var overlay:=VBoxContainer.new();layer.add_child(overlay)
	var title:=Label.new();title.text="Static exclusive overlay status";overlay.add_child(title)
	var action:=Button.new();action.text="Static overlay action";overlay.add_child(action);action.pressed.connect(Logic.static_clicked);action.pressed.connect(NativeSound.static_clicked)
	await process_frame
	check(not row("Static exclusive overlay status").is_empty(),"exclusive plain overlays remain readable with an owned static callback and native static sound decoration")
	var foreign_action:=Button.new();overlay.add_child(foreign_action);foreign_action.pressed.connect(Foreign.static_clicked)
	check(row("Static exclusive overlay status").is_empty(),"a foreign static gameplay callback rejects mixed plain-overlay ownership")
	foreign_action.queue_free();await process_frame
	check(not row("Static exclusive overlay status").is_empty(),"removing the foreign static callback restores exclusive observed overlay ownership")
	var sound_layer:=CanvasLayer.new();world.add_child(sound_layer)
	var sound_overlay:=VBoxContainer.new();sound_layer.add_child(sound_overlay)
	var sound_title:=Label.new();sound_title.text="Native static sound only status";sound_overlay.add_child(sound_title)
	var sound_action:=Button.new();sound_overlay.add_child(sound_action);sound_action.pressed.connect(NativeSound.static_clicked)
	check(row("Native static sound only status").is_empty(),"native static sound decoration alone never grants a mod ownership of an overlay")
	var registered:=PanelContainer.new();registered.set_meta("window_float_key","mod:Static registered panel");world.add_child(registered);world.mod_windows.append(registered);registered.hide()
	var registered_action:=Button.new();registered.add_child(registered_action);registered_action.pressed.connect(Logic.static_clicked)
	check(not row("Static registered panel").is_empty(),"static mod-owned gameplay callbacks attribute game-registered windows")
	registered_action.pressed.connect(Foreign.static_clicked)
	check(row("Static registered panel").is_empty(),"foreign static callbacks cannot inherit registered-window ownership")
	world.queue_free();api.queue_free();await process_frame
	print("STATIC_OWNER_TESTS ","PASS" if failures.is_empty() else failures,"; ",checks," checks");quit(0 if failures.is_empty() else 1)
