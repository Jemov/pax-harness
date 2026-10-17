extends Control
const Chart = preload("res://mods/pax_harness/chat_chart.gd")
const Style = preload("res://mods/pax_harness/chat_style.gd")
const Text = preload("res://mods/pax_harness/chart_text.gd")
const Focus = preload("res://mods/pax_harness/chart_focus.gd")
const COLORS := [Color("#8daef5"),Color("#6fc4ad"),Color("#e0bb7e"),Color("#b99adc"),Color("#db929e"),Color("#74bed6")]
signal resource_hovered(label: String)
signal captions_changed(entries: Array)
signal province_requested(region: Dictionary)
var map_target: Callable
var _map_menu: PopupMenu
var _context_region: Dictionary = {}
var text_boxes: Array = []
var caption_keys: Array = []
var _next_keys: Array = []
var spec: Dictionary = {}
var hits: Array = []
var active := -1
var pinned := -1
var related_enabled := true
var animation_enabled := true
var hover_mix := 0.0
var _map_rect := Rect2()

func setup(value: Dictionary) -> void:
	spec = value
	name = "StatisticalPlot"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = maxf(320,spec.get("labels",[]).size()*26+72) if spec.type == "heatmap" else maxf(320,spec.get("groups",[]).size()*70+60) if spec.type == "ridgeline" else 380 if spec.type in ["sankey","choropleth","cartogram"] else 340
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): _set_active(-1))
	focus_mode = Control.FOCUS_ALL
	set_process(false)
func set_chart_options(related: bool, animate: bool) -> void:
	related_enabled = related; animation_enabled = animate; queue_redraw()
func _set_active(value: int) -> void:
	tooltip_text = str(hits[value].text) if value >= 0 and value < hits.size() else ""
	if active == value: return
	active = value; set_process(true); queue_redraw()
func focus_index() -> int: return pinned if pinned >= 0 else active
func _process(delta: float) -> void:
	var target: float = 1.0 if focus_index() >= 0 else 0.0
	hover_mix = move_toward(hover_mix,target,delta*8 if animation_enabled else 1000)
	queue_redraw()
	if is_equal_approx(hover_mix,target): set_process(false)
