extends "res://mods/pax_harness/src/visualization/views/chart_extra_view.gd"
## Measured native drawing; labels never silently truncated. Keys retain full text.
const Extended = preload("res://mods/pax_harness/src/visualization/specs/chart_extended_spec.gd")
var _linked := ""
var _hover_node_ids: Array = []
var _pinned_node_ids: Array = []
func setup(value: Dictionary) -> void:
 super.setup(value)
 name = "ExtendedPlot"
 custom_minimum_size.y = 380
func link_resource(label: String) -> void:
 _linked = label; queue_redraw()
func _gui_input(event: InputEvent) -> void:
 super._gui_input(event)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index == MOUSE_BUTTON_RIGHT and spec.type in ["symbol_map","flow_map"]:
   _open_map_menu(event.position); accept_event()
  elif event.button_index == MOUSE_BUTTON_LEFT:
   pinned = active if pinned != active else -1; _pinned_node_ids = _hover_node_ids.duplicate() if pinned >= 0 else []; set_process(true); grab_focus(); accept_event()
func _set_active(value: int) -> void:
 super._set_active(value)
 _hover_node_ids = hits[value].get("node_ids",[]).duplicate() if value >= 0 and value < hits.size() else []
 if value >= 0 and value < hits.size(): resource_hovered.emit(str(hits[value].get("label","")))
 else: resource_hovered.emit("")
func _draw() -> void:
 hits.clear(); text_boxes.clear(); _next_keys.clear()
 if size.x < 80: return
 draw_style_box(Style.box(Color("#1b1e24"),6,Color("#292e38"),0),Rect2(Vector2.ZERO,size))
 match spec.type:
  "combo","interval","errorbar","bump": _series_plot()
  "dumbbell": _dumbbell()
  "slope": _slope()
  "calendar_heatmap": _calendar()
  "symbol_map","flow_map": _geographic()
  "tree","icicle": _hierarchy()
  "parallel": _parallel()
  "small_multiples": _multiples()
 if caption_keys != _next_keys:
  caption_keys = _next_keys.duplicate(true); captions_changed.emit.call_deferred(caption_keys)
 var selected: int = focus_index()
 if selected >= 0 and selected < hits.size():
  var hit: Dictionary = hits[selected]
  if hit.has("polygon"): draw_polyline(hit.polygon+PackedVector2Array([hit.polygon[0]]),Color(0.93,0.97,1,0.8),1.5,true)
  elif hit.has("center"): draw_arc(hit.center,hit.radius+3,0,TAU,64,Color("#e1ebff"),1.8,true)
  else: draw_style_box(Style.box(Color(1,1,1,0.06),3,Color.TRANSPARENT,0),hit.rect)
func _entry(rect: Rect2, description: String, label: String = "") -> void:
 _hit(rect,description); hits[-1].label = label
func _bounds(rows: Array, keys: Array = ["values"], zero: bool = false) -> Vector2:
 var low := 0.0 if zero else INF; var high := 0.0 if zero else -INF
 for row: Dictionary in rows:
  for key: String in keys:
   for value: Variant in row.get(key,[]):
    if value != null: low = minf(low,float(value)); high = maxf(high,float(value))
 if not is_finite(low): low = 0; high = 1
 if is_equal_approx(low,high): low -= 0.5; high += 0.5
 return Vector2(low,high)
func _at(area: Rect2, i: int, count: int, value: float, bounds: Vector2, centered: bool = false, reverse: bool = false) -> Vector2:
 var x: float = (i+0.5)/count if centered else float(i)/maxi(1,count-1)
 var y: float = (value-bounds.x)/(bounds.y-bounds.x)
 return area.position+Vector2(x*area.size.x,(y if reverse else 1-y)*area.size.y)
