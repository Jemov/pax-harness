extends "res://mods/pax_harness/chart_extra_view.gd"
const Layout = preload("res://mods/pax_harness/chart_network_layout.gd")
var network_positions: Dictionary = {}
var settle := 1.0
var drill := ""
var _sun_hover := ""
var _sun_pin := ""
signal drill_changed
func setup(value: Dictionary) -> void:
	super.setup(value)
	if spec.type == "network": network_positions = Layout.compute(spec.nodes,spec.links)
	custom_minimum_size.y = 420 if spec.type in ["network","sunburst"] else 340
func replay_animation() -> void:
	if spec.type == "network": settle = 0 if animation_enabled else 1; set_process(true)
func set_chart_options(related: bool, animate: bool) -> void:
	super.set_chart_options(related,animate)
	if not animate: settle = 1; queue_redraw()
func _process(delta: float) -> void:
	super._process(delta)
	if settle < 1:
		settle = minf(1,settle+delta*1.6) if animation_enabled else 1
		queue_redraw(); set_process(settle < 1 or not is_equal_approx(hover_mix,1.0 if focus_index() >= 0 else 0.0))
func reset_drill() -> void:
	drill = ""; _sun_hover = ""; _sun_pin = ""; active = -1; pinned = -1; queue_redraw()
	drill_changed.emit()
func _gui_input(event: InputEvent) -> void:
	super._gui_input(event)
	if spec.type != "sunburst": return
	if event is InputEventMouseMotion:
		_sun_hover = str(hits[active].get("node_id","")) if active >= 0 and active < hits.size() else ""
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if active >= 0 and active < hits.size():
			var id: String = str(hits[active].get("node_id",""))
			var has_children: bool = spec.nodes.any(func(n: Dictionary): return n.get("parent","") == id)
			if id == drill: reset_drill()
			elif has_children: drill = id; active = -1; _sun_hover = ""; queue_redraw(); drill_changed.emit()
			else: _sun_pin = "" if _sun_pin == id else id
			grab_focus(); accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: reset_drill()
func _draw() -> void:
	hits.clear(); text_boxes.clear(); _next_keys.clear()
	if size.x < 50: return
	draw_style_box(Style.box(Color("#1b1e24"),6,Color("#292e38"),0),Rect2(Vector2.ZERO,size))
	match spec.type:
		"gantt": _gantt()
		"network": _network()
		"sunburst": _sunburst()
	if caption_keys != _next_keys:
		caption_keys = _next_keys.duplicate(true); captions_changed.emit.call_deferred(caption_keys)
func _arrow(point: Vector2, direction: Vector2, color: Color) -> void:
	var unit: Vector2 = direction.normalized(); var side := Vector2(-unit.y,unit.x)
	_fill(PackedVector2Array([point,point-unit*8+side*4,point-unit*8-side*4]),color)
