extends VBoxContainer
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Filters = preload("res://mods/pax_harness/src/visualization/controls/chart_filters.gd")
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
const Icons = preload("res://mods/pax_harness/src/ui/components/chat_icons.gd")
var owner_view: Control
var original: Dictionary
var viewport: ScrollContainer
var query: LineEdit
var panel: VBoxContainer
var zoom_label: Button
var note: Label
var series_checks: Array = []
var minimum: SpinBox
var bins: SpinBox
var _filter_button: Button
var related_enabled := true
var animation_enabled := true
var query_timer: Timer
func style_button(value: Button, wide: bool = false) -> void:
	value.custom_minimum_size = Vector2(32,30)
	for state: String in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
		var color: Color = Color("#2b3442") if state == "hover" else Color("#263b56") if state in ["pressed","hover_pressed"] else Color.TRANSPARENT
		value.add_theme_stylebox_override(state,Style.box(color,5,Color("#557bab") if state == "focus" else Color.TRANSPARENT,8 if wide else 4))
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: value.add_theme_color_override(state,Color("#c0ccdd"))
	value.add_theme_font_size_override("font_size",12)
	value.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
func button(text: String, action: Callable) -> Button:
	var value := preload("res://mods/pax_harness/src/ui/components/chat_button.gd").new(); value.text = text; value.pressed.connect(action); style_button(value,text != "")
	return value
func icon_button(kind: String, tip: String, action: Callable) -> Button:
	var value: Button = button("",action); value.icon = Icons.make(kind,Color("#a8b9d0"),16); value.tooltip_text = tip
	value.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return value
func setup(view: Control, data: Dictionary) -> void:
	owner_view = view; original = data
	name = "ChartControls"; add_theme_constant_override("separation",6)
	var bar := HFlowContainer.new(); bar.add_theme_constant_override("h_separation",6); add_child(bar)
	var zoom_group := PanelContainer.new(); zoom_group.add_theme_stylebox_override("panel",Style.box(Color("#202630"),6,Color("#303946"),0)); bar.add_child(zoom_group)
	var zoom_row := HBoxContainer.new(); zoom_row.add_theme_constant_override("separation",0); zoom_group.add_child(zoom_row)
	zoom_row.add_child(icon_button("minus",L.text("Уменьшить масштаб"),func(): if viewport != null: viewport.change_zoom(viewport.target_zoom-0.25)))
	zoom_label = button("100%",func(): if viewport != null: viewport.change_zoom(1)); zoom_label.custom_minimum_size.x = 56; zoom_label.tooltip_text = L.text("Вернуть масштаб 100%"); zoom_row.add_child(zoom_label)
	zoom_row.add_child(icon_button("plus",L.text("Увеличить масштаб"),func(): if viewport != null: viewport.change_zoom(viewport.target_zoom+0.25)))
	_filter_button = button(L.text("Фильтр"),func(): panel.visible = not panel.visible); _filter_button.icon = Icons.make("filter",Color("#a8b9d0"),15); _filter_button.tooltip_text = L.text("Найти категории и настроить отображение"); bar.add_child(_filter_button)
	if original.type in ["sankey","network","gantt","sunburst"]:
		var focus: Button = icon_button("link",L.text("Подсветка связанных путей. Нажмите узел для закрепления; Esc — снять выбор."),func(): pass); focus.toggle_mode = true; focus.button_pressed = true
		focus.toggled.connect(func(on: bool): related_enabled = on; _update_options()); bar.add_child(focus)
	bar.add_child(icon_button("play",L.text("Повторить анимацию"),func(): owner_view.replay_animation()))
	var menu := MenuButton.new(); style_button(menu); menu.icon = Icons.make("more",Color("#a8b9d0"),16); menu.tooltip_text = L.text("Настройки графика"); bar.add_child(menu)
	var popup: PopupMenu = menu.get_popup(); popup.add_check_item(L.text("Анимации"),1); popup.set_item_checked(0,true); popup.add_separator(); popup.add_item(L.text("Сбросить фильтры и масштаб"),2); popup.add_item(L.text("Данные и источник…"),3)
	popup.add_theme_stylebox_override("panel",Style.box(Color("#202630"),6,Color("#354153"),8)); popup.add_theme_stylebox_override("hover",Style.box(Color("#2b394c"),4,Color.TRANSPARENT,6))
	popup.id_pressed.connect(func(id: int):
		if id == 1: animation_enabled = not animation_enabled; popup.set_item_checked(0,animation_enabled); _update_options()
		elif id == 2: reset()
		elif id == 3: owner_view.show_data())
	bar.tooltip_text = L.text("Ctrl + колесо — масштаб 100–400%. Средняя кнопка мыши — перемещение увеличенного графика.")
	if original.type == "sunburst": bar.add_child(icon_button("root",L.text("Вернуться ко всей иерархии"),func(): if is_instance_valid(owner_view._plot): owner_view._plot.reset_drill()))
	panel = VBoxContainer.new(); panel.visible = false; add_child(panel)
	query = LineEdit.new(); query.placeholder_text = L.text("Найти категорию, задачу или узел…"); query.max_length = 160; panel.add_child(query)
	query_timer = Timer.new(); query_timer.one_shot = true; query_timer.wait_time = 0.18; add_child(query_timer); query_timer.timeout.connect(_apply)
	query.text_changed.connect(func(_s: String): query_timer.start())
	if original.type in ["histogram","waterfall"]:
		query.editable = false; query.placeholder_text = L.text("Все исходные статьи сохранены") if original.type == "waterfall" else L.text("Распределение исходной выборки")
		query.tooltip_text = L.text("Исключение отдельных статей изменило бы накопленный итог.") if original.type == "waterfall" else L.text("Для гистограммы можно изменить число интервалов.")
	var names: Array = []
	for row: Dictionary in original.get("series",original.get("groups",[])): names.append(row.name)
	if original.type == "gantt": names = ["planned","active","blocked","complete"]
	if names.size() > 1:
		for title: String in names:
			var row := HBoxContainer.new(); var check := CheckBox.new(); check.button_pressed = true; check.set_meta("key",title); row.add_child(check)
			var label := Label.new(); label.text = {"planned":L.text("Запланировано"),"active":L.text("В работе"),"blocked":L.text("Заблокировано"),"complete":L.text("Завершено")}.get(title,title); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
			panel.add_child(row); series_checks.append(check); check.toggled.connect(func(_on: bool): _apply())
	if original.type in ["network","sankey","flow_map"]:
		minimum = SpinBox.new(); minimum.min_value = 0; minimum.max_value = 1.0e15; minimum.step = 0.1; minimum.prefix = L.text("Мин. поток: "); minimum.tooltip_text = L.text("Скрыть связи с меньшим весом; исходные значения сохраняются."); panel.add_child(minimum); minimum.value_changed.connect(func(_v: float): _apply())
	if original.type == "histogram":
		bins = SpinBox.new(); bins.min_value = 2; bins.max_value = 40; bins.step = 1; bins.value = original.get("bins",10); bins.prefix = L.text("Интервалы: "); panel.add_child(bins); bins.value_changed.connect(func(_v: float): _apply())
	note = Label.new(); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.add_theme_font_size_override("font_size",12); note.add_theme_color_override("font_color",Color("#a7b6ce")); note.visible = false; add_child(note)