func _series_plot() -> void:
 var is_bump: bool = spec.type == "bump"
 var bounds: Vector2 = _bounds(spec.series,["values","lower","upper"],spec.type == "combo")
 if is_bump: bounds.x = 1; bounds.y = maxf(2,bounds.y)
 var area: Rect2 = _area()
 _axes(area,bounds.y if is_bump else bounds.x,bounds.x if is_bump else bounds.y,0,spec.labels.size()-1,spec.labels,{"y_ticks":not is_bump,"y":L.text("Место · 1 — первое") if is_bump else spec.get("y_label",spec.get("unit",""))})
 if is_bump:
  var tick_count: int = mini(5,int(bounds.y))
  for tick: int in tick_count:
   var rank: int = roundi(lerpf(bounds.x,bounds.y,float(tick)/maxi(1,tick_count-1)))
   var y: float = area.position.y+(rank-bounds.x)/(bounds.y-bounds.x)*area.size.y
   _text(str(rank),Vector2(0,y+4),area.position.x-10,Color("#9ba6b8"),HORIZONTAL_ALIGNMENT_RIGHT)
 var centered := true
 var bar_count := 0
 for row: Dictionary in spec.series:
  if row.get("kind","") == "bar": bar_count += 1
 var bar_index := 0
 for s: int in spec.series.size():
  var row: Dictionary = spec.series[s]; var color: Color = COLORS[s%COLORS.size()]
  _key(str(row.name),color,"series:"+str(s))
  var previous := Vector2.ZERO; var has_previous := false
  var prev_lower := Vector2.ZERO; var prev_upper := Vector2.ZERO
  for i: int in row.values.size():
   if row.values[i] == null: has_previous = false; continue
   var p: Vector2 = _at(area,i,row.values.size(),float(row.values[i]),bounds,centered,is_bump)
   var description: String = str(spec.labels[i])+" · "+str(row.name)+"\n"+_amount(row.values[i])
   if spec.type == "interval" or spec.type == "errorbar":
    var lower: Vector2 = _at(area,i,row.values.size(),float(row.lower[i]),bounds,true)
    var upper: Vector2 = _at(area,i,row.values.size(),float(row.upper[i]),bounds,true)
    description += L.text("\nГраницы: ")+_amount(row.lower[i])+" — "+_amount(row.upper[i])
    if spec.type == "interval" and has_previous:
     _fill(PackedVector2Array([prev_upper,upper,lower,prev_lower]),Color(color,0.18))
    if spec.type == "errorbar":
     draw_line(lower,upper,Color(color,0.7),1.6,true)
     draw_line(lower-Vector2(5,0),lower+Vector2(5,0),color,1.6,true)
     draw_line(upper-Vector2(5,0),upper+Vector2(5,0),color,1.6,true)
    prev_lower = lower; prev_upper = upper
   if row.get("kind","") == "bar":
    var baseline: Vector2 = _at(area,i,row.values.size(),0,bounds,true)
    var width: float = maxf(1,area.size.x/row.values.size()*0.7/maxi(1,bar_count))
    var rect := Rect2(p.x-area.size.x/row.values.size()*0.35+bar_index*width,minf(p.y,baseline.y),maxf(1,width-1),maxf(1,absf(p.y-baseline.y)))
    draw_style_box(Style.box(Color(color,0.65),3,Color.TRANSPARENT,0),rect)
    _entry(rect.grow(2),description,str(spec.labels[i]))
   else:
    if has_previous: draw_line(previous,p,color,2.3,true)
    draw_circle(p,3.6,color,true,-1,true)
    _entry(Rect2(p-Vector2(7,7),Vector2(14,14)),description,str(spec.labels[i]))
   previous = p; has_previous = true
  if row.get("kind","") == "bar": bar_index += 1
