extends Node
## Use the game's floating origin and orbit controls, with object-sized clipping.
## Never move/reparent a world object just to make it visible to the camera.
var service: Node
var target: MeshInstance3D
var body: String
var active:=false
var _view: Object
var _root: Node
var _distance:=0.0
var _span:=0.0
var _dragging:=false
var _km_per_unit:=1000.0

func setup(value: Node) -> void:
	service=value; process_priority=100
func focus(id: String) -> Dictionary:
	if not service.current() or not service.records.has(id) or service.records[id].kind!="object": return {"ok":false,"code":"creation.object_unavailable"}
	_root=service.game.scene_root(); _view=_root.get("view")
	if not _root.has_method("camera_navigation") or not _view is Object or not service.game.has_method("camera"): return {"ok":false,"code":"creation.object_camera_unavailable"}
	for field: String in ["view_mode","view_x","view_y","view_z","target_x","target_y","target_z","distance","target_distance","camera_yaw","pitch","flight_t","camera_drift"]:
		if not field in _view: return {"ok":false,"code":"creation.object_camera_unavailable"}
	var native: Variant=_root.camera_navigation()
	if not native is Object or not native.has_method("place_camera") or not native.has_method("cursor_over_ui") or not service.game.camera() is Camera3D: return {"ok":false,"code":"creation.object_camera_unavailable"}
	var script: Script=_root.get_script()
	_km_per_unit=float(script.get_script_constant_map().get("UNIT",1000.0)) if script!=null else 1000.0
	if not is_finite(_km_per_unit) or _km_per_unit<=0: return {"ok":false,"code":"creation.object_camera_unavailable"}
	body=str(service.records[id].definition.body)
	target=service.game.body_node(body).get_node_or_null("HarnessObject_"+id)
	if not is_instance_valid(target) or target.mesh==null or target.mesh.get_surface_count()==0: return {"ok":false,"code":"creation.object_unavailable"}
	active=false
	if is_instance_valid(service.owner_mod.chat_ui): service.owner_mod.chat_ui.close()
	if is_instance_valid(service.view): service.view.window.hide()
	var ui: Variant=_root.get("ui")
	if ui is Object and ui.get("menu_node") is Object and ui.menu_node.has_method("закрыть"): ui.menu_node.call("закрыть")
	var map: Variant=_root.get("political_map")
	if map is Control and map.visible: _root.galaxy_view().toggle_map()
	var galaxy: Variant=_view.get("galaxy_scene")
	if galaxy is Object and galaxy.has_method("hide_m"): galaxy.call("hide_m")
	service.game.focus(body,true)
	_view.set("view_mode","harness_object")
	var normal: Vector3=target.global_basis.z.normalized()
	var sunlight: Variant=_view.get("sun_light")
	if sunlight is Node3D and normal.dot(sunlight.global_basis.z)<0: normal=-normal
	_view.set("camera_yaw",atan2(normal.x,normal.z)+0.15); _view.set("pitch",asin(clampf(normal.y,-0.95,0.95))+0.12)
	_span=maxf(0.000001,(target.global_basis*target.get_aabb().size).length())
	_distance=_span*1.25
	active=true; _place()
	_root.camera_navigation().place_camera()
	_clip_camera(); service.game.body_node(body).show()
	return {"ok":true,"result":{"object_id":id,"body":body,"camera_target":"object","physical_travel":false,"distance_km":_distance*_units(),"model_visible":true}}
func _units() -> float:
	return _km_per_unit
func _place() -> void:
	var parent: Node3D=service.game.body_node(body)
	var center: Vector3=target.get_meta("harness_model_center",target.get_aabb().get_center())
	var offset: Vector3=(target.to_global(center)-parent.global_position)*_units()
	var data: Dictionary=service.game.body(body)
	# Keep the large kilometre coordinates as separate scalar doubles. Vector3
	# is only used for the small, already rebased local offset.
	_view.set("view_x",float(data.kx)+offset.x); _view.set("view_y",float(data.ky)+offset.y); _view.set("view_z",float(data.kz)+offset.z)
	_view.set("target_x",_view.get("view_x")); _view.set("target_y",_view.get("view_y")); _view.set("target_z",_view.get("view_z"))
	_view.set("distance",_distance); _view.set("target_distance",_distance); _view.set("flight_t",1.0); _view.set("camera_drift",false)
	# Expected scalars are stored separately as metadata to preserve precision.
	set_meta("target_x",_view.get("target_x")); set_meta("target_y",_view.get("target_y")); set_meta("target_z",_view.get("target_z"))
func _clip_camera() -> void:
	service.game.camera().near=maxf(0.0000001,_distance*0.002)
func _process(_delta: float) -> void:
	if not active: return
	if not service.current() or not is_instance_valid(target) or str(_view.get("view_mode"))!="harness_object": active=false; _dragging=false; return
	var ui: Variant=_root.get("ui")
	if ui is Object and bool(ui.get("menu_frame")):
		active=false; _dragging=false; service.game.focus(body,true); return
	for axis: String in ["x","y","z"]:
		if absf(float(_view.get("target_"+axis))-float(get_meta("target_"+axis)))>0.001: active=false; return
	if absf(float(_view.get("target_distance"))-_distance)>maxf(0.0000001,_distance*0.001): active=false; return
	_place(); _root.camera_navigation().place_camera(); _clip_camera(); service.game.body_node(body).show()
func _input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and _dragging:
		_dragging=false; get_viewport().set_input_as_handled(); return
	if is_instance_valid(service.owner_mod.chat_ui) and service.owner_mod.chat_ui.surface.is_visible_in_tree(): return
	if _root.camera_navigation().cursor_over_ui(): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_dragging=event.pressed; get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_view.set("camera_yaw",float(_view.get("camera_yaw"))-event.relative.x*0.005)
		_view.set("pitch",clampf(float(_view.get("pitch"))+event.relative.y*0.005,-1.45,1.45)); get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		_distance=clampf(_distance*(0.85 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.18),_span*0.7,maxf(_span*200,float(service.game.body(body).radius)*8))
		_view.set("target_distance",_distance); get_viewport().set_input_as_handled()
