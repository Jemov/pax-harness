extends Node
var clicks:=0
var pointer_presses:=0
var pointer_releases:=0
var pointer_position:=Vector2.ZERO
var menu_id:=-1
var menu_index:=-1
var menu_opens:=0
func clicked() -> void:clicks+=1
func hover() -> void:pass
func pointer(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		pointer_position=event.position
		if event.pressed:pointer_presses+=1
		else:pointer_releases+=1
func menu_selected(id: int) -> void:menu_id=id
func menu_index_selected(index: int) -> void:menu_index=index
func menu_opened() -> void:menu_opens+=1
static var static_pointer_presses:=0
static var static_pointer_releases:=0
static var static_pointer_position:=Vector2.ZERO
static var static_menu_id:=-1
static var static_clicks:=0
static func static_pointer(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		static_pointer_position=event.position
		if event.pressed:static_pointer_presses+=1
		else:static_pointer_releases+=1
static func static_menu_selected(id: int) -> void:static_menu_id=id
static func static_clicked() -> void:static_clicks+=1
