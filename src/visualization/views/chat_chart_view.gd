extends VBoxContainer
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Native, resize-aware charts. The complete data stays in the saved message.
const Chart = preload("res://mods/pax_harness/src/visualization/specs/chat_chart.gd")
const Text = preload("res://mods/pax_harness/src/visualization/chart_text.gd")
const COLORS := [Color("#879fce"), Color("#6cb6a1"), Color("#d4b578"), Color("#b696cc"), Color("#c88289"), Color("#71b7ce"), Color("#b5ba75"), Color("#d39c73"), Color("#8b91d0"), Color("#91bdb9"), Color("#b7a5a1"), Color("#8aa7bc")]
var spec: Dictionary = {}
signal resource_hovered(label: String)
signal province_requested(region: Dictionary)
var map_target: Callable
var _plot: Control
var _caption_list: VBoxContainer
var _body: VBoxContainer
var controls: VBoxContainer
var _data_disclosure: Control
var _entry_tween: Tween

func _show_caption_keys(entries: Array) -> void:
	if not is_instance_valid(_caption_list): return
	for child: Node in _caption_list.get_children():
		_caption_list.remove_child(child); child.queue_free()
	_caption_list.visible = not entries.is_empty()
	for entry: Dictionary in entries:
		var item := Label.new()
		item.text = str(entry.code)+"  "+str(entry.text)
		item.set_meta("mod_user_text",true)
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_theme_font_size_override("font_size",12)
		item.add_theme_color_override("font_color",entry.get("color",Color("#b9c3d3")))
		_caption_list.add_child(item)

func setup(value: Dictionary) -> void:
	spec = Chart.validate(value)
	if spec.is_empty(): return
	name = "EconomicChart"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = str(spec.title)
	heading.set_meta("mod_user_text",true)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 17)
	add_child(heading)
	if spec.get("basis","observed") != "observed":
		var caption := Label.new()
		caption.text = L.text("Сценарный расчёт") if spec.basis == "scenario" else L.text("Прогноз")
		caption.add_theme_color_override("font_color",Color("#d4b578"))
		add_child(caption)
	controls = preload("res://mods/pax_harness/src/visualization/controls/chart_controls.gd").new()
	controls.setup(self,spec); add_child(controls)
	_body = VBoxContainer.new(); _body.add_theme_constant_override("separation",12); add_child(_body)
	apply_display(spec)

func _ready() -> void: replay_animation()

func replay_animation() -> void:
	if not is_instance_valid(_body): return
	if _entry_tween != null and _entry_tween.is_valid(): _entry_tween.kill()
	_body.modulate.a = 1
	if controls.animation_enabled:
		_body.modulate.a = 0.25
		_entry_tween = create_tween(); _entry_tween.tween_property(_body,"modulate:a",1.0,0.20)
	if is_instance_valid(_plot) and _plot.has_method("replay_animation"): _plot.replay_animation()

func stop_animation() -> void:
	if _entry_tween != null and _entry_tween.is_valid(): _entry_tween.kill()
	if is_instance_valid(_body): _body.modulate.a = 1

func apply_display(value: Dictionary) -> void:
	var previous_zoom: float = controls.viewport.target_zoom if is_instance_valid(controls.viewport) else 1.0
	for child: Node in _body.get_children(): _body.remove_child(child); child.queue_free()
	_plot = null; _caption_list = null; _data_disclosure = null
	var data: Dictionary = Chart.validate(value)
	if data.is_empty():
		controls.viewport = null
		var empty := Label.new(); empty.text = L.text("По этому фильтру нет данных. Измените фильтр или нажмите «Сброс»."); empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _body.add_child(empty)
		return
	_build_display(data)
	if previous_zoom != 1: controls.viewport.change_zoom(previous_zoom)
	if is_inside_tree(): replay_animation()