func _dumbbell() -> void:
 var left: float = clampf(size.x*0.3,84,240)
 var bounds: Vector2 = _bounds(spec.series)
 var top := 42.0; var heights: Array = []; var total := 0.0
 for label: String in spec.labels:
  var h: float = clampf(_height(label,left-22)+14,36,110); heights.append(h); total += h
 _grow_height(top+total+44)
 var area := Rect2(left,top,size.x-left-20,total)
 for s: int in 2: _key(str(spec.series[s].name),COLORS[s],"series:"+str(s))
 _scale_horizontal(Rect2(left,12,area.size.x,20),bounds)
 var y: float = top
 for i: int in spec.labels.size():
  var center_y: float = y+float(heights[i])/2
  _fit(str(spec.labels[i]),Rect2(10,y+7,left-22,float(heights[i])-14),Color("#c5d1e2"),HORIZONTAL_ALIGNMENT_LEFT)
  if i%2 == 0: draw_rect(Rect2(left,y,area.size.x,heights[i]),Color(1,1,1,0.018))
  var a: Variant = spec.series[0].values[i]; var b: Variant = spec.series[1].values[i]
  var ax: float = left+(float(a)-bounds.x)/(bounds.y-bounds.x)*area.size.x if a != null else left
  var bx: float = left+(float(b)-bounds.x)/(bounds.y-bounds.x)*area.size.x if b != null else left
  if a != null and b != null: draw_line(Vector2(ax,center_y),Vector2(bx,center_y),Color("#62758f"),3,true)
  for s: int in 2:
   var n: Variant = spec.series[s].values[i]
   if n != null: draw_circle(Vector2(ax if s == 0 else bx,center_y),5,COLORS[s],true,-1,true)
  _entry(Rect2(left-7,y,area.size.x+14,heights[i]),str(spec.labels[i])+"\n"+str(spec.series[0].name)+": "+(L.text("нет данных") if a == null else _amount(a))+"\n"+str(spec.series[1].name)+": "+(L.text("нет данных") if b == null else _amount(b)),str(spec.labels[i]))
  y += float(heights[i])
func _scale_horizontal(area: Rect2, bounds: Vector2) -> void:
 var ticks: int = 5 if area.size.x >= 400 else 3
 for i: int in ticks:
  var t: float = float(i)/(ticks-1)
  _fit(Chart.number(lerpf(bounds.x,bounds.y,t)),Rect2(clampf(area.position.x+t*area.size.x-28,area.position.x,area.end.x-56),area.position.y,56,22))
func _slope() -> void:
 var area: Rect2 = _area(); var bounds: Vector2 = _bounds(spec.series)
 _axes(area,bounds.x,bounds.y,0,1,[spec.series[0].name,spec.series[1].name])
 for i: int in spec.labels.size():
  var color: Color = COLORS[i%COLORS.size()]; var a: Variant = spec.series[0].values[i]; var b: Variant = spec.series[1].values[i]
  var key: String = _key(str(spec.labels[i]),color,"entity:"+str(i))
  var pa: Vector2 = _at(area,0,2,float(a),bounds,true) if a != null else Vector2.ZERO
  var pb: Vector2 = _at(area,1,2,float(b),bounds,true) if b != null else Vector2.ZERO
  if a != null and b != null: draw_line(pa,pb,Color(color,0.7),2,true)
  for s: int in 2:
   var value: Variant = a if s == 0 else b
   if value == null: continue
   var p: Vector2 = pa if s == 0 else pb
   draw_circle(p,4,color,true,-1,true)
   var rect := Rect2(p+Vector2(6 if s == 0 else -38,-8),Vector2(32,20))
   if not text_boxes.any(func(row: Dictionary): return row.rect.grow(2).intersects(rect)): _fit(key,rect,color)
   _entry(Rect2(p-Vector2(7,7),Vector2(14,14)),str(spec.labels[i])+" · "+str(spec.series[s].name)+"\n"+_amount(value),str(spec.labels[i]))