func _gantt() -> void:
	var low := INF; var high := -INF; var total_height := 0.0
	var left: float = clampf(size.x*0.30,84,260)
	var row_heights: Array = []
	for task: Dictionary in spec.tasks:
		low = minf(low,task.start); high = maxf(high,task.end)
		var height: float = maxf(40,_height(str(task.label),left-22)+18); row_heights.append(height); total_height += height
	if low == high: low -= 1; high += 1
	var heading: String = str(spec.get("x_label",spec.get("unit","Дни кампании")))
	var top: float = 48+_height(heading,size.x-20)
	_grow_height(top+total_height+20)
	var area := Rect2(left,top,size.x-left-18,total_height)
	Text.draw_text(self,heading,Rect2(10,8,size.x-20,0),Color("#aabbd2"),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)
	for tick: int in (5 if area.size.x > 400 else 3):
		var count: int = 5 if area.size.x > 400 else 3; var fraction: float = float(tick)/(count-1)
		var x: float = area.position.x+fraction*area.size.x
		draw_line(Vector2(x,top-8),Vector2(x,area.end.y),Color(0.6,0.7,0.9,0.12),1,true)
		_fit(Chart.number(lerpf(low,high,fraction)),Rect2(clampf(x-32,left,size.x-82),top-26,64,20))
	var focused: Dictionary = {}; var selection: int = focus_index()
	if related_enabled and selection >= 0 and selection < spec.tasks.size(): focused = Focus.paths(spec.tasks,spec.get("dependencies",[]),spec.tasks[selection].id)
	var rects: Dictionary = {}; var y: float = top
	for i: int in spec.tasks.size():
		var task: Dictionary = spec.tasks[i]; var row_height: float = row_heights[i]
		var alpha: float = lerpf(1,1 if focused.has(task.id) else 0.18,hover_mix) if not focused.is_empty() else 1.0
		if i%2 == 0: draw_rect(Rect2(8,y,size.x-16,row_height),Color(1,1,1,0.018))
		Text.draw_text(self,str(task.label),Rect2(10,y+(row_height-_height(str(task.label),left-22))/2,left-22,0),Color(Color("#c5d1e2"),alpha),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)
		var start_x: float = left+(float(task.start)-low)/(high-low)*area.size.x
		var end_x: float = left+(float(task.end)-low)/(high-low)*area.size.x
		var rect := Rect2(start_x,y+row_height/2-10,maxf(3,end_x-start_x),20); rects[task.id] = rect
		var color: Color = {"planned":COLORS[0],"active":COLORS[1],"blocked":COLORS[4],"complete":COLORS[2]}.get(str(task.get("status","")),COLORS[0])
		if task.start == task.end:
			var center: Vector2 = rect.get_center(); _fill(PackedVector2Array([center+Vector2(0,-8),center+Vector2(8,0),center+Vector2(0,8),center-Vector2(8,0)]),Color(color,alpha))
		else:
			draw_style_box(Style.box(Color(color,0.28*alpha),4,Color(color,0.8*alpha),0),rect)
			if task.has("progress") and task.progress > 0: draw_style_box(Style.box(Color(color,0.65*alpha),4,Color.TRANSPARENT,0),Rect2(rect.position,Vector2(rect.size.x*float(task.progress),rect.size.y)))
		var text: String = str(task.label)+"\n"+Chart.number(task.start)+" — "+Chart.number(task.end)
		if task.has("progress"): text += "\nВыполнено: "+Chart.number(task.progress*100)+"%"
		text += "\n"+{"planned":"Запланировано","active":"В работе","blocked":"Заблокировано","complete":"Завершено"}.get(str(task.get("status","")),"Статус не указан")
		_hit(Rect2(8,y,size.x-16,row_height),text); y += row_height
	for edge: Dictionary in spec.get("dependencies",[]):
		var from: Rect2 = rects[edge.source]; var to: Rect2 = rects[edge.target]
		var points := PackedVector2Array([Vector2(from.end.x,from.get_center().y),Vector2(minf(size.x-12,from.end.x+10),from.get_center().y),Vector2(minf(size.x-12,from.end.x+10),to.get_center().y),Vector2(to.position.x,to.get_center().y)])
		var color := Color("#8799b4"); color.a = 0.75 if focused.has(edge.source) and focused.has(edge.target) else 0.22
		draw_polyline(points,color,1.3,true); _arrow(points[-1],points[-1]-points[-2],color)
	if spec.has("now") and spec.now >= low and spec.now <= high:
		var x: float = left+(float(spec.now)-low)/(high-low)*area.size.x
		draw_dashed_line(Vector2(x,top),Vector2(x,area.end.y),Color("#e3bc76"),1.5,5,true)
		_hit(Rect2(x-4,top,8,area.size.y),"Текущий момент: "+Chart.number(spec.now))