func link_resource(_label: String) -> void: pass
func category() -> int: return active
func _hit_index(at: Vector2) -> int:
	for index: int in range(hits.size()-1,-1,-1):
		if hits[index].rect.has_point(at) and (not hits[index].has("polygon") or Geometry2D.is_point_in_polygon(at,hits[index].polygon)): return index
	return -1
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_active(_hit_index(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and spec.type in ["choropleth","cartogram"]:
		_open_map_menu(event.position); accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and spec.type in ["sankey","network","gantt"]:
		pinned = active if pinned != active else -1; set_process(true); grab_focus(); accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		pinned = -1; set_process(true); accept_event()
func _get_tooltip(at: Vector2) -> String:
	var index: int = _hit_index(at)
	return str(hits[index].text) if index >= 0 else ""
func _open_map_menu(at: Vector2) -> void:
	if is_instance_valid(_map_menu): _map_menu.hide()
	_context_region = {}
	var index: int = _hit_index(at)
	if index < 0 or not map_target.is_valid() or not hits[index].has("region"): return
	_context_region = map_target.call(hits[index].region)
	if _context_region.is_empty(): return
	if not is_instance_valid(_map_menu):
		_map_menu = PopupMenu.new(); _map_menu.name = "ProvinceContextMenu"
		_map_menu.add_item("Перейти",0); add_child(_map_menu)
		_map_menu.id_pressed.connect(func(id: int):
			_map_menu.hide()
			if id == 0 and not _context_region.is_empty(): province_requested.emit(_context_region.duplicate()))
	_map_menu.popup(Rect2i(Vector2i(get_screen_transform()*at),Vector2i(160,0)))
func _make_custom_tooltip(for_text: String) -> Object:
	return preload("res://mods/pax_harness/chat_tooltip.gd").make(self,for_text)
func _hit(rect: Rect2, text: String, polygon: PackedVector2Array = PackedVector2Array()) -> void:
	var row: Dictionary = {"rect":rect,"text":text}
	if not polygon.is_empty(): row.polygon = polygon
	hits.append(row)
func _text(text: String, at: Vector2, width: float, color: Color = Color("#aab2bf"), align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, font_size: int = 12) -> void:
	Text.draw_text(self,text,Rect2(at-Vector2(0,get_theme_default_font().get_ascent(font_size)),Vector2(maxf(1,width),0)),color,align,font_size,text_boxes)

func _height(text: String, width: float) -> float:
	return Text.height(text,maxf(1,width),get_theme_default_font())

func _key(text: String, color: Color = Color("#b9c3d3"), identity: String = "") -> String:
	for entry: Dictionary in _next_keys:
		if (identity != "" and entry.get("identity","") == identity) or (identity == "" and entry.text == text): return entry.code
	var code := "["+str(_next_keys.size()+1)+"]"
	_next_keys.append({"code":code,"text":text,"color":color,"identity":identity})
	return code

func _fit(text: String, rect: Rect2, color: Color = Color("#c9d3e3"), align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var shown: String = text if _height(text,rect.size.x) <= rect.size.y else _key(text,color)
	if _height(shown,rect.size.x) <= rect.size.y:
		Text.draw_text(self,shown,rect,color,align,12,text_boxes)

func _grow_height(value: float) -> void:
	if not is_equal_approx(custom_minimum_size.y,value): custom_minimum_size.y = value

static func wrap_label(text: String, width: float, font: Font, font_size: int = 12) -> PackedStringArray:
	return Text.wrap_lines(text,width,font,font_size)
func _amount(value: float) -> String: return Chart.number(value)+(" "+str(spec.unit) if spec.get("unit","") != "" else "")
func _fill(polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty(): draw_colored_polygon(polygon,color)
func _area() -> Rect2:
	var top: float = 20+maxf(18,_height(str(spec.get("y_label",spec.get("unit",""))),size.x-20))
	var bottom: float = 66+maxf(20,_height(str(spec.get("x_label","")),maxf(1,size.x-96)))
	_grow_height(maxf(340,top+bottom+(maxf(180,spec.groups.size()*60) if spec.type == "ridgeline" else 180)))
	return Rect2(76,top,maxf(1,size.x-96),maxf(100,size.y-top-bottom))
func _axes(area: Rect2, low: float, high: float, left: float, right: float, categories: Array = [], options: Dictionary = {}) -> void:
	for tick: int in 5:
		var y: float = area.position.y+area.size.y*tick/4.0
		draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(0.6,0.68,0.8,0.12),1,true)
		if options.get("y_ticks",true): _text(Chart.number(lerpf(high,low,tick/4.0)),Vector2(0,y+4),area.position.x-10,Color("#9ba6b8"),HORIZONTAL_ALIGNMENT_RIGHT)
	var count: int = 5 if area.size.x > 450 else 3 if area.size.x > 210 else 2
	if categories.is_empty():
		for tick: int in count:
			var fraction: float = float(tick)/(count-1)
			var width: float = minf(76,area.size.x/(count-1)-6)
			_fit(Chart.number(lerpf(left,right,fraction)),Rect2(clampf(area.position.x+fraction*area.size.x-width/2,area.position.x,size.x-width-10),area.end.y+8,width,36))
	else:
		var step: float = area.size.x/categories.size()
		for i: int in categories.size():
			var rect := Rect2(area.position.x+i*step+2,area.end.y+8,maxf(1,step-4),36)
			if step < 30:
				var code: String = _key(str(categories[i]))
				var skip: int = ceili(36/maxf(1,step))
				if i % skip == 0: _fit(code,Rect2(clampf(rect.position.x,area.position.x,size.x-46),rect.position.y,32,36))
			else: _fit(str(categories[i]),rect)
	Text.draw_text(self,str(options.get("y",spec.get("y_label",spec.get("unit","")))),Rect2(10,8,size.x-20,0),Color("#9ba6b8"),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)
	Text.draw_text(self,str(options.get("x",spec.get("x_label",""))),Rect2(area.position.x,area.end.y+52,area.size.x,0),Color("#9ba6b8"),HORIZONTAL_ALIGNMENT_CENTER,12,text_boxes)
func _color(value: float, low: float, high: float) -> Color:
	if low < 0 and high > 0:
		return Color("#29303c").lerp(Color("#dd8997") if value < 0 else COLORS[0],absf(value)/maxf(0.000001,-low if value < 0 else high))
	return Color("#283b58").lerp(COLORS[0],clampf((value-low)/maxf(0.000001,high-low),0,1))
func _draw() -> void:
	hits.clear()
	text_boxes.clear(); _next_keys.clear()
	if size.x < 50: return
	draw_style_box(Style.box(Color("#1b1e24"),6,Color("#292e38"),0),Rect2(Vector2.ZERO,size))
	match spec.type:
		"column","stacked_column": _columns()
		"scatter","bubble": _scatter()
		"heatmap": _heatmap()
		"sankey": _sankey()
		"treemap": _treemap()
		"waterfall": _waterfall()
		"histogram": _histogram()
		"radar": _radar()
		"boxplot": _boxplot()
		"stacked_area": _stacked_area()
		"choropleth","cartogram": _map()
		"density","violin","ridgeline": _distributions()
	if caption_keys != _next_keys:
		caption_keys = _next_keys.duplicate(true)
		captions_changed.emit.call_deferred(caption_keys)
	if focus_index() >= 0 and focus_index() < hits.size():
		var row: Dictionary = hits[focus_index()]
		if row.has("polygon"):
			draw_polyline(row.polygon+PackedVector2Array([row.polygon[0]]),Color(Color("#d9e6ff"),hover_mix*0.8),1.5,true)
		else: draw_style_box(Style.box(Color(1,1,1,0.07*hover_mix),4,Color.TRANSPARENT,0),row.rect)

func _scatter() -> void:
	var left: float = spec.x.min(); var right: float = spec.x.max()
	var low := INF; var high := -INF
	for row: Dictionary in spec.series:
		low = minf(low,row.values.min()); high = maxf(high,row.values.max())
	if left == right: left -= 1; right += 1
	if low == high: low -= 1; high += 1
	var pad: float = (high-low)*0.08; low -= pad; high += pad
	var area: Rect2 = _area(); _axes(area,low,high,left,right)
	var maximum: float = spec.sizes.max() if spec.type == "bubble" else 1.0
	for s: int in spec.series.size():
		for i: int in spec.labels.size():
			var radius: float = 28*sqrt(float(spec.sizes[i])/maximum) if spec.type == "bubble" else 4.5
			if radius <= 0: continue
			var point: Vector2 = area.position+Vector2((float(spec.x[i])-left)/(right-left)*area.size.x,(high-float(spec.series[s].values[i]))/(high-low)*area.size.y)
			draw_circle(point,radius,Color(COLORS[s],0.3 if spec.type == "bubble" else 0.85),true,-1,true)
			draw_arc(point,radius,0,TAU,48,COLORS[s],1.2,true)
			var text: String = str(spec.labels[i])+"\n"+str(spec.get("x_label","x"))+": "+Chart.number(spec.x[i])+"\n"+str(spec.series[s].name)+": "+_amount(spec.series[s].values[i])
			if spec.type == "bubble": text += "\n"+str(spec.get("size_label","Размер"))+": "+Chart.number(spec.sizes[i])
			_hit(Rect2(point-Vector2.ONE*maxf(7,radius),Vector2.ONE*maxf(14,radius*2)),text)

func _columns() -> void:
	var low := 0.0; var high := 0.0
	for i: int in spec.labels.size():
		var total := 0.0
		for row: Dictionary in spec.series:
			low = minf(low,row.values[i]); high = maxf(high,row.values[i]); total += float(row.values[i])
		if spec.type == "stacked_column": high = maxf(high,total)
	if low == high: high = low+1
	var area: Rect2 = _area(); _axes(area,low,high,0,spec.labels.size()-1,spec.labels)
	var step: float = area.size.x/spec.labels.size()
	for i: int in spec.labels.size():
		var start := 0.0
		for s: int in spec.series.size():
			var value: float = spec.series[s].values[i]
			var base: float = start if spec.type == "stacked_column" else 0.0
			var width: float = step*0.75/(1 if spec.type == "stacked_column" else spec.series.size())
			var y1: float = area.end.y-(base-low)/(high-low)*area.size.y
			var y2: float = area.end.y-(base+value-low)/(high-low)*area.size.y
			var rect := Rect2(area.position.x+i*step+step*0.125+(0 if spec.type == "stacked_column" else s*width),minf(y1,y2),maxf(1,width-1),maxf(1,absf(y2-y1)))
			draw_style_box(Style.box(Color(COLORS[s],0.85),3,Color.TRANSPARENT,0),rect)
			_hit(rect.grow(2),str(spec.labels[i])+" · "+str(spec.series[s].name)+": "+_amount(value))
			start += value

func _heatmap() -> void:
	var low := INF; var high := -INF
	for row: Array in spec.matrix:
		for value: Variant in row:
			if value != null: low = minf(low,value); high = maxf(high,value)
	if low == INF: low = 0; high = 1
	var left: float = clampf(size.x*0.28,70,160)
	var header := 52.0
	var footer_text: String = "От "+Chart.number(low)+" до "+_amount(high)+" · серый — нет данных"
	var footer: float = _height(footer_text,size.x-20)+18
	var row_height := 30.0
	for text: String in spec.labels: row_height = maxf(row_height,_height(text,left-20)+12)
	_grow_height(maxf(320,header+row_height*spec.labels.size()+footer))
	var area := Rect2(left,header,maxf(1,size.x-left-18),maxf(row_height*spec.labels.size(),size.y-header-footer))
	var cell := Vector2(area.size.x/spec.columns.size(),area.size.y/spec.labels.size())
	for r: int in spec.labels.size():
		var label_height: float = _height(str(spec.labels[r]),left-20)
		Text.draw_text(self,str(spec.labels[r]),Rect2(10,area.position.y+r*cell.y+(cell.y-label_height)/2,left-20,label_height),Color("#aab2bf"),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)
		for c: int in spec.columns.size():
			var value: Variant = spec.matrix[r][c]
			var rect := Rect2(area.position+Vector2(c,r)*cell,cell-Vector2(2,2))
			draw_style_box(Style.box(Color("#30343e") if value == null else _color(value,low,high),3,Color.TRANSPARENT,0),rect)
			if cell.x >= 48: _fit("—" if value == null else Chart.number(value),Rect2(rect.position+Vector2(3,(cell.y-20)/2),Vector2(rect.size.x-6,20)),Color("#edf2fb"))
			_hit(rect,str(spec.labels[r])+" · "+str(spec.columns[c])+": "+("нет данных" if value == null else _amount(value)))
	for c: int in spec.columns.size():
		var code: String = _key(str(spec.columns[c])) if cell.x < 32 else str(spec.columns[c])
		var skip: int = ceili(36/maxf(1,cell.x))
		if cell.x >= 32 or c % skip == 0: _fit(code,Rect2(area.position.x+c*cell.x+2,8,maxf(30,cell.x-4),36))
	Text.draw_text(self,footer_text,Rect2(10,area.end.y+10,size.x-20,0),Color("#aab2bf"),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)

func _treemap() -> void:
	var items: Array = []
	for index: int in spec.labels.size():
		if spec.series[0].values[index] > 0: items.append({"index":index,"value":float(spec.series[0].values[index])})
	items.sort_custom(func(a: Dictionary,b: Dictionary): return a.value > b.value)
	_tiles(items,Rect2(8,8,size.x-16,size.y-16))
func _tiles(items: Array, rect: Rect2) -> void:
	if items.is_empty(): return
	if items.size() == 1:
		var item: Dictionary = items[0]; var inner: Rect2 = rect.grow(-2)
		draw_style_box(Style.box(Color(COLORS[int(item.index)%COLORS.size()],0.38),4,Color(COLORS[int(item.index)%COLORS.size()],0.7),0),inner)
		if inner.size.x > 50 and inner.size.y > 38:
			_fit(str(spec.labels[item.index])+"\n"+_amount(item.value),Rect2(inner.position+Vector2(8,8),inner.size-Vector2(16,16)),Color("#e4eaf5"),HORIZONTAL_ALIGNMENT_LEFT)
		else:
			var code: String = _key(str(spec.labels[item.index])+": "+_amount(item.value),COLORS[int(item.index)%COLORS.size()])
			if inner.size.x >= 28 and inner.size.y >= 20: _fit(code,Rect2(inner.position+Vector2(2,2),inner.size-Vector2(4,4)))
		_hit(inner,str(spec.labels[item.index])+": "+_amount(item.value))
		return
	var total := 0.0
	for item: Dictionary in items: total += item.value
	var subtotal := 0.0; var split := 0
	while split < items.size()-1 and subtotal < total/2:
		subtotal += items[split].value; split += 1
	var ratio: float = subtotal/total
	var first: Rect2 = rect; var second: Rect2 = rect
	if rect.size.x >= rect.size.y:
		first.size.x *= ratio; second.position.x += first.size.x; second.size.x -= first.size.x
	else:
		first.size.y *= ratio; second.position.y += first.size.y; second.size.y -= first.size.y
	_tiles(items.slice(0,split),first); _tiles(items.slice(split),second)

func _waterfall() -> void:
	var levels: Array = []; var running := 0.0; var low := 0.0; var high := 0.0
	for i: int in spec.labels.size():
		var start: float = 0 if i in spec.get("total_indices",[]) else running
		running = float(spec.series[0].values[i]) if i in spec.get("total_indices",[]) else running+float(spec.series[0].values[i])
		levels.append(Vector2(start,running)); low = minf(low,minf(start,running)); high = maxf(high,maxf(start,running))
	if low == high: high += 1
	var area: Rect2 = _area(); _axes(area,low,high,0,spec.labels.size()-1,spec.labels)
	var step: float = area.size.x/spec.labels.size()
	for i: int in levels.size():
		var y1: float = area.end.y-(levels[i].x-low)/(high-low)*area.size.y
		var y2: float = area.end.y-(levels[i].y-low)/(high-low)*area.size.y
		var rect := Rect2(area.position.x+i*step+step*0.12,minf(y1,y2),step*0.76,maxf(1,absf(y2-y1)))
		draw_style_box(Style.box(COLORS[0] if i in spec.get("total_indices",[]) else COLORS[1] if levels[i].y >= levels[i].x else COLORS[4],3,Color.TRANSPARENT,0),rect)
		if i < levels.size()-1: draw_line(Vector2(rect.end.x,y2),Vector2(area.position.x+(i+1)*step+step*0.12,y2),Color("#647086"),1,true)
		_hit(rect.grow(3),str(spec.labels[i])+": "+_amount(spec.series[0].values[i])+"\nОстаток: "+_amount(levels[i].y))

func _histogram() -> void:
	var low: float = spec.samples.min(); var high: float = spec.samples.max()
	if low == high: low -= 0.5; high += 0.5
	var count: int = int(spec.get("bins",10)); var values: Array = []; values.resize(count); values.fill(0)
	var interval: float = (high-low)/count
	for value: float in spec.samples: values[clampi(floori((value-low)/interval),0,count-1)] += 1
	var area: Rect2 = _area(); _axes(area,0,maxf(1,values.max()),low,high)
	for i: int in count:
		var height: float = float(values[i])/maxf(1,values.max())*area.size.y
		var rect := Rect2(area.position.x+i*area.size.x/count,area.end.y-height,area.size.x/count-2,height)
		draw_style_box(Style.box(Color(COLORS[0],0.8),3,Color.TRANSPARENT,0),rect)
		_hit(Rect2(rect.position.x,area.position.y,rect.size.x,area.size.y),Chart.number(low+i*interval)+" … "+Chart.number(low+(i+1)*interval)+": "+str(values[i])+" наблюдений")

func _radar() -> void:
	var title: String = "Общая шкала: 0–"+Chart.number(float(spec.get("max",100)))
	var top: float = _height(title,size.x-20)+42
	var center := Vector2(size.x/2,(top+size.y-38)/2); var radius: float = minf((size.x-100)/2,(size.y-top-66)/2)
	var maximum: float = float(spec.get("max",100)); var count: int = spec.labels.size()
	for ring: int in range(1,6):
		var points := PackedVector2Array()
		for i: int in count: points.append(center+Vector2.from_angle(-PI/2+TAU*i/count)*radius*ring/5)
		draw_polyline(points+PackedVector2Array([points[0]]),Color(0.6,0.68,0.8,0.15),1,true)
	for i: int in count:
		var direction: Vector2 = Vector2.from_angle(-PI/2+TAU*i/count)
		draw_line(center,center+direction*radius,Color(0.6,0.68,0.8,0.15),1,true)
		var code: String = _key(str(spec.labels[i]))
		_fit(code,Rect2(center+direction*(radius+22)-Vector2(19,9),Vector2(38,20)))
	for s: int in spec.series.size():
		var polygon := PackedVector2Array()
		for i: int in count:
			var point: Vector2 = center+Vector2.from_angle(-PI/2+TAU*i/count)*radius*float(spec.series[s].values[i])/maximum
			polygon.append(point)
			_hit(Rect2(point-Vector2(7,7),Vector2(14,14)),str(spec.series[s].name)+" · "+str(spec.labels[i])+": "+_amount(spec.series[s].values[i]))
		_fill(polygon,Color(COLORS[s],0.15)); draw_polyline(polygon+PackedVector2Array([polygon[0]]),COLORS[s],2,true)
	Text.draw_text(self,title,Rect2(10,8,size.x-20,0),Color("#aab2bf"),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)

func _boxplot() -> void:
	var low := INF; var high := -INF
	for box: Dictionary in spec.boxes: low = minf(low,box.min); high = maxf(high,box.max)
	if low == high: high = low+1
	var names: Array = []
	for box: Dictionary in spec.boxes: names.append(box.label)
	var area: Rect2 = _area(); _axes(area,low,high,0,spec.boxes.size()-1,names)
	var step: float = area.size.x/spec.boxes.size()
	for i: int in spec.boxes.size():
		var box: Dictionary = spec.boxes[i]; var x: float = area.position.x+(i+0.5)*step
		var y_min: float = area.end.y-(float(box.min)-low)/(high-low)*area.size.y; var y_max: float = area.end.y-(float(box.max)-low)/(high-low)*area.size.y
		var y1: float = area.end.y-(float(box.q1)-low)/(high-low)*area.size.y; var y3: float = area.end.y-(float(box.q3)-low)/(high-low)*area.size.y
		var median: float = area.end.y-(float(box.median)-low)/(high-low)*area.size.y; var width: float = minf(45,step*0.65)
		draw_line(Vector2(x,y_min),Vector2(x,y_max),COLORS[0],1.5,true)
		for y: float in [y_min,y_max]: draw_line(Vector2(x-width/3,y),Vector2(x+width/3,y),COLORS[0],1.5,true)
		draw_style_box(Style.box(Color(COLORS[0],0.35),3,COLORS[0],0),Rect2(x-width/2,y3,width,maxf(1,y1-y3)))
		draw_line(Vector2(x-width/2,median),Vector2(x+width/2,median),Color("#e8effc"),2,true)
		_hit(Rect2(x-step/2,area.position.y,step,area.size.y),str(box.label)+"\nmin: "+_amount(box.min)+"\nQ1: "+_amount(box.q1)+"\nМедиана: "+_amount(box.median)+"\nQ3: "+_amount(box.q3)+"\nmax: "+_amount(box.max))

func _stacked_area() -> void:
	var count: int = spec.labels.size(); var sums: Array = []; sums.resize(count); sums.fill(0.0)
	for row: Dictionary in spec.series:
		for i: int in count: sums[i] += float(row.values[i])
	var high: float = maxf(1,sums.max()); var area: Rect2 = _area()
	_axes(area,0,high,float(spec.x[0]) if spec.has("x") else 0.0,float(spec.x[-1]) if spec.has("x") else float(count-1),[],{"x":spec.get("x_label", "Шаг" if not spec.has("x") else "x")})
	var base: Array = []; base.resize(count); base.fill(0.0)
	for s: int in spec.series.size():
		var lower := PackedVector2Array(); var upper := PackedVector2Array()
		for i: int in count:
			var fraction: float = float(i)/maxi(1,count-1)
			if spec.has("x") and count > 1: fraction = (float(spec.x[i])-float(spec.x[0]))/(float(spec.x[-1])-float(spec.x[0]))
			var x: float = area.position.x+fraction*area.size.x
			lower.append(Vector2(x,area.end.y-float(base[i])/high*area.size.y))
			base[i] += float(spec.series[s].values[i]); upper.append(Vector2(x,area.end.y-float(base[i])/high*area.size.y))
			_hit(Rect2(x-6,area.position.y,12,area.size.y),str(spec.labels[i])+" · "+str(spec.series[s].name)+": "+_amount(spec.series[s].values[i]))
		lower.reverse(); _fill(upper+lower,Color(COLORS[s],0.6)); draw_polyline(upper,COLORS[s],1.5,true)

func _sankey() -> void:
	var selection: int = focus_index()
	var seed := ""
	if related_enabled and selection >= 0:
		if selection < spec.links.size(): seed = spec.links[selection].source
		elif selection-spec.links.size() < spec.nodes.size(): seed = spec.nodes[selection-spec.links.size()].id
	var focused: Dictionary = Focus.paths(spec.nodes,spec.links,seed)
	var layers: Dictionary = {}; var incoming: Dictionary = {}; var outgoing: Dictionary = {}; var weights: Dictionary = {}; var order: Dictionary = {}
	for i: int in spec.nodes.size():
		var id: String = spec.nodes[i].id; layers[id] = 0; incoming[id] = 0.0; outgoing[id] = 0.0; order[id] = i
	for edge: Dictionary in spec.links: incoming[edge.target] += float(edge.value); outgoing[edge.source] += float(edge.value)
	for iteration: int in spec.nodes.size():
		for edge: Dictionary in spec.links: layers[edge.target] = maxi(layers[edge.target],layers[edge.source]+1)
	var last: int = layers.values().max(); var buckets: Dictionary = {}; var maximum := 0.0
	var label_width: float = maxf(1,minf(230,(size.x-32)/maxi(1,last+1)-8))
	var captions: Dictionary = {}; var amounts: Dictionary = {}; var reserved := 0.0
	for id: String in layers:
		if not buckets.has(layers[id]): buckets[layers[id]] = []
		buckets[layers[id]].append(id); weights[id] = maxf(incoming[id],outgoing[id])
	for bucket: Array in buckets.values():
		var total := 0.0; var space := 0.0
		for id: String in bucket:
			total += weights[id]
			var full: String = str(spec.nodes[order[id]].label)
			if label_width < 32:
				_key(full,COLORS[int(order[id])%COLORS.size()]); captions[id] = PackedStringArray()
			else:
				captions[id] = wrap_label(full,label_width,get_theme_default_font())
				if captions[id].size() > 3: captions[id] = PackedStringArray([_key(full,COLORS[int(order[id])%COLORS.size()])])
			var amount_text: String = _amount(weights[id])
			if incoming[id] > 0 and outgoing[id] > 0 and not is_equal_approx(incoming[id],outgoing[id]): amount_text = "Вход: "+_amount(incoming[id])+"\nВыход: "+_amount(outgoing[id])
			amounts[id] = wrap_label(amount_text,label_width,get_theme_default_font()) if label_width >= 32 else PackedStringArray()
			space += (captions[id].size()+amounts[id].size())*Text.line_height(get_theme_default_font())+30
		maximum = maxf(maximum,total); reserved = maxf(reserved,space)
	var required_height: float = maxf(380,reserved+220)
	if not is_equal_approx(custom_minimum_size.y,required_height): custom_minimum_size.y = required_height
	var top: float = 60 if label_width < 32 else 25
	if label_width < 32: Text.draw_text(self,"Подписи узлов — в списке под схемой",Rect2(12,8,size.x-24,0),Color("#b9c3d3"),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)
	var scale: float = minf(150,maxf(1,size.y-top-29-reserved))/maxf(0.000001,maximum)
	var positions: Dictionary = {}; var out_y: Dictionary = {}; var in_y: Dictionary = {}
	for layer: int in buckets:
		var group_height := 0.0
		for id: String in buckets[layer]: group_height += maxf(2,weights[id]*scale)+(captions[id].size()+amounts[id].size())*Text.line_height(get_theme_default_font())+30
		var y: float = top+maxf(0,(size.y-top-12-group_height)/2)
		for id: String in buckets[layer]:
			var rect := Rect2(16+(float(layer)+0.5)*(size.x-32)/(last+1)-4,y,8,maxf(2,weights[id]*scale))
			positions[id] = rect; out_y[id] = y; in_y[id] = y; y += rect.size.y+(captions[id].size()+amounts[id].size())*Text.line_height(get_theme_default_font())+30
	for edge: Dictionary in spec.links:
		var from: Rect2 = positions[edge.source]; var to: Rect2 = positions[edge.target]
		var width: float = float(edge.value)*scale; var polygon := PackedVector2Array(); var bottom := PackedVector2Array()
		var steps: int = clampi(ceili(absf(to.position.x-from.end.x)/3),40,160)
		var control_x: float = (to.position.x-from.end.x)*0.48
		for step: int in steps+1:
			var t: float = float(step)/steps
			var point: Vector2 = Vector2(from.end.x,out_y[edge.source]).bezier_interpolate(Vector2(from.end.x+control_x,out_y[edge.source]),Vector2(to.position.x-control_x,in_y[edge.target]),Vector2(to.position.x,in_y[edge.target]),t)
			polygon.append(point); bottom.append(point+Vector2(0,width))
		var source_color: Color = COLORS[int(order[edge.source])%COLORS.size()]
		var target_color: Color = COLORS[int(order[edge.target])%COLORS.size()]
		var emphasis: float = lerpf(1,1.7 if focused.has(edge.source) and focused.has(edge.target) else 0.12,hover_mix) if not focused.is_empty() else 1.0
		var colors := PackedColorArray()
		for step: int in steps+1: colors.append(Color(source_color.lerp(target_color,float(step)/steps),0.20*emphasis))
		var upper: PackedVector2Array = polygon.duplicate()
		bottom.reverse(); polygon.append_array(bottom)
		for step: int in steps+1: colors.append(Color(source_color.lerp(target_color,1-float(step)/steps),0.20*emphasis))
		if not Geometry2D.triangulate_polygon(polygon).is_empty(): draw_polygon(polygon,colors)
		draw_polyline(upper,Color(source_color,minf(0.9,0.42*emphasis)),1,true)
		draw_polyline(bottom,Color(target_color,minf(0.9,0.32*emphasis)),1,true)
		_hit(Rect2(from.end.x,minf(out_y[edge.source],in_y[edge.target]),to.position.x-from.end.x,absf(in_y[edge.target]-out_y[edge.source])+width),str(spec.nodes[order[edge.source]].label)+" → "+str(spec.nodes[order[edge.target]].label)+": "+_amount(edge.value),polygon)
		out_y[edge.source] += width; in_y[edge.target] += width
	for node: Dictionary in spec.nodes:
		var rect: Rect2 = positions[node.id]
		draw_style_box(Style.box(COLORS[int(order[node.id])%COLORS.size()],3,Color.TRANSPARENT,0),rect)
		if not captions[node.id].is_empty():
			var caption := Rect2(clampf(rect.get_center().x-label_width/2,12,size.x-label_width-12),rect.end.y+9,label_width,captions[node.id].size()*Text.line_height(get_theme_default_font()))
			Text.draw_text(self,"\n".join(captions[node.id]),caption,Color("#d6dfef"),HORIZONTAL_ALIGNMENT_CENTER,12,text_boxes)
			var amount_rect := Rect2(caption.position+Vector2(0,caption.size.y+3),Vector2(label_width,amounts[node.id].size()*Text.line_height(get_theme_default_font())))
			Text.draw_text(self,"\n".join(amounts[node.id]),amount_rect,Color("#91a1b8"),HORIZONTAL_ALIGNMENT_CENTER,12,text_boxes)
		_hit(rect.grow(3),str(node.label)+"\nВход: "+_amount(incoming[node.id])+"\nВыход: "+_amount(outgoing[node.id]))

func _map() -> void:
	var low := INF; var high := -INF
	for region: Dictionary in spec.regions:
		if region.value != null: low = minf(low,region.value); high = maxf(high,region.value)
	if low == INF: low = 0; high = 1
	var footer_text: String = ("Схематичная картограмма · " if spec.type == "cartogram" else "")+Chart.number(low)+" … "+_amount(high)+" · серый — нет данных"
	var footer: float = _height(footer_text,size.x-28)+24
	var area := Rect2(14,14,size.x-28,size.y-14-footer)
	if spec.type == "choropleth":
		var aspect: float = float(spec.get("aspect",1.6))
		var dimensions := Vector2(minf(area.size.x,area.size.y*aspect),minf(area.size.y,area.size.x/aspect))
		area = Rect2(area.get_center()-dimensions/2,dimensions)
		for region: Dictionary in spec.regions:
			for raw: Array in region.polygons:
				var polygon := PackedVector2Array()
				for point: Array in raw: polygon.append(area.position+Vector2(point[0],point[1])*area.size)
				_fill(polygon,Color("#3b404a") if region.value == null else _color(region.value,low,high))
				draw_polyline(polygon+PackedVector2Array([polygon[0]]),Color("#171c24"),1,true)
				var bounds := Rect2(polygon[0],Vector2.ZERO)
				for point: Vector2 in polygon: bounds = bounds.expand(point)
				_hit(bounds,str(region.label)+": "+("нет данных" if region.value == null else _amount(region.value)),polygon)
				hits[-1]["region"] = {"id":str(region.id),"label":str(region.label),"body":str(spec.get("body",""))}
	else:
		var columns: int = ceili(sqrt(spec.regions.size()*1.6)); var rows: int = ceili(float(spec.regions.size())/columns)
		var cell := Vector2(area.size.x/columns,area.size.y/rows); var used: Dictionary = {}
		for i: int in spec.regions.size():
			var region: Dictionary = spec.regions[i]; var preferred: Array = region.get("center",[float(i%columns)/maxi(1,columns-1),float(i/columns)/maxi(1,rows-1)])
			var best := -1; var distance := INF
			for candidate: int in columns*rows:
				if used.has(candidate): continue
				var d: float = Vector2(float(candidate%columns)/maxi(1,columns-1)-float(preferred[0]),float(candidate/columns)/maxi(1,rows-1)-float(preferred[1])).length_squared()
				if d < distance: distance = d; best = candidate
			used[best] = true
			var rect := Rect2(area.position+Vector2(best%columns,best/columns)*cell,cell-Vector2(3,3))
			draw_style_box(Style.box(Color("#3b404a") if region.value == null else _color(region.value,low,high),4,Color.TRANSPARENT,0),rect)
			_fit(str(region.label)+"\n"+("—" if region.value == null else _amount(region.value)),Rect2(rect.position+Vector2(6,6),rect.size-Vector2(12,12)),Color("#e5edf9"))
			_hit(rect,str(region.label)+": "+("нет данных" if region.value == null else _amount(region.value)))
			hits[-1]["region"] = {"id":str(region.id),"label":str(region.label),"body":str(spec.get("body",""))}
	Text.draw_text(self,footer_text,Rect2(14,area.end.y+10,size.x-28,0),Color("#aab2bf"),HORIZONTAL_ALIGNMENT_LEFT,12,text_boxes)

func _bandwidth(values: Array) -> float:
	if spec.has("bandwidth"): return float(spec.bandwidth)
	var mean := 0.0; var variance := 0.0
	for value: float in values: mean += value/values.size()
	for value: float in values: variance += pow(value-mean,2)/maxi(1,values.size()-1)
	return maxf(0.000001,maxf(absf(mean)*0.01,1.06*sqrt(variance)*pow(values.size(),-0.2)))
func _density(values: Array, x: float, bandwidth: float) -> float:
	var total := 0.0
	for value: float in values: total += exp(-0.5*pow((x-value)/bandwidth,2))
	return total/(values.size()*bandwidth*sqrt(TAU))
func _distributions() -> void:
	var low := INF; var high := -INF; var bandwidths: Array = []; var peak := 0.0
	for group: Dictionary in spec.groups:
		var width: float = _bandwidth(group.samples); bandwidths.append(width)
		low = minf(low,group.samples.min()-width*3); high = maxf(high,group.samples.max()+width*3)
	var curves: Array = []
	for i: int in spec.groups.size():
		var values: Array = []
		for sample: int in 81:
			var value: float = _density(spec.groups[i].samples,lerpf(low,high,sample/80.0),bandwidths[i])
			values.append(value); peak = maxf(peak,value)
		curves.append(values)
	var area: Rect2 = _area()
	if spec.type == "violin":
		var names: Array = []
		for group: Dictionary in spec.groups: names.append(str(group.name)+" · n="+str(group.samples.size()))
		_axes(area,low,high,0,spec.groups.size()-1,names,{"x":"","y":str(spec.get("unit","Значение"))})
	elif spec.type == "density": _axes(area,0,peak,low,high,[],{"x":str(spec.get("x_label",spec.get("unit","Значение"))),"y":"Оценка плотности"})
	else:
		_axes(area,0,1,low,high,[],{"y_ticks":false,"y":"Оценка плотности","x":str(spec.get("x_label",spec.get("unit","Значение")))})
	for i: int in curves.size():
		var upper := PackedVector2Array(); var lower := PackedVector2Array()
		for sample: int in 81:
			var fraction: float = sample/80.0
			if spec.type == "violin":
				var x: float = area.position.x+(i+0.5)*area.size.x/curves.size()
				var y: float = area.end.y-fraction*area.size.y
				var width: float = float(curves[i][sample])/maxf(1.0e-15,peak)*minf(70,area.size.x/curves.size()*0.4)
				upper.append(Vector2(x-width,y)); lower.append(Vector2(x+width,y))
			else:
				var baseline: float = area.end.y if spec.type == "density" else area.position.y+(i+1)*area.size.y/curves.size()
				var height: float = area.size.y if spec.type == "density" else area.size.y/curves.size()*0.85
				upper.append(Vector2(area.position.x+fraction*area.size.x,baseline-float(curves[i][sample])/maxf(1.0e-15,peak)*height))
				lower.append(Vector2(area.position.x+fraction*area.size.x,baseline))
				if spec.type == "density": _hit(Rect2(upper[-1]-Vector2(6,6),Vector2(12,12)),str(spec.groups[i].name)+" · n="+str(spec.groups[i].samples.size())+"\nx: "+Chart.number(lerpf(low,high,fraction))+"\nПлотность: "+str(snappedf(curves[i][sample],0.00001)))
		lower.reverse(); _fill(upper+lower,Color(COLORS[i%COLORS.size()],0.25)); draw_polyline(upper,COLORS[i%COLORS.size()],2,true)
		var text: String = str(spec.groups[i].name)+" · n="+str(spec.groups[i].samples.size())+(" · малая выборка" if spec.groups[i].samples.size() < 20 else "")
		if spec.type == "violin":
			draw_polyline(lower,COLORS[i%COLORS.size()],2,true)
		elif spec.type == "density": _key(text,COLORS[i%COLORS.size()])
		else:
			var code: String = _key(text,COLORS[i%COLORS.size()])
			_fit(code,Rect2(6,area.position.y+i*area.size.y/curves.size()+4,52,20),COLORS[i%COLORS.size()])
		if spec.type != "density":
			var region: Rect2 = Rect2(area.position.x+i*area.size.x/curves.size(),area.position.y,area.size.x/curves.size(),area.size.y) if spec.type == "violin" else Rect2(area.position.x,area.position.y+i*area.size.y/curves.size(),area.size.x,area.size.y/curves.size())
			_hit(region,text+"\nСглаженная оценка плотности; bandwidth="+Chart.number(bandwidths[i]))