func _calendar() -> void:
 var first := 10000000; var last := -10000000; var lookup := {}; var low := INF; var high := -INF
 for row: Dictionary in spec.days:
  var day: int = Extended.date_day(row.date); first = mini(first,day); last = maxi(last,day); lookup[day] = row.value
  if row.value != null: low = minf(low,float(row.value)); high = maxf(high,float(row.value))
 if not is_finite(low): low = 0; high = 1
 var monday: int = first-posmod(first+3,7)
 var weeks: int = ceili(float(last-monday+1)/7)
 var columns: int = mini(weeks,maxi(7,int((size.x-46)/17)))
 var cell: float = minf(24,(size.x-46)/columns)
 var strips: int = ceili(float(weeks)/columns); var strip_h: float = cell*7+55
 _grow_height(strips*strip_h+45)
 var weekdays := [L.text("Пн"),L.text("Вт"),L.text("Ср"),L.text("Чт"),L.text("Пт"),L.text("Сб"),L.text("Вс")]
 for strip: int in strips:
  var top: float = 34+strip*strip_h
  var start: int = monday+strip*columns*7
  var start_date: Dictionary = Time.get_datetime_dict_from_unix_time(start*86400)
  _fit("%04d-%02d-%02d"%[start_date.year,start_date.month,start_date.day],Rect2(34,top-24,size.x-44,20),Color("#aabbd2"),HORIZONTAL_ALIGNMENT_LEFT)
  for d: int in 7:
   var weekday: String = weekdays[d]
   if Text.height(weekday,27,get_theme_default_font(),10) > cell: weekday = _key(weekday,Color("#8798af"),"weekday:"+str(d))
   if Text.height(weekday,27,get_theme_default_font(),10) <= cell:
    Text.draw_text(self,weekday,Rect2(3,top+d*cell,27,cell),Color("#8798af"),HORIZONTAL_ALIGNMENT_CENTER,10,text_boxes)
  for w: int in columns:
   for d: int in 7:
    var day: int = start+w*7+d
    if day < first or day > last: continue
    var value: Variant = lookup.get(day)
    var rect := Rect2(34+w*cell,top+d*cell,cell-3,cell-3)
    var color: Color = Color("#272e39") if value == null else _color(float(value),low,high)
    draw_style_box(Style.box(color,2,Color.TRANSPARENT,0),rect)
    var date: Dictionary = Time.get_datetime_dict_from_unix_time(day*86400)
    _entry(rect,"%04d-%02d-%02d"%[date.year,date.month,date.day]+"\n"+(L.text("Нет данных") if value == null else _amount(value)))
 _fit(L.text("Нет данных ≠ 0 · Пн → Вс · ")+Chart.number(low)+" … "+Chart.number(high),Rect2(10,size.y-28,size.x-20,20),Color("#8798af"),HORIZONTAL_ALIGNMENT_LEFT)

