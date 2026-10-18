extends RefCounted
## A detached, bounded editable volume; no terrain, planet or population is created.
static func supported(api: Node) -> bool:
	return api!=null and api.get("voxel")!=null and api.voxel.has_method("available") and api.voxel.available()
static func static_snapshot(api: Node, definition: Dictionary, cuts: Array) -> MeshInstance3D:
	var data: Dictionary=definition.model.duplicate(true)
	if not data.has("shapes"): data["shapes"]=[]
	# Explicit voxels are normally placed after shapes. Bake them into single-cell
	# boxes first so persisted cuts also remove those cells in the fallback path.
	for voxel: Array in data.get("voxels",[]):
		data.shapes.append({"type":"box","from":voxel.slice(0,3),"to":voxel.slice(0,3),"color":voxel[3]})
	data.erase("voxels")
	for cut: Dictionary in cuts: data.shapes.append({"type":"sphere","center":cut.center,"radius":cut.radius,"color":0})
	return api.voxel.model(data)

static func create(api: Node, definition: Dictionary, cuts: Array=[]) -> MeshInstance3D:
	if not definition.get("destructible",false): return api.voxel.model(definition.model)
	if not supported(api) or not api.voxel.enable(): return null
	var grid: Dictionary=api.voxel.model_grid(definition.model)
	var buffer: Variant=api.voxel.create("VoxelBuffer")
	if buffer==null: return null
	var size_: Vector3i=grid.size
	buffer.create(size_.x+2,size_.y+2,size_.z+2)
	var channel: int=api.voxel.constant("VoxelBuffer","CHANNEL_COLOR")
	buffer.set_channel_depth(channel,api.voxel.constant("VoxelBuffer","DEPTH_8_BIT"))
	for z: int in size_.z:
		for y: int in size_.y:
			for x: int in size_.x:
				buffer.set_voxel(int(grid.cells[(z*size_.y+y)*size_.x+x]),x+1,y+1,z+1,channel)
	var tool: Variant=buffer.get_voxel_tool()
	tool.set_channel(channel); tool.set_mode(api.voxel.constant("VoxelTool","MODE_REMOVE"))
	for cut: Dictionary in cuts:
		tool.do_sphere(Vector3(cut.center[0],cut.center[1],cut.center[2])+Vector3.ONE,float(cut.radius))
	var mesher: Variant=api.voxel.create("VoxelMesherCubes")
	var palette: Variant=api.voxel.create("VoxelColorPalette")
	for i: int in range(1,grid.palette.size()): palette.set_color(i,grid.palette[i])
	mesher.palette=palette; mesher.greedy_meshing_enabled=true
	mesher.color_mode=api.voxel.constant("VoxelMesherCubes","COLOR_MESHER_PALETTE")
	var material:=StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.roughness=0.85
	var built: Mesh=mesher.build_mesh(buffer,[material])
	var mesh:=ArrayMesh.new()
	if built!=null and built.get_surface_count()>0:
		var arrays: Array=built.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i: int in vertices.size(): vertices[i]-=Vector3(size_)*0.5
		arrays[Mesh.ARRAY_VERTEX]=vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.surface_set_material(0,material)
	var node:=MeshInstance3D.new(); node.mesh=mesh
	node.set_meta("harness_voxel_buffer",buffer); node.set_meta("harness_voxel_channel",channel)
	return node
static func occupied(node: MeshInstance3D) -> int:
	if not node.has_meta("harness_voxel_buffer"): return 0
	var buffer: Variant=node.get_meta("harness_voxel_buffer")
	var channel: int=node.get_meta("harness_voxel_channel")
	var size_: Vector3i=buffer.get_size(); var count:=0
	for z: int in range(1,size_.z-1):
		for y: int in range(1,size_.y-1):
			for x: int in range(1,size_.x-1):
				if buffer.get_voxel(x,y,z,channel)!=0: count+=1
	return count
