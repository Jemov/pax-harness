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
	for observed: Dictionary in interface.inspect("qa_window_logic",logic,{"limit":100}).result.controls:
		var entry: Dictionary=interface.refs.get(observed.ref,{})
		if entry.has("node") and entry.node.get_ref()==button:return observed
	return {}
func overlay(parent: Control,caption: String) -> Dictionary:
	var margin:=MarginContainer.new();margin.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(margin)
	var column:=VBoxContainer.new();margin.add_child(column)
	var label:=Label.new();label.text=caption;column.add_child(label)
	return {"margin":margin,"column":column,"label":label}
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=World.new();root.add_child(world)
	logic=Logic.new();world.add_child(logic)
	var api:=API.new();api.logic=logic;root.add_child(api)
	var game:=Game.new();game.world=world
	interface=Interface.new();interface.setup(api,game)
	var choices:=VBoxContainer.new();logic.add_child(choices)
	var first_row:=PanelContainer.new();choices.add_child(first_row)
	var approve:=Button.new();first_row.add_child(approve);approve.pressed.connect(logic.clicked)
	var first_overlay:=overlay(first_row,"Adopt overlay policy")
	var detail:=RichTextLabel.new();detail.bbcode_enabled=true;detail.text="[i]Cost 15 ore[/i]";detail.fit_content=true;first_overlay.column.add_child(detail)
	var hidden:=Label.new();hidden.text="Hidden overlay choice";first_overlay.column.add_child(hidden);hidden.hide()
	var hidden_box:=VBoxContainer.new();first_overlay.column.add_child(hidden_box);hidden_box.hide()
	var hidden_nested:=Label.new();hidden_nested.text="Hidden overlay-container choice";hidden_box.add_child(hidden_nested)
	var secret:=LineEdit.new();secret.secret=true;secret.text="overlay-private-sentinel";first_overlay.column.add_child(secret)
	var editable:=LineEdit.new();editable.text="Editable overlay input";first_overlay.column.add_child(editable)
	var second_row:=PanelContainer.new();choices.add_child(second_row)
	var reject:=Button.new();second_row.add_child(reject);reject.pressed.connect(logic.clicked)
	var second_overlay:=overlay(second_row,"Reject overlay policy")
	var keep:=RichTextLabel.new();keep.bbcode_enabled=true;keep.text="Keep [b]15 ore[/b]";keep.fit_content=true;second_overlay.column.add_child(keep)
	var ambiguous:=PanelContainer.new();choices.add_child(ambiguous)
	var left:=Button.new();ambiguous.add_child(left);left.pressed.connect(logic.clicked)
	var right:=Button.new();ambiguous.add_child(right);right.pressed.connect(logic.clicked)
	overlay(ambiguous,"Ambiguous two-button caption")
	var ordinary_parent:=HBoxContainer.new();choices.add_child(ordinary_parent)
	var ordinary:=Button.new();ordinary_parent.add_child(ordinary);ordinary.pressed.connect(logic.clicked)
	overlay(ordinary_parent,"Unregistered non-panel association")
	var foreign_row:=PanelContainer.new();world.add_child(foreign_row)
	var foreign:=Button.new();foreign_row.add_child(foreign);foreign.pressed.connect(world.native_press);foreign.mouse_entered.connect(logic.hover)
	overlay(foreign_row,"Foreign overlay decision")
	var bounded_row:=PanelContainer.new();choices.add_child(bounded_row)
	var bounded_button:=Button.new();bounded_row.add_child(bounded_button);bounded_button.pressed.connect(logic.clicked)
	var bounded_overlay:=overlay(bounded_row,"L".repeat(150))
	for index: int in 10:
		var label:=Label.new();label.text="Bounded overlay caption "+str(index);bounded_overlay.column.add_child(label)
	await process_frame
	var first:=button_row(approve);var second:=button_row(reject)
	check(approve.text=="" and approve.get_child_count()==0 and approve.get_parent() is PanelContainer and first_overlay.margin.get_parent()==approve.get_parent(),"fixture matches one direct Button plus a sibling IGNORE MarginContainer in a PanelContainer")
	check("Adopt overlay policy" in first.context and "Cost 15 ore" in first.context,"single-button panel context includes its sibling overlay's visible Label and parsed rich caption")
	check("Reject overlay policy" in second.context and "Keep 15 ore" in second.context,"a separate panel row exposes its own sibling overlay captions")
	check(first.ref!=second.ref and not "Reject overlay policy" in first.context and not "Adopt overlay policy" in second.context,"two panel rows do not cross-associate their overlay captions or refs")
	var found: Dictionary=interface.inspect("qa_window_logic",logic,{"search":"Adopt overlay policy"})
	check(found.result.controls.any(func(control: Dictionary):return control.kind=="Button" and control.ref==first.ref),"search by overlay decision text finds its actual Button")
	found=interface.inspect("qa_window_logic",logic,{"search":"Reject overlay policy"})
	check(found.result.controls.any(func(control: Dictionary):return control.kind=="Button" and control.ref==second.ref),"search separately identifies the second row's actual Button")
	check(not "Hidden overlay choice" in first.context and not "Hidden overlay-container choice" in first.context,"hidden labels and hidden-container descendants are excluded from sibling overlay context")
	check(not "overlay-private-sentinel" in str(first) and not "Editable overlay input" in first.context,"private and other editable overlay inputs never become rendered captions")
	check(not "overlay-private-sentinel" in str(interface.inspect("qa_window_logic",logic,{})),"full UI inspection still redacts the private overlay field")
	secret.text="changed-overlay-private-sentinel";hidden.text="Changed hidden overlay caption"
	var private_changed:=button_row(approve)
	check(private_changed.ref==first.ref and private_changed.context==first.context,"private or hidden sibling-overlay changes cause no context leakage or ref churn")
	check(not "Ambiguous two-button caption" in button_row(left).context and not "Ambiguous two-button caption" in button_row(right).context,"a PanelContainer with two direct buttons never guesses which one owns its overlay caption")
	first_overlay.margin.mouse_filter=Control.MOUSE_FILTER_STOP
	check(not "Adopt overlay policy" in button_row(approve).context,"an interactive STOP sibling cannot supply a button caption")
	first_overlay.margin.mouse_filter=Control.MOUSE_FILTER_PASS
	check(not "Adopt overlay policy" in button_row(approve).context,"a PASS sibling is not treated as a non-interactive overlay")
	first_overlay.margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	check(not "Unregistered non-panel association" in button_row(ordinary).context,"a single-button parent outside PanelContainer does not acquire the overlay association")
	var outsider:=button_row(foreign)
	check("Foreign overlay decision" in outsider.context and outsider.actions==["hover"],"a foreign native overlay caption stays readable through its actual hover-only ownership")
	check(not interface.act({"ref":outsider.ref,"action":"press"}).ok and world.native_presses==0,"reading a sibling caption never grants press access to a foreign gameplay callback")
	var bounded:=button_row(bounded_button)
	check(bounded.context.size()==8 and bounded.context.all(func(text: String):return text.length()<=120),"overlay caption collection remains bounded to eight rendered texts of at most 120 characters")
	check(interface.act({"ref":first.ref,"action":"press"}).ok and logic.clicks==1,"an associated owned Button keeps normal press dispatch")
	check(button_row(approve).context==first.context and button_row(approve).ref==first.ref,"unchanged sibling-overlay observations preserve stable refs")
	first_overlay.label.text="Adopt revised overlay policy"
	var revised:=button_row(approve)
	check(revised.ref!=first.ref and "Adopt revised overlay policy" in revised.context and not "Adopt overlay policy" in revised.context,"a changed visible overlay caption produces a fresh accurate Button snapshot")
	var before: int=logic.clicks
	check(not interface.act({"ref":first.ref,"action":"press"}).ok and logic.clicks==before,"an old Button ref cannot act after its overlaid decision text changes")
	before=logic.clicks
	check(interface.act({"ref":revised.ref,"action":"press"}).ok and logic.clicks==before+1,"reinspection dispatches the current associated Button through its actual callback")
	world.queue_free();api.queue_free();await process_frame
	print("OVERLAY_CAPTION_TESTS ","PASS" if failures.is_empty() else failures,"; ",checks," checks");quit(0 if failures.is_empty() else 1)