func _network() -> void:
	var positions: Dictionary = {}; var radii: Dictionary = {}; var groups: Dictionary = {}; var maximum := 1.0
	for node: Dictionary in spec.nodes: maximum = maxf(maximum,float(node.get("value",1)))
	for i: int in spec.nodes.size():
		var node: Dictionary = spec.nodes[i]; var group: String = str(node.get("group",""))
		if not groups.has(group): groups[group] = groups.size()
		var initial: Vector2 = Vector2(0.5,0.5)+Vector2.from_angle(TAU*i/maxi(1,spec.nodes.size())-PI/2)*0.34
		var p: Vector2 = initial.lerp(network_positions[node.id],1-pow(1-settle,3))
		positions[node.id] = Vector2(32,32)+p*Vector2(size.x-64,size.y-64)
		radii[node.id] = 9+13*sqrt(float(node.get("value",1))/maximum)
	var focused: Dictionary = {}; var selection: int = focus_index()
	if related_enabled and selection >= 0:
		if selection < spec.links.size(): focused[spec.links[selection].source] = true; focused[spec.links[selection].target] = true
		elif selection-spec.links.size() < spec.nodes.size(): focused[spec.nodes[selection-spec.links.size()].id] = true
		var initial: Dictionary = focused.duplicate()
		for edge: Dictionary in spec.links:
			if initial.has(edge.source): focused[edge.target] = true
			if initial.has(edge.target): focused[edge.source] = true
	var max_weight := 1.0
	for edge: Dictionary in spec.links: max_weight = maxf(max_weight,float(edge.get("value",1)))
	for edge: Dictionary in spec.links:
		var a: Vector2 = positions[edge.source]; var b: Vector2 = positions[edge.target]
		var selected: bool = focused.has(edge.source) and focused.has(edge.target)
		var alpha: float = lerpf(0.38,0.95 if selected else 0.06,hover_mix) if not focused.is_empty() else 0.38
		var color := Color(COLORS[0],alpha); var width: float = 1+4*sqrt(float(edge.get("value",1))/max_weight)
		draw_line(a,b,color,width,true)
		if spec.get("directed",false): _arrow(b+(a-b).normalized()*(radii[edge.target]+3),b-a,color)
		var direction: Vector2 = (b-a).normalized(); var side := Vector2(-direction.y,direction.x)*maxf(5,width)
		var polygon := PackedVector2Array([a+side,b+side,b-side,a-side])
		_hit(Rect2(a,Vector2.ZERO).expand(b).grow(6),str(edge.get("label","Связь"))+" · "+str(edge.source)+" → "+str(edge.target)+("\nВес: "+_amount(edge.value) if edge.has("value") else ""),polygon)
	for i: int in spec.nodes.size():
		var node: Dictionary = spec.nodes[i]; var p: Vector2 = positions[node.id]; var radius: float = radii[node.id]
		var color: Color = COLORS[int(groups[str(node.get("group",""))])%COLORS.size()]
		var alpha: float = lerpf(1,1 if focused.has(node.id) else 0.18,hover_mix) if not focused.is_empty() else 1
		draw_circle(p,radius+4,Color(color,0.09*alpha),true,-1,true); draw_circle(p,radius,Color(color,0.85*alpha),true,-1,true)
		var code: String = _key(str(node.label)+(" · "+_amount(node.value) if node.has("value") else ""),color,node.id)
		# Full names are in the wrapped key. Numbers are drawn only when clear.
		var box := Rect2(p-Vector2(19,9),Vector2(38,20))
		if not text_boxes.any(func(row: Dictionary): return row.rect.intersects(box)): Text.draw_text(self,code,box,Color("#f0f4fb"),HORIZONTAL_ALIGNMENT_CENTER,12,text_boxes)
		_hit(Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2),str(node.label)+("\n"+_amount(node.value) if node.has("value") else ""))