func _geographic() -> void:
 var available := Rect2(24,30,size.x-48,size.y-72)
 var ratio: float = float(spec.get("aspect",1.6))
 var width: float = minf(available.size.x,available.size.y*ratio)
 var height: float = width/ratio
 _map_rect = Rect2(available.get_center()-Vector2(width,height)/2,Vector2(width,height))
 for row: Dictionary in spec.get("regions",[]):
  for poly: Array in row.polygons:
   var polygon := PackedVector2Array()
   for coord: Array in poly: polygon.append(_project(coord))
   _fill(polygon,Color("#29374b")); draw_polyline(polygon+PackedVector2Array([polygon[0]]),Color("#52647e"),1,true)
   var box := Rect2(polygon[0],Vector2.ZERO)
   for point: Vector2 in polygon: box = box.expand(point)
   _hit(box,str(row.label)+(": "+_amount(row.value) if row.get("value") != null else ""),polygon)
   hits[-1].region = {"id":str(row.id),"label":str(row.label),"body":str(spec.get("body",""))}
 var nodes := {}; var maximum := 1.0
 for node: Dictionary in spec.nodes: nodes[node.id] = node; maximum = maxf(maximum,float(node.get("value",1)))
 var selected_nodes := {}
 if related_enabled:
  for id: String in (_pinned_node_ids if pinned >= 0 else _hover_node_ids): selected_nodes[id] = true
 var max_flow := 1.0
 for edge: Dictionary in spec.get("links",[]): max_flow = maxf(max_flow,float(edge.value))
 for edge: Dictionary in spec.get("links",[]):
  var a: Vector2 = _project(nodes[edge.source].point); var b: Vector2 = _project(nodes[edge.target].point)
  var direction: Vector2 = (b-a).normalized(); var side := Vector2(-direction.y,direction.x)
  var bend: Vector2 = (a+b)/2+side*minf(36,a.distance_to(b)*0.15)
  var path := PackedVector2Array()
  for step: int in 25:
   var t: float = float(step)/24; path.append(a*(1-t)*(1-t)+bend*2*(1-t)*t+b*t*t)
  var alpha: float = 0.72
  if not selected_nodes.is_empty() and not (selected_nodes.has(edge.source) or selected_nodes.has(edge.target)): alpha = 0.12
  var thickness: float = 1+6*sqrt(float(edge.value)/max_flow)
  var color := Color(COLORS[1],alpha)
  draw_polyline(path,color,thickness,true)
  var tip: Vector2 = path[22]; var toward: Vector2 = (path[22]-path[20]).normalized(); var normal := Vector2(-toward.y,toward.x)
  _fill(PackedVector2Array([tip,tip-toward*10+normal*5,tip-toward*10-normal*5]),color)
  # Hit polygon follows the actual curve rather than its broad bounding rectangle.
  var poly := PackedVector2Array(); var back := PackedVector2Array()
  for i: int in path.size():
   var dir: Vector2 = (path[mini(i+1,path.size()-1)]-path[maxi(0,i-1)]).normalized(); var orth := Vector2(-dir.y,dir.x)*maxf(5,thickness)
   poly.append(path[i]+orth); back.append(path[i]-orth)
  back.reverse(); poly.append_array(back)
  var box := Rect2(a,Vector2.ZERO)
  for point: Vector2 in path: box = box.expand(point)
  _hit(box.grow(8),str(nodes[edge.source].label)+" → "+str(nodes[edge.target].label)+"\n"+_amount(edge.value),poly)
  hits[-1].node_ids = [edge.source,edge.target]
 for i: int in spec.nodes.size():
  var node: Dictionary = spec.nodes[i]; var p: Vector2 = _project(node.point)
  var radius: float = 18*sqrt(float(node.get("value",1))/maximum)
  var color: Color = COLORS[i%COLORS.size()]
  if radius > 0:
   draw_circle(p,radius+3,Color(color,0.08),true,-1,true); draw_circle(p,radius,Color(color,0.65),true,-1,true)
  draw_arc(p,maxf(3,radius),0,TAU,64,color,1.2,true)
  var code: String = _key(str(node.label)+(" · "+_amount(node.value) if node.has("value") else ""),color,node.id)
  var box := Rect2(p+Vector2(-20,radius+3),Vector2(40,20))
  if Rect2(Vector2.ZERO,size).encloses(box) and not text_boxes.any(func(row: Dictionary): return row.rect.grow(3).intersects(box)): _fit(code,box,color)
  _entry(Rect2(p-Vector2.ONE*maxf(4,radius),Vector2.ONE*maxf(8,radius*2)),str(node.label)+("\n"+_amount(node.value) if node.has("value") else ""),str(node.label))
  hits[-1].center = p; hits[-1].radius = maxf(4,radius); hits[-1].node_ids = [node.id]
  if node.has("region_id"): hits[-1].region = {"id":node.region_id,"label":node.label,"body":str(spec.get("body",""))}
 _fit(L.text("Площадь символа — значение") if spec.type == "symbol_map" else L.text("Стрелка — направление · толщина — объём потока"),Rect2(10,size.y-28,size.x-20,24),Color("#8fa1ba"),HORIZONTAL_ALIGNMENT_LEFT)