func _build_display(spec: Dictionary) -> void:
	if spec.type in Chart.Extra.TYPES:
		var canvas: Control
		if spec.type in Chart.Extra.Extended.TYPES: canvas = preload("res://mods/pax_harness/src/visualization/views/chart_extended_view.gd").new()
		elif spec.type in ["gantt","network","sunburst"]: canvas = preload("res://mods/pax_harness/src/visualization/views/chart_strategy_view.gd").new()
		else: canvas = preload("res://mods/pax_harness/src/visualization/views/chart_extra_view.gd").new()
		_plot = canvas
		canvas.setup(spec)
		canvas.map_target = map_target
		canvas.province_requested.connect(func(region: Dictionary): province_requested.emit(region))
		if spec.type in ["gantt","network","sunburst"]: canvas.drill_changed.connect(replay_animation)
		canvas.captions_changed.connect(func(entries: Array): if _plot == canvas: _show_caption_keys(entries))
	else:
		var canvas := Plot.new()
		_plot = canvas
		canvas.spec = spec
		canvas.captions_changed.connect(func(entries: Array): if _plot == canvas: _show_caption_keys(entries))
		canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		canvas.custom_minimum_size.y = 270 if spec.type in ["line","area"] else maxf(220, spec.labels.size()*25) if spec.type in ["donut","pie"] else spec.labels.size()*(40+spec.series.size()*18)+(26 if spec.get("unit","") != "" else 0)
		canvas.mouse_filter = Control.MOUSE_FILTER_STOP
		canvas.resource_hovered.connect(func(label: String): resource_hovered.emit(label))
	var chart_viewport := preload("res://mods/pax_harness/src/visualization/controls/chart_viewport.gd").new()
	_body.add_child(chart_viewport); chart_viewport.setup(_plot); controls.bind(chart_viewport)
	_caption_list = VBoxContainer.new()
	_caption_list.name = "CaptionKey"
	_caption_list.visible = false
	_body.add_child(_caption_list)
	if spec.type not in ["donut","pie"] and spec.type not in Chart.Extra.Extended.TYPES and spec.get("series",[]).size() > 1:
		var legend := VBoxContainer.new()
		legend.add_theme_constant_override("h_separation", 18)
		for index: int in spec.series.size():
			var item := Label.new()
			item.text = "●  "+str(spec.series[index].name)
			item.set_meta("mod_user_text",true)
			item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item.add_theme_color_override("font_color", COLORS[index])
			legend.add_child(item)
		_body.add_child(legend)
	var source := Label.new()
	var aliases := {"orders.failed":"Архив проваленных планов","history.read":"История мира","resources.read":"Запасы ресурсов","money.read":"Казна","statistics":"сохранённая статистика"}
	var source_parts: Array = ["Источник: "]
	source_parts.append(aliases[spec.source] if aliases.has(spec.source) else {"value":spec.source})
	L.bind(source,"text",source_parts)
	source.set_meta("mod_user_text",true)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source.add_theme_font_size_override("font_size", 12)
	source.add_theme_color_override("font_color", Color("#949ba7"))
	_body.add_child(source)
	_data_disclosure = preload("res://mods/pax_harness/src/visualization/views/chart_data_view.gd").new()
	_data_disclosure.setup(self.spec,spec); _body.add_child(_data_disclosure)

func show_data() -> void:
	if is_instance_valid(_data_disclosure): _data_disclosure.visible = not _data_disclosure.visible

func highlight_resource(label: String) -> void:
	if is_instance_valid(_plot): _plot.link_resource(label)

