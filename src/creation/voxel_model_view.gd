extends SubViewportContainer
const VoxelObject=preload("res://mods/pax_harness/src/creation/voxel_object.gd")
var service: Node
var definition: Dictionary
var mesh: MeshInstance3D
var viewport: SubViewport
var camera: Camera3D
var yaw:=0.35
var pitch:=0.17
var zoom:=1.0
var carving:=false
var _dragged:=false
var _start:=Vector2.ZERO
signal carved(result: Dictionary)

func setup(value: Node, data: Dictionary) -> void:
	service=value; definition=data.duplicate(true)
	name="ModelPreview"; custom_minimum_size=Vector2(0,320); size_flags_horizontal=Control.SIZE_EXPAND_FILL
	stretch=true; mouse_filter=Control.MOUSE_FILTER_STOP
	viewport=SubViewport.new(); viewport.size=Vector2i(720,440); viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	viewport.msaa_3d=Viewport.MSAA_4X; viewport.gui_disable_input=true; add_child(viewport)
	camera=Camera3D.new(); viewport.add_child(camera); camera.current=true; camera.fov=45
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-35,-30,0); light.light_energy=0.8; viewport.add_child(light)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("#151a20")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=0.35; viewport.add_child(environment)
	resized.connect(_frame); reload()
func reload() -> void:
	if is_instance_valid(mesh): viewport.remove_child(mesh); mesh.queue_free()
	var record: Dictionary=service.records.get(str(definition.id),{})
	mesh=VoxelObject.create(service.api,definition,record.get("damage",[]))
	if mesh==null: mesh=VoxelObject.static_snapshot(service.api,definition,record.get("damage",[]))
	viewport.add_child(mesh); _frame()
func _frame() -> void:
	if not is_instance_valid(camera): return
	var span: float=maxf(definition.model.size[0],maxf(definition.model.size[1],definition.model.size[2]))
	var aspect: float=maxf(0.3,size.x/maxf(1,size.y))
	var distance_: float=span*0.82/tan(deg_to_rad(camera.fov*0.5))*maxf(1,1/aspect)*zoom
	camera.position=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance_
	camera.look_at(Vector3.ZERO)
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed: zoom=clampf(zoom*(0.88 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.14),0.45,3); _frame()
			accept_event()
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: _start=event.position; _dragged=false
			elif carving and not _dragged: _carve(event.position)
			accept_event()
	elif event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		if event.position.distance_to(_start)>4: _dragged=true
		if not carving: yaw-=event.relative.x*0.009; pitch=clampf(pitch+event.relative.y*0.009,-1.3,1.3); _frame()
		accept_event()
func _carve(position_: Vector2) -> void:
	if not mesh.has_meta("harness_voxel_buffer"): return
	var screen: Vector2=position_/size*Vector2(viewport.size)
	var start: Vector3=camera.project_ray_origin(screen)
	var direction: Vector3=camera.project_ray_normal(screen)
	var buffer: Variant=mesh.get_meta("harness_voxel_buffer")
	var channel: int=mesh.get_meta("harness_voxel_channel")
	var grid_size:=Vector3(definition.model.size[0],definition.model.size[1],definition.model.size[2])
	for step: int in range(2048):
		var point: Vector3=start+direction*float(step)*0.2+grid_size*0.5
		if point.x<0 or point.y<0 or point.z<0 or point.x>=grid_size.x or point.y>=grid_size.y or point.z>=grid_size.z: continue
		if buffer.get_voxel(int(point.x)+1,int(point.y)+1,int(point.z)+1,channel)==0: continue
		var result: Dictionary=service.damage_from_player(str(definition.id),[point.x,point.y,point.z],maxf(1,grid_size.length()*0.045))
		if result.ok: reload()
		carved.emit(result); return
