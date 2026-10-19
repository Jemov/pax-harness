extends SceneTree
var hits := 0
class Surface extends Control:
	var events: Array = []
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouse: events.append([event.get_class(), event.device, event.position])
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(800,600)
	var button:=Button.new();button.text="Probe";button.position=Vector2(20,20);button.size=Vector2(150,50);root.add_child(button)
	button.pressed.connect(func():hits+=1)
	var surface:=Surface.new();surface.position=Vector2(220,20);surface.size=Vector2(150,150);root.add_child(surface)
	var field:=LineEdit.new();field.position=Vector2(20,220);field.size=Vector2(250,40);root.add_child(field)
	await process_frame
	var before:=[Input.get_mouse_button_mask(),root.get_mouse_position(),DisplayServer.mouse_get_position()]
	for at: Vector2 in [Vector2(60,40),Vector2(250,60),Vector2(60,240)]:
		var move:=InputEventMouseMotion.new();move.device=10071;move.position=at;move.global_position=at;root.push_input(move,true)
		for down: bool in [true,false]:
			var click:=InputEventMouseButton.new();click.device=10071;click.position=at;click.global_position=at;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=down;click.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(click,true)
	root.push_text_input("Привет Test")
	print({"before":before,"after":[Input.get_mouse_button_mask(),root.get_mouse_position(),DisplayServer.mouse_get_position()],"hits":hits,"custom_events":surface.events,"text":field.text,"focus":str(root.gui_get_focus_owner())})
	quit(0 if hits==1 and field.text=="Привет Test" and surface.events.size()==3 and Input.get_mouse_button_mask()==before[0] else 1)