func _project(point: Array) -> Vector2: return _map_rect.position+Vector2(float(point[0]),float(point[1]))*_map_rect.size
func _hierarchy() -> void:
 var nodes := {}; var children := {}; var root_id := ""
 for row: Dictionary in spec.nodes: nodes[row.id] = row; children[row.id] = []
 for row: Dictionary in spec.nodes:
  if row.has("parent"): children[row.parent].append(row.id)
  else: root_id = row.id
 var totals := {}; var depths := {}; var leaves := []; var maximum := 0
 _tree_totals(root_id,0,nodes,children,totals,depths,leaves)
 for depth: int in depths.values(): maximum = maxi(maximum,depth)
 if spec.type == "icicle":
  _grow_height(maxf(340,(maximum+1)*56+40))
  _icicle_row(root_id,18,size.x-36,0,nodes,children,totals,0)
 else:
  _grow_height(maxf(360,leaves.size()*34+48))
  var ys := {}; var positions := {}; var available: float = size.y-56
  for i: int in leaves.size(): ys[leaves[i]] = 28+(i+0.5)/leaves.size()*available
  _tree_y(root_id,children,ys)
  var column: float = (size.x-48)/maxi(1,maximum)
  for id: String in nodes: positions[id] = Vector2(24+depths[id]*column,float(ys[id]))
  for row: Dictionary in spec.nodes:
   if not row.has("parent"): continue
   var a: Vector2 = positions[row.parent]; var b: Vector2 = positions[row.id]
   draw_polyline(PackedVector2Array([a,Vector2((a.x+b.x)/2,a.y),Vector2((a.x+b.x)/2,b.y),b]),Color("#526983"),1.5,true)
  for i: int in spec.nodes.size():
   var row: Dictionary = spec.nodes[i]; var p: Vector2 = positions[row.id]; var color: Color = COLORS[int(depths[row.id])%COLORS.size()]
   draw_circle(p,5,color,true,-1,true)
   var label_width: float = minf(180,maxf(36,column-16))
   var label_box := Rect2(clampf(p.x-label_width/2,8,size.x-label_width-8),p.y-25,label_width,22)
   var show_name: bool = _height(str(row.label),label_width) <= 22 and not text_boxes.any(func(entry: Dictionary): return entry.rect.grow(1).intersects(label_box))
   if show_name: _fit(str(row.label),label_box,color)
   else:
    var key: String = _key(str(row.label)+" · "+_amount(totals[row.id]),color,row.id)
    var box := Rect2(clampf(p.x-18,8,size.x-44),p.y-24,36,20)
    if not text_boxes.any(func(entry: Dictionary): return entry.rect.grow(1).intersects(box)): _fit(key,box,color)
   _entry(Rect2(p-Vector2(9,9),Vector2(18,18)),str(row.label)+"\n"+_amount(totals[row.id]),str(row.label))
func _tree_totals(id: String, level: int, nodes: Dictionary, children: Dictionary, totals: Dictionary, depths: Dictionary, leaves: Array) -> float:
 var total: float = float(nodes[id].get("value",0)); depths[id] = level
 if children[id].is_empty(): leaves.append(id)
 for child: String in children[id]: total += _tree_totals(child,level+1,nodes,children,totals,depths,leaves)
 totals[id] = total; return total
func _tree_y(id: String, children: Dictionary, ys: Dictionary) -> float:
 if ys.has(id): return ys[id]
 var total := 0.0
 for child: String in children[id]: total += _tree_y(child,children,ys)
 ys[id] = total/maxi(1,children[id].size()); return ys[id]
