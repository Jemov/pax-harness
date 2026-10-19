extends SceneTree
const Interface=preload("res://mods/pax_harness/src/ui/game/mod_interface.gd")
const Logic=preload("res://mods/qa_window_logic/main.gd")
class World extends Node:
	var mod_windows: Array=[]
	var native_presses:=0
	func native_press() -> void:native_presses+=1
class Game extends RefCounted:
	var world: Node
	func scene_root() -> Node:return world
class API extends Node:
	var logic: Node
	func get_mod(id: String) -> Node:return logic if id=="qa_window_logic" else null
var interface: RefCounted
var logic: Node
var failures: Array=[]
var checks:=0
func check(value: bool,why: String) -> void:
	checks+=1
	if not value:failures.append(why)
func button_row(button: Button) -> Dictionary:
	# Locate the exact fixture node through its observed ref; button captions
	# are deliberately empty, matching native cards with child renderers.
	for observed: Dictionary in interface.inspect("qa_window_logic",logic,{"limit":100}).result.controls:
		var entry: Dictionary=interface.refs.get(observed.ref,{})
		if entry.has("node") and entry.node.get_ref()==button:return observed
	return {}
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=World.new();root.add_child(world)
	logic=Logic.new();world.add_child(logic)
	var api:=API.new();api.logic=logic;root.add_child(api)
	var game:=Game.new();game.world=world
	interface=Interface.new();interface.setup(api,game)
	var approve:=Button.new();logic.add_child(approve);approve.pressed.connect(logic.clicked)
	var approve_column:=VBoxContainer.new();approve.add_child(approve_column)
	var approve_row:=HBoxContainer.new();approve_column.add_child(approve_row)
	var approve_title:=RichTextLabel.new();approve_title.bbcode_enabled=true;approve_title.text="[b]Approve allocation[/b]";approve_title.fit_content=true;approve_row.add_child(approve_title)
	var cost:=Label.new();cost.text="Spend 10 ore";approve_column.add_child(cost)
	var hidden:=Label.new();hidden.text="Hidden decision details";approve_column.add_child(hidden);hidden.hide()
	var hidden_box:=VBoxContainer.new();approve_column.add_child(hidden_box);hidden_box.hide()
	var hidden_nested:=Label.new();hidden_nested.text="Hidden container details";hidden_box.add_child(hidden_nested)
	var secret:=LineEdit.new();secret.secret=true;secret.text="private-caption-sentinel";approve_column.add_child(secret)
	var editable:=LineEdit.new();editable.text="Editable input is not a caption";approve_column.add_child(editable)
	var reject:=Button.new();logic.add_child(reject);reject.pressed.connect(logic.clicked)
	var reject_column:=VBoxContainer.new();reject.add_child(reject_column)
	var reject_row:=HBoxContainer.new();reject_column.add_child(reject_row)
	var reject_title:=Label.new();reject_title.text="Reject allocation";reject_row.add_child(reject_title)
	var keep:=RichTextLabel.new();keep.bbcode_enabled=true;keep.text="Keep [i]10 ore[/i]";keep.fit_content=true;reject_column.add_child(keep)
	var foreign:=Button.new();world.add_child(foreign);foreign.pressed.connect(world.native_press);foreign.mouse_entered.connect(logic.hover)
	var foreign_column:=VBoxContainer.new();foreign.add_child(foreign_column)
	var foreign_title:=RichTextLabel.new();foreign_title.bbcode_enabled=true;foreign_title.text="[b]Native foreign decision[/b]";foreign_title.fit_content=true;foreign_column.add_child(foreign_title)
	await process_frame
	var first:=button_row(approve);var second:=button_row(reject);var outsider:=button_row(foreign)
	check(approve.text=="" and reject.text=="" and approve.get_signal_connection_list("gui_input").is_empty(),"fixture buttons render child captions without Button.text or gui_input callbacks")
	check("Approve allocation" in first.context and "Spend 10 ore" in first.context,"empty Button context includes nested parsed RichTextLabel and Label captions")
	check("Reject allocation" in second.context and "Keep 10 ore" in second.context,"a second empty Button retains its own nested choice captions")
	check(first.ref!=second.ref and not "Reject allocation" in first.context and not "Approve allocation" in second.context,"separate decision buttons never inherit one another's descendant captions or refs")
	check(not "[b]" in str(first.context) and not "[i]" in str(second.context),"rich descendant captions expose rendered text rather than markup")
	check(not "Hidden decision details" in first.context and not "Hidden container details" in first.context,"hidden labels and labels inside hidden containers are absent from button context")
	check(not "private-caption-sentinel" in str(first) and not "Editable input is not a caption" in first.context,"secret and other editable inputs never become descendant button captions")
	check(not "private-caption-sentinel" in str(interface.inspect("qa_window_logic",logic,{})),"full UI inspection still redacts a secret descendant LineEdit")
	var found: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Approve allocation"})
	check(found.result.controls.any(func(control: Dictionary):return control.kind=="Button" and control.ref==first.ref),"search by a rendered nested decision caption returns its actual actionable button")
	found=interface.inspect("qa_window_logic",logic,{"search":"Reject allocation"})
	check(found.result.controls.any(func(control: Dictionary):return control.kind=="Button" and control.ref==second.ref),"search distinguishes the second actual decision button by its own child caption")
	check("press" in first.actions and interface.act({"ref":first.ref,"action":"press"}).ok and logic.clicks==1,"caption context preserves normal owned Button press dispatch")
	check("Native foreign decision" in outsider.context,"hover-attributed native buttons expose their observed rendered caption")
	check(outsider.actions==["hover"] and not interface.act({"ref":outsider.ref,"action":"press"}).ok and world.native_presses==0,"descendant captions do not grant press access through a foreign gameplay callback")
	secret.text="changed-private-caption-sentinel";hidden.text="Changed hidden caption"
	var private_changed:=button_row(approve)
	check(private_changed.ref==first.ref and private_changed.context==first.context and not "changed-private-caption-sentinel" in str(private_changed),"private or hidden descendant changes do not leak through context or reference churn")
	approve_title.text="[b]Approve revised allocation[/b]"
	var revised:=button_row(approve)
	check(revised.ref!=first.ref and "Approve revised allocation" in revised.context and not "Approve allocation" in revised.context,"a changed visible descendant caption produces a fresh accurate button snapshot")
	var before: int=logic.clicks
	check(not interface.act({"ref":first.ref,"action":"press"}).ok and logic.clicks==before,"old refs cannot act after a button's rendered decision caption changes")
	before=logic.clicks
	check(interface.act({"ref":revised.ref,"action":"press"}).ok and logic.clicks==before+1,"reinspection permits the current owned decision button through normal callbacks")
	world.queue_free();api.queue_free();await process_frame
	print("BUTTON_CAPTION_TESTS ","PASS" if failures.is_empty() else failures,"; ",checks," checks");quit(0 if failures.is_empty() else 1)