class Plot extends Control:
	var spec: Dictionary
	var hits: Array = []
	var active := -1
	var text_boxes: Array = []
	var caption_keys: Array = []
	var _next_keys: Array = []
	var _line_bottom := 0.0
	var animation_enabled := true
	var _pie: ColorRect
	func set_chart_options(_related: bool, animate: bool) -> void: animation_enabled = animate
	signal captions_changed(entries: Array)
	signal resource_hovered(label: String)
	var linked_index := -1
	var strengths: Array[float] = []
	var focus_mix := 0.0
	func _ready() -> void:
		for index: int in spec.labels.size(): strengths.append(0.0)
		if spec.type == "pie":
			_pie = ColorRect.new()
			_pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pie.show_behind_parent = true
			var material := ShaderMaterial.new()
			material.shader = preload("res://mods/pax_harness/src/visualization/shaders/chart_pie_slice.gdshader")
			_pie.material = material
			add_child(_pie)
		resized.connect(_resize_plot)
		mouse_exited.connect(func(): _set_active(-1))
		focus_exited.connect(func(): _set_active(-1))
		focus_mode = Control.FOCUS_ALL
		set_process(false)
		_resize_plot()
	func _resize_plot() -> void:
		if spec.type in ["donut","pie"] and size.x > 0:
			var geometry: Dictionary = _donut_geometry()
			var total: float = 0
			for value: float in spec.series[0].values: total += value
			var height: float = geometry.legend_top+12
			for i: int in spec.labels.size(): height += maxf(25,_height(_legend_text(i,total),size.x-geometry.legend_left-24)+10)
			height = maxf(220,height)
			if custom_minimum_size.y != height: custom_minimum_size.y = height
		elif spec.type in ["bar","stacked_bar"] and size.x > 0:
			var height: float = _height(str(spec.get("unit","")),size.x-8)+12
			for text: String in spec.labels: height += _height(text,size.x-8)+34+(spec.series.size()*18 if spec.type == "bar" else 18)
			custom_minimum_size.y = height
		elif spec.type in ["line","area"] and size.x > 0:
			custom_minimum_size.y = maxf(270,110+_height(str(spec.get("y_label",spec.get("unit",""))),size.x-16)+_height(str(spec.get("x_label","")),size.x-100)+160)
		queue_redraw()
	func category() -> int:
		if active >= 0 and active < hits.size(): return int(hits[active].get("category",-1))
		return linked_index
	func link_resource(text: String) -> void:
		linked_index = -1
		if spec.type in ["bar","stacked_bar","donut","pie"] and text != "":
			for index: int in spec.labels.size():
				if str(spec.labels[index]).to_lower().strip_edges() == text.to_lower().strip_edges(): linked_index = index; break
		set_process(true)
		queue_redraw()
	func _set_active(index: int) -> void:
		tooltip_text = str(hits[index].text) if index >= 0 and index < hits.size() else ""
		if active == index: return
		active = index
		set_process(true)
		queue_redraw()
		var selected: int = int(hits[index].get("category",-1)) if index >= 0 and index < hits.size() else -1
		resource_hovered.emit(str(spec.labels[selected]) if selected >= 0 else "")
	func _process(delta: float) -> void:
		if not animation_enabled: delta = 1000
		var selected: int = category()
		var moving := false
		focus_mix = move_toward(focus_mix,1.0 if selected >= 0 else 0.0,delta*7)
		for index: int in strengths.size():
			var target: float = 1.0 if selected == index else 0.0
			strengths[index] = move_toward(strengths[index],target,delta*7)
			moving = moving or not is_equal_approx(strengths[index],target)
		queue_redraw()
		if not moving and is_equal_approx(focus_mix,1.0 if selected >= 0 else 0.0): set_process(false)
	func _index_at(point: Vector2) -> int:
		if spec.type in ["donut","pie"]:
			var geometry: Dictionary = _donut_geometry()
			var relative: Vector2 = point-geometry.center
			if relative.length() >= (0 if spec.type == "pie" else geometry.radius-36) and relative.length() <= geometry.radius+7:
				var ratio: float = fposmod(relative.angle()+PI/2,TAU)/TAU
				var total: float = 0.0
				for value: float in spec.series[0].values: total += value
				var end: float = 0.0
				for index: int in spec.labels.size():
					end += float(spec.series[0].values[index])/total
					if ratio < end: return index
		for index: int in hits.size():
			if hits[index].rect.has_point(point): return index
		return -1
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion: _set_active(_index_at(event.position))
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT] and spec.type in ["donut","pie"]:
			_set_active(posmod(active+(-1 if event.keycode in [KEY_UP,KEY_LEFT] else 1),spec.labels.size()))
			accept_event()
	func _get_tooltip(at_position: Vector2) -> String:
		var index: int = _index_at(at_position)
		return str(hits[index].text) if index >= 0 and index < hits.size() else ""
	func _make_custom_tooltip(for_text: String) -> Object:
		return preload("res://mods/pax_harness/src/ui/components/chat_tooltip.gd").make(self,for_text)
	func label(text: String, pos: Vector2, width: float, color: Color = Color("#e8e9ed"), align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
		Text.draw_text(self,text,Rect2(pos-Vector2(0,get_theme_default_font().get_ascent(13)),Vector2(maxf(1,width),0)),color,align,13,text_boxes)
	func _height(text: String, width: float) -> float:
		return Text.height(text,maxf(1,width),get_theme_default_font(),13)
	func _fit(text: String, rect: Rect2) -> void:
		var shown: String = text
		if _height(text,rect.size.x) > rect.size.y:
			shown = "["+str(_next_keys.size()+1)+"]"
			_next_keys.append({"code":shown,"text":text})
		Text.draw_text(self,shown,rect,Color("#a8afb9"),HORIZONTAL_ALIGNMENT_CENTER,13,text_boxes)
	func amount(value: float) -> String:
		return Chart.number(value)+(" "+str(spec.unit) if str(spec.get("unit", "")) != "" else "")
	func hit(rect: Rect2, text: String, item: int = -1) -> void:
		hits.append({"rect":rect, "text":text,"category":item})
	func _draw() -> void:
		hits.clear()
		text_boxes.clear(); _next_keys.clear()
		if size.x < 40: return
		if spec.type in ["line","area"]: draw_style_box(preload("res://mods/pax_harness/src/ui/components/chat_style.gd").box(Color("#1b1e24"),6,Color("#292e38"),0),Rect2(Vector2.ZERO,size))
		match spec.type:
			"bar", "stacked_bar": bars()
			"line", "area": lines()
			"donut", "pie": donut()
		if caption_keys != _next_keys:
			caption_keys = _next_keys.duplicate(true)
			captions_changed.emit.call_deferred(caption_keys)
	func highlight() -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1,1,1,0.06)
		return box
	func bars() -> void:
		var low := 0.0
		var high := 0.0
		for index: int in spec.labels.size():
			var sum := 0.0
			for series: Dictionary in spec.series:
				low = minf(low, series.values[index])
				high = maxf(high, series.values[index])
				sum += float(series.values[index])
			if spec.type == "stacked_bar": high = maxf(high, sum)
		if str(spec.get("unit", "")) == "%" and low == 0: high = maxf(high,100)
		if low == high: high = low + 1
		var value_width: float = clampf(get_theme_default_font().get_string_size(Chart.number(high),HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+12,110,size.x*0.4)
		var plot_width := maxf(1,size.x-value_width-10)
		var top_offset: float = _height(str(spec.get("unit","")),size.x-8)+12
		if spec.get("unit","") != "": label(str(spec.unit),Vector2(4,get_theme_default_font().get_ascent(13)),size.x-8,Color("#949ba7"),HORIZONTAL_ALIGNMENT_RIGHT)
		var zero := (-low)/(high-low)*plot_width
		var top: float = top_offset
		for index: int in spec.labels.size():
			var header_height: float = _height(str(spec.labels[index]),size.x-8)
			var row_height: float = header_height+34+(spec.series.size()*18 if spec.type == "bar" else 18)
			var strength: float = strengths[index] if index < strengths.size() else 0.0
			if strength > 0:
				var background := StyleBoxFlat.new(); background.bg_color = Color(1,1,1,0.025*strength); background.set_corner_radius_all(5)
				draw_style_box(background,Rect2(0,top-3,size.x,row_height-4))
			label(str(spec.labels[index]),Vector2(4,top+get_theme_default_font().get_ascent(13)),size.x-8,Color("#d0d1d3").lerp(Color("#89c8f4"),strength))
			var start := 0.0
			for s: int in spec.series.size():
				var value: float = spec.series[s].values[index]
				var y: float = top+header_height+8+(0 if spec.type == "stacked_bar" else s*18)
				var x: float = start if spec.type == "stacked_bar" else zero
				var end: float = x+value/(high-low)*plot_width
				if spec.type == "bar" or s == 0: draw_rect(Rect2(0,y,plot_width,10),Color("#292c32").lerp(Color("#333943"),strength))
				if not is_zero_approx(value): draw_rect(Rect2(minf(x,end),y-strength,maxf(1,absf(end-x)),10+2*strength),COLORS[s].lightened(0.12*strength))
				if spec.type == "bar":
					label(Chart.number(value),Vector2(plot_width+8,y+10),value_width,Color("#d0d1d3").lerp(Color("#e2e8f1"),strength))
					hit(Rect2(0,top if s == 0 else y-2,size.x,header_height+28 if s == 0 else 18),str(spec.labels[index])+" · "+str(spec.series[s].name)+": "+str(value)+" "+str(spec.get("unit","")),index)
				else:
					hit(Rect2(x,y-2,maxf(1,end-x),16),str(spec.labels[index])+" · "+str(spec.series[s].name)+": "+str(value)+" "+str(spec.get("unit","")),index)
				start = end
			if spec.type == "stacked_bar": label(Chart.number(start/plot_width*(high-low)),Vector2(plot_width+8,top+header_height+18),value_width)
			if low < 0: draw_line(Vector2(zero,top+header_height+4),Vector2(zero,top+row_height-16),Color("#777f8f"))
			top += row_height
	func lines() -> void:
		var low := 0.0
		var high := 0.0
		for series: Dictionary in spec.series:
			for value: Variant in series.values:
				if value != null: low = minf(low,float(value)); high = maxf(high,float(value))
		if low == high: high = low+1
		var top: float = 20+maxf(18,_height(str(spec.get("y_label",spec.get("unit",""))),size.x-16))
		var bottom: float = 70+_height(str(spec.get("x_label","")),size.x-100)
		var area := Rect2(86,top,maxf(1,size.x-100),size.y-top-bottom)
		_line_bottom = area.end.y
		for tick: int in 5:
			var y: float = area.position.y+area.size.y*tick/4.0
			draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(0.6,0.68,0.8,0.12),1,true)
			label(Chart.number(high-(high-low)*tick/4.0),Vector2(0,y+5),78,Color("#a8afb9"),HORIZONTAL_ALIGNMENT_RIGHT)
		var count: int = spec.labels.size()
		var label_step := maxi(1,ceili(count/maxf(2,area.size.x/90)))
		for s: int in spec.series.size():
			var points := PackedVector2Array()
			var last_label_end := -INF
			for i: int in count:
				if i in spec.get("breaks",[]):
					if not points.is_empty(): _stroke(points,s)
					points.clear()
				if spec.series[s].values[i] == null:
					if not points.is_empty(): _stroke(points,s)
					points.clear()
					continue
				var value: float = spec.series[s].values[i]
				var ratio: float = float(i)/maxi(1,count-1)
				if spec.has("x") and count > 1: ratio = (float(spec.x[i])-float(spec.x[0]))/(float(spec.x[-1])-float(spec.x[0]))
				var x: float = area.position.x+area.size.x*ratio
				var y: float = area.end.y-(value-low)/(high-low)*area.size.y
				points.append(Vector2(x,y))
				hit(Rect2(x-7,y-7,14,14),str(spec.labels[i])+"\n"+str(spec.series[s].name)+": "+amount(value))
				hits[-1]["series"] = s
				if s == 0 and (i % label_step == 0 or i == count-1):
					var left: float = clampf(x-40,area.position.x,size.x-90)
					if left >= last_label_end+4:
						_fit(str(spec.labels[i]),Rect2(left,area.end.y+8,85,38))
						last_label_end = left+85
			if not points.is_empty(): _stroke(points,s)
		if active >= 0 and active < hits.size():
			var point: Vector2 = hits[active].rect.get_center()
			draw_line(Vector2(point.x,area.position.y),Vector2(point.x,area.end.y),Color(0.65,0.75,0.95,0.3),1,true)
			var color: Color = COLORS[int(hits[active].get("series",0))]
			draw_circle(point,8,Color(color,0.18),true,-1,true)
			draw_circle(point,4.5,color.lightened(0.15),true,-1,true)
			draw_circle(point,2,Color("#edf4ff"),true,-1,true)
		var y_caption: String = str(spec.get("y_label",spec.get("unit","")))
		if y_caption != "": label(y_caption,Vector2(8,8+get_theme_default_font().get_ascent(13)),size.x-16,Color("#a8afb9"))
		if spec.get("x_label","") != "": label(str(spec.x_label),Vector2(area.position.x,area.end.y+54+get_theme_default_font().get_ascent(13)),area.size.x,Color("#a8afb9"),HORIZONTAL_ALIGNMENT_CENTER)
	func _stroke(points: PackedVector2Array, series: int) -> void:
		var path: PackedVector2Array = Chart.curve_points(points,str(spec.get("curve","linear")))
		if path.size() > 1:
			var polygon := PackedVector2Array(); var colors := PackedColorArray()
			var stride: int = maxi(1,ceili(path.size()/240.0))
			for index: int in range(0,path.size(),stride):
				polygon.append(path[index]); colors.append(Color(COLORS[series],0.3 if spec.type == "area" else 0.14 if spec.series.size() == 1 else 0.06))
			polygon.append(path[-1]); colors.append(colors[0])
			polygon.append(Vector2(path[-1].x,_line_bottom)); colors.append(Color(COLORS[series],0))
			polygon.append(Vector2(path[0].x,_line_bottom)); colors.append(Color(COLORS[series],0))
			if absf(path[-1].x-path[0].x) > 0.01 and not Geometry2D.triangulate_polygon(polygon).is_empty(): draw_polygon(polygon,colors)
			draw_polyline(path,COLORS[series].lightened(0.08),2.5,true)
		if spec.labels.size() <= 60:
			for point: Vector2 in points: draw_circle(point,3,COLORS[series].lightened(0.08),true,-1,true)
	func _donut_geometry() -> Dictionary:
		var narrow: bool = size.x < 500
		var radius: float = minf(90,size.x*0.26) if narrow else 90
		return {"radius":radius,"center":Vector2(size.x/2,102) if narrow else Vector2(radius+6,110),"legend_left":16.0 if narrow else radius*2+25,"legend_top":220.0 if narrow else 20.0}
	func _legend_text(index: int, total: float) -> String:
		var value: float = spec.series[0].values[index]
		var text: String = "["+str(index+1)+"] "+str(spec.labels[index])+": "+amount(value)
		if spec.get("unit","") != "%": text += " ("+Chart.number(value/total*100)+"%)"
		return text
	func _pie_circle(center: Vector2, radius: float, shapes: PackedVector4Array, edges: PackedVector4Array, colors: PackedColorArray) -> void:
		var count: int = shapes.size()
		shapes.resize(12); edges.resize(12); colors.resize(12)
		_pie.position = center-Vector2.ONE*(radius+8)
		_pie.size = Vector2.ONE*(radius*2+16)
		var material: ShaderMaterial = _pie.material
		material.set_shader_parameter("extent",radius+8)
		material.set_shader_parameter("sector_count",count)
		material.set_shader_parameter("sector_shapes",shapes)
		material.set_shader_parameter("sector_edges",edges)
		material.set_shader_parameter("sector_colors",colors)
	func donut() -> void:
		var geometry: Dictionary = _donut_geometry()
		var radius: float = geometry.radius
		var center: Vector2 = geometry.center
		var total := 0.0
		for value: float in spec.series[0].values: total += value
		var legend_width := 0.0
		for index: int in spec.labels.size(): legend_width = maxf(legend_width,get_theme_default_font().get_string_size(_legend_text(index,total),HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+27)
		legend_width = minf(legend_width,size.x-float(geometry.legend_left)+7)
		var angle := -PI/2
		var legend_y: float = geometry.legend_top
		var selected: int = category()
		var pie_shapes := PackedVector4Array(); var pie_edges := PackedVector4Array(); var pie_colors := PackedColorArray()
		for i: int in spec.labels.size():
			var value: float = spec.series[0].values[i]
			var next: float = angle+TAU*value/total
			var strength: float = strengths[i] if i < strengths.size() else 0.0
			var color: Color = COLORS[i].lightened(0.12*strength)
			color.a = 1-focus_mix*0.52*(1-strength)
			var offset := Vector2(cos((angle+next)/2),sin((angle+next)/2))*3.5*strength
			var gap: float = minf(0.006,(next-angle)/4)
			if value > 0:
				if spec.type == "pie":
					pie_shapes.append(Vector4(offset.x,offset.y,radius+strength,next-angle))
					var start_edge := Vector2.from_angle(angle); var end_edge := Vector2.from_angle(next)
					pie_edges.append(Vector4(start_edge.x,start_edge.y,end_edge.x,end_edge.y)); pie_colors.append(color)
				else: draw_arc(center+offset,radius-16+strength,angle+gap,next-gap,maxi(2,ceili((next-angle)*64)),color,28,true)
			var left: float = geometry.legend_left
			var y: float = legend_y
			var text: String = _legend_text(i,total)
			var row_height: float = maxf(25,_height(text,size.x-left-24)+10)
			if strength > 0:
				var background := StyleBoxFlat.new(); background.bg_color = Color(COLORS[i],0.11*strength); background.set_corner_radius_all(5)
				draw_style_box(background,Rect2(left-7,y-4,legend_width,row_height))
				draw_circle(Vector2(left+2*strength,y+7),7,Color(COLORS[i],0.15*strength),true,-1.0,true)
			draw_circle(Vector2(left+2*strength,y+7),4+strength,color,true,-1.0,true)
			var text_color: Color = Color("#d0d1d3").lerp(COLORS[i],strength)
			text_color.a = 1-focus_mix*0.4*(1-strength)
			label(text,Vector2(left+12,y+get_theme_default_font().get_ascent(13)),maxf(1,size.x-left-24),text_color)
			var details: String = str(spec.labels[i])+": "+str(value)+" "+str(spec.get("unit",""))
			if spec.get("unit","") != "%": details += " ("+Chart.number(value/total*100)+"%)"
			hit(Rect2(left-7,y-4,maxf(1,legend_width),row_height),details,i)
			legend_y += row_height
			angle = next
		if spec.type == "pie": _pie_circle(center,radius,pie_shapes,pie_edges,pie_colors)
		var center_text: String = Chart.number(float(spec.series[0].values[selected])/total*100)+" %" if selected >= 0 else Chart.number(total)
		if spec.type == "donut": label(center_text,Vector2(center.x-radius+12,center.y+2),radius*2-24,COLORS[selected] if selected >= 0 else Color("#d0d1d3"),HORIZONTAL_ALIGNMENT_CENTER)
		if selected >= 0 and spec.type == "donut": label("["+str(selected+1)+"]",Vector2(center.x-radius+12,center.y+24),radius*2-24,Color("#949ba7"),HORIZONTAL_ALIGNMENT_CENTER)