func _icicle_row(id: String, x: float, width: float, level: int, nodes: Dictionary, children: Dictionary, totals: Dictionary, color_index: int) -> void:
 if width <= 0:
  _key(str(nodes[id].label)+" · "+_amount(totals[id]),COLORS[color_index%COLORS.size()],id); return
 var rect := Rect2(x,18+level*56,maxf(0,width-2),50)
 var color: Color = COLORS[color_index%COLORS.size()].lightened(minf(0.2,level*0.035))
 draw_style_box(Style.box(Color(color,0.48),3,Color.TRANSPARENT,0),rect)
 var key: String = _key(str(nodes[id].label)+" · "+_amount(totals[id]),color,id)
 _fit(str(nodes[id].label) if width >= 100 else key,Rect2(rect.position+Vector2(4,5),Vector2(maxf(1,width-10),40)),Color("#e0e8f5"))
 _entry(rect,str(nodes[id].label)+"\n"+_amount(totals[id]),str(nodes[id].label))
 var cursor: float = x
 for i: int in children[id].size():
  var child: String = children[id][i]; var span: float = width*float(totals[child])/maxf(1e-15,float(totals[id]))
  _icicle_row(child,cursor,span,level+1,nodes,children,totals,i if level == 0 else color_index); cursor += span
func _parallel() -> void:
 var count: int = spec.dimensions.size(); var area := Rect2(30,82,size.x-60,size.y-148)
 var bounds: Array = []
 for i: int in count:
  var dim: Dictionary = spec.dimensions[i]
  var bound: Vector2 = _dimension_bounds(i)
  var low: float = bound.x; var high: float = bound.y
  bounds.append(bound)
  var x: float = area.position.x+float(i)/(count-1)*area.size.x
  draw_line(Vector2(x,area.position.y),Vector2(x,area.end.y),Color("#52647e"),1.2,true)
  var slot: float = minf(110,(size.x-20)/count-4)
  var label: String = str(dim.label)+(" · "+str(dim.unit) if dim.get("unit","") != "" else "")
  var shown: String = label if slot > 70 and _height(label,slot) <= 40 else _key(label,COLORS[0],"dim:"+str(i))
  _fit(shown,Rect2(clampf(x-slot/2,5,size.x-slot-5),12,slot,40))
  _fit(Chart.number(high),Rect2(clampf(x-slot/2,5,size.x-slot-5),56,slot,20))
  _fit(Chart.number(low),Rect2(clampf(x-slot/2,5,size.x-slot-5),area.end.y+8,slot,20))
 for s: int in spec.rows.size():
  var row: Dictionary = spec.rows[s]; var color: Color = COLORS[s%COLORS.size()]
  _key(str(row.label),color,"row:"+str(s))
  var previous := Vector2.ZERO; var has_previous := false
  for i: int in count:
   var value: Variant = row.values[i]
   if value == null: has_previous = false; continue
   var p: Vector2 = _at(area,i,count,float(value),bounds[i])
   var alpha: float = 0.65 if spec.rows.size() < 15 else 0.25
   if _linked != "" and row.label != _linked: alpha = 0.06
   if has_previous: draw_line(previous,p,Color(color,alpha),1.6,true)
   draw_circle(p,2.5,Color(color,0.9),true,-1,true)
   _entry(Rect2(p-Vector2(5,5),Vector2(10,10)),str(row.label)+"\n"+str(spec.dimensions[i].label)+": "+Chart.number(value)+" "+str(spec.dimensions[i].get("unit","")),str(row.label))
   previous = p; has_previous = true