func bind(canvas_viewport: ScrollContainer) -> void:
	viewport = canvas_viewport
	viewport.zoom_changed.connect(func(value: float): zoom_label.text = str(roundi(value*100))+"%")
	_update_options()
func _update_options() -> void:
	if viewport != null:
		viewport.set_animation_enabled(animation_enabled)
		if viewport.plot.has_method("set_chart_options"): viewport.plot.set_chart_options(related_enabled,animation_enabled)
	if not animation_enabled: owner_view.stop_animation()
func _apply() -> void:
	var hidden: Array = []
	for check: CheckBox in series_checks:
		if not check.button_pressed: hidden.append(check.get_meta("key"))
	var filtered: Dictionary = Filters.apply(original,query.text,hidden,minimum.value if minimum != null else 0)
	if bins != null and not filtered.is_empty(): filtered.bins = int(bins.value)
	note.visible = query.text != "" or not hidden.is_empty() or (minimum != null and minimum.value > 0)
	L.bind(note,"text",["Показана часть данных; исходные значения сохранены."," Доли рассчитаны по видимым категориям." if original.type in ["pie","donut","treemap","sunburst","icicle"] else ""])
	owner_view.apply_display(filtered)
func reset() -> void:
	query.set_block_signals(true); query.text = ""; query.set_block_signals(false)
	for check: CheckBox in series_checks: check.set_pressed_no_signal(true)
	if minimum != null: minimum.set_value_no_signal(0)
	if bins != null: bins.set_value_no_signal(int(original.get("bins",10)))
	_apply()
	if viewport != null: viewport.change_zoom(1)