func _sunburst() -> void:
	var nodes: Dictionary = {}; var children: Dictionary = {}; var roots: Array = []
	for row: Dictionary in spec.nodes: nodes[row.id] = row; children[row.id] = []
	for row: Dictionary in spec.nodes:
		if row.has("parent"): children[row.parent].append(row.id)
		else: roots.append(row.id)
	var root_id: String = drill if nodes.has(drill) else roots[0]
	var totals: Dictionary = {}; _sum_tree(root_id,nodes,children,totals)
	var depth: int = _tree_depth(root_id,children)
	var heading: String = str(nodes[root_id].label)
	var top: float = _height(heading,size.x-20)+22
	_grow_height(maxf(420,top+320))
	var center := Vector2(size.x/2,top+(size.y-top-12)/2); var radius: float = minf(size.x/2-18,(size.y-top-28)/2)
	var inner: float = clampf(radius*0.27,30,56); var ring: float = (radius-inner)/maxi(1,depth)
	Text.draw_text(self,heading,Rect2(10,8,size.x-20,0),Color("#c6d3e7"),HORIZONTAL_ALIGNMENT_CENTER,12,text_boxes)
	var selected: String = _sun_pin if _sun_pin != "" else _sun_hover
	var focused: Dictionary = {}
	if related_enabled and selected != "":
		var edges: Array = []
		for row: Dictionary in spec.nodes:
			if row.has("parent"): edges.append({"source":row.parent,"target":row.id})
		focused = Focus.paths(spec.nodes,edges,selected)
	_sun_sectors(root_id,-PI/2,TAU,0,center,inner,ring,nodes,children,totals,focused,0)
	draw_circle(center,inner-3,Color("#202936"),true,-1,true)
	_fit("Всего",Rect2(center-Vector2(inner-5,20),Vector2((inner-5)*2,20)),Color("#94a6bf"))
	_fit(Chart.number(totals[root_id]),Rect2(center+Vector2(-inner+5,2),Vector2((inner-5)*2,22)),Color("#e3ebf8"))
	_hit(Rect2(center-Vector2.ONE*inner,Vector2.ONE*inner*2),str(nodes[root_id].label)+"\n"+_amount(totals[root_id])+"\nНажмите, чтобы вернуться к корню")
	hits[-1]["node_id"] = root_id
func _sum_tree(id: String, nodes: Dictionary, children: Dictionary, totals: Dictionary) -> float:
	var total: float = float(nodes[id].get("value",0))
	for child: String in children[id]: total += _sum_tree(child,nodes,children,totals)
	totals[id] = total; return total
func _tree_depth(id: String, children: Dictionary) -> int:
	var depth := 0
	for child: String in children[id]: depth = maxi(depth,1+_tree_depth(child,children))
	return depth
func _sun_sectors(id: String, angle: float, span: float, level: int, center: Vector2, inner: float, ring: float, nodes: Dictionary, children: Dictionary, totals: Dictionary, focused: Dictionary, color_index: int) -> void:
	var cursor: float = angle
	for i: int in children[id].size():
		var child: String = children[id][i]; var arc: float = span*float(totals[child])/maxf(1.0e-15,totals[id])
		if arc <= 0: continue
		var first: float = inner+level*ring+2; var last: float = first+ring-4
		var index: int = i if level == 0 else color_index
		var color: Color = COLORS[index%COLORS.size()].lightened(minf(0.25,level*0.065))
		var alpha: float = lerpf(0.78,1 if focused.has(child) else 0.13,hover_mix) if not focused.is_empty() else 0.78
		var polygon := PackedVector2Array(); var steps: int = maxi(3,ceili(arc*40))
		for step: int in steps+1: polygon.append(center+Vector2.from_angle(cursor+arc*step/steps)*last)
		for step: int in range(steps,-1,-1): polygon.append(center+Vector2.from_angle(cursor+arc*step/steps)*first)
		_fill(polygon,Color(color,alpha)); draw_polyline(polygon+PackedVector2Array([polygon[0]]),Color(color.lightened(0.15),0.4),1,true)
		var code: String = _key(str(nodes[id].label)+" → "+str(nodes[child].label)+": "+_amount(totals[child]),color,child)
		var at: Vector2 = center+Vector2.from_angle(cursor+arc/2)*(first+last)/2
		var box := Rect2(at-Vector2(19,9),Vector2(38,20))
		if ring >= 26 and arc*(first+last)/2 > 48 and not text_boxes.any(func(row: Dictionary): return row.rect.grow(2).intersects(box)):
			Text.draw_text(self,code,box,Color("#f1f4fc"),HORIZONTAL_ALIGNMENT_CENTER,12,text_boxes)
		var bounds := Rect2(polygon[0],Vector2.ZERO)
		for point: Vector2 in polygon: bounds = bounds.expand(point)
		_hit(bounds,str(nodes[child].label)+"\n"+_amount(totals[child])+"\n"+Chart.number(totals[child]/totals[id]*100)+"% от родителя",polygon); hits[-1]["node_id"] = child
		_sun_sectors(child,cursor,arc,level+1,center,inner,ring,nodes,children,totals,focused,index)
		cursor += arc