func _multiples() -> void:
 var columns: int = 2 if size.x >= 620 else 1
 var row_count: int = ceili(float(spec.panels.size())/columns)
 var panel_height := 216.0; var width: float = (size.x-24)/columns
 _grow_height(row_count*panel_height+16)
 var bounds: Vector2 = _bounds(spec.panels,["values"],spec.kind == "bar")
 for s: int in spec.panels.size():
  var row: Dictionary = spec.panels[s]; var offset := Vector2(12+(s%columns)*width,8+floorf(float(s)/columns)*panel_height)
  draw_style_box(Style.box(Color("#202731"),5,Color.TRANSPARENT,0),Rect2(offset,Vector2(width-10,panel_height-10)))
  _fit(str(row.title),Rect2(offset+Vector2(10,8),Vector2(width-30,36)),Color("#d7e3f5"),HORIZONTAL_ALIGNMENT_LEFT)
  var area := Rect2(offset+Vector2(48,54),Vector2(width-74,118))
  if row.values.all(func(n: Variant): return n == null): _fit(L.text("Нет данных"),Rect2(area.position+Vector2(0,42),Vector2(area.size.x,24)),Color("#8395ae"))
  for tick: int in 3:
   var y: float = area.position.y+float(tick)/2*area.size.y
   draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(1,1,1,0.07),1,true)
   _fit(Chart.number(lerpf(bounds.y,bounds.x,float(tick)/2)),Rect2(offset.x+3,y-8,39,20),Color("#8395ae"),HORIZONTAL_ALIGNMENT_RIGHT)
  var previous := Vector2.ZERO; var has_previous := false
  for i: int in row.values.size():
   if row.values[i] == null: has_previous = false; continue
   var p: Vector2 = _at(area,i,row.values.size(),float(row.values[i]),bounds,spec.kind == "bar")
   if spec.kind == "bar":
    var base: Vector2 = _at(area,i,row.values.size(),0,bounds,true)
    var bar_width: float = maxf(1,area.size.x/row.values.size()*0.65)
    var rect := Rect2(p.x-bar_width/2,minf(base.y,p.y),bar_width,maxf(1,absf(base.y-p.y)))
    draw_rect(rect,Color(COLORS[s%COLORS.size()],0.75)); _entry(rect.grow(2),str(row.title)+" · "+str(spec.labels[i])+"\n"+_amount(row.values[i]),str(spec.labels[i]))
   else:
    if has_previous: draw_line(previous,p,COLORS[s%COLORS.size()],2,true)
    draw_circle(p,3,COLORS[s%COLORS.size()],true,-1,true)
    _entry(Rect2(p-Vector2(6,6),Vector2(12,12)),str(row.title)+" · "+str(spec.labels[i])+"\n"+_amount(row.values[i]),str(spec.labels[i]))
   previous = p; has_previous = true
  for index: int in ([0,row.values.size()-1] if row.values.size() > 1 else [0]):
   var label_width: float = area.size.x/2-4
   _fit(str(spec.labels[index]),Rect2(area.position.x+(label_width+8 if index > 0 else 0),area.end.y+8,label_width,28),Color("#8fa1ba"))

func _hit_index(at: Vector2) -> int:
 for index: int in range(hits.size()-1,-1,-1):
  var hit: Dictionary = hits[index]
  if not hit.rect.has_point(at): continue
  if hit.has("center") and at.distance_to(hit.center) > hit.radius: continue
  if hit.has("polygon") and not Geometry2D.is_point_in_polygon(at,hit.polygon): continue
  return index
 return -1

func _dimension_bounds(index: int) -> Vector2:
 var dim: Dictionary = spec.dimensions[index]; var low := INF; var high := -INF
 for row: Dictionary in spec.rows:
  if row.values[index] != null: low = minf(low,float(row.values[index])); high = maxf(high,float(row.values[index]))
 if not is_finite(low): low = 0; high = 1
 low = float(dim.get("min",low)); high = float(dim.get("max",high))
 if low >= high:
  var span: float = maxf(1,maxf(absf(low),absf(high))*0.01)
  if dim.has("min") and not dim.has("max"): high = low+span
  elif dim.has("max") and not dim.has("min"): low = high-span
  else: low -= span/2; high += span/2
 return Vector2(low,high)
