extends PanelContainer
## Frozen headers, a bounded page of contiguous cells and lossless CSV text.
const Style = preload("res://mods/pax_harness/chat_style.gd")
const Markdown = preload("res://mods/pax_harness/chat_markdown.gd")
const Table = preload("res://mods/pax_harness/table_spec.gd")
var grid: GridContainer
var rules: Control
var header_grid: GridContainer
var data_scroll: ScrollContainer
var horizontal_scroll: ScrollContainer
var filter_input: LineEdit
var counter: Label
var previous_button: Button
var next_button: Button
var csv_text: TextEdit
var spec: Dictionary
var order: Array = []
var page := 0
var sort_column := -1
var sort_descending := false
var _ui: Node
var _widths: Array = []
var _body_rules: Control
var _header_rules: Control
var _csv_panel: VBoxContainer

class Rules extends Control:
	var grid: GridContainer
	func _draw() -> void:
		if grid == null or grid.get_child_count() == 0: return
		var color := Color("#373a40")
		for column: int in range(1,grid.columns):
			var x: float = grid.get_child(column).position.x
			draw_line(Vector2(x,0),Vector2(x,size.y),color,1.0,true)
		for row_start: int in range(grid.columns,grid.get_child_count(),grid.columns):
			var y: float = grid.get_child(row_start).position.y
			draw_line(Vector2(0,y),Vector2(size.x,y),color,1.0,true)
		draw_rect(Rect2(Vector2(0.5,0.5),size-Vector2.ONE),color,false,1.0,true)

func setup(ui: Node, block: Dictionary) -> void:
	_ui = ui; spec = Table.normalize(block)
	name = "MarkdownTable"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel",Style.box(Color.TRANSPARENT,0,Color.TRANSPARENT,0))
	var layout := VBoxContainer.new(); layout.add_theme_constant_override("separation",8); add_child(layout)
	if not spec.title.is_empty(): layout.add_child(Style.label(spec.title,16))
	if spec.extra_columns > 0:
		var warning := Style.label("В строках есть дополнительные значения. Добавлено столбцов: "+str(spec.extra_columns)+" — все данные сохранены.",12,Color("#e6bd7a"))
		warning.name = "TableWarning"; layout.add_child(warning)
	var tools := HFlowContainer.new(); tools.add_theme_constant_override("h_separation",8); layout.add_child(tools)
	filter_input = LineEdit.new(); filter_input.name = "TableFilter"; filter_input.placeholder_text = "Поиск по таблице"; filter_input.clear_button_enabled = true; filter_input.custom_minimum_size.x = 165
	filter_input.text_changed.connect(func(_text: String): page = 0; _refresh())
	tools.add_child(filter_input)
	var csv_button: Button = _button("CSV",_show_csv); csv_button.name = "TableCSV"; csv_button.tooltip_text = "Показать CSV-текст всех отфильтрованных строк"; tools.add_child(csv_button)
	var reset_button: Button = _button("Сброс",_reset); reset_button.tooltip_text = "Сбросить поиск и сортировку"; tools.add_child(reset_button)
	horizontal_scroll = ScrollContainer.new(); horizontal_scroll.name = "TableHorizontalScroll"; horizontal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO; horizontal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(horizontal_scroll)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation",0); horizontal_scroll.add_child(content)
	_widths = _column_widths()
	var total := 16.0
	for width: float in _widths: total += width
	content.custom_minimum_size.x = total
	var header_row := HBoxContainer.new(); header_row.add_theme_constant_override("separation",0); content.add_child(header_row)
	var header_panel := PanelContainer.new(); header_panel.add_theme_stylebox_override("panel",Style.box(Color.TRANSPARENT,0,Color.TRANSPARENT,0)); header_row.add_child(header_panel)
	header_grid = _new_grid(); header_panel.add_child(header_grid)
	_header_rules = _new_rules(header_panel,header_grid)
	var gutter := Control.new(); gutter.custom_minimum_size.x = 16; header_row.add_child(gutter)
	data_scroll = ScrollContainer.new(); data_scroll.name = "TableDataScroll"; data_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; data_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	content.add_child(data_scroll)
	var body := PanelContainer.new(); body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; body.add_theme_stylebox_override("panel",Style.box(Color.TRANSPARENT,0,Color.TRANSPARENT,0)); data_scroll.add_child(body)
	grid = _new_grid(); body.add_child(grid)
	_body_rules = _new_rules(body,grid)
	var pager := HFlowContainer.new(); pager.add_theme_constant_override("h_separation",8); layout.add_child(pager)
	previous_button = _button("←",func(): page -= 1; _refresh()); previous_button.tooltip_text = "Предыдущие 50 строк"; pager.add_child(previous_button)
	counter = Style.label("",12,Color("#9ca7b6")); counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	counter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER; pager.add_child(counter)
	next_button = _button("→",func(): page += 1; _refresh()); next_button.tooltip_text = "Следующие 50 строк"; pager.add_child(next_button)
	if not spec.source.is_empty(): layout.add_child(Style.label("Источник: "+spec.source,12,Color("#9ca7b6")))
	_csv_panel = VBoxContainer.new(); _csv_panel.name = "TableCSVPanel"; _csv_panel.hide(); layout.add_child(_csv_panel)
	_csv_panel.add_child(Style.label("CSV: все строки текущего результата поиска, с учётом сортировки",12))
	csv_text = TextEdit.new(); csv_text.name = "TableCSVText"; csv_text.editable = false; csv_text.custom_minimum_size.y = 180; csv_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; _csv_panel.add_child(csv_text)
	var csv_tools := HFlowContainer.new(); _csv_panel.add_child(csv_tools)
	csv_tools.add_child(_button("Копировать CSV",func(): DisplayServer.clipboard_set(csv_export())))
	csv_tools.add_child(_button("Закрыть",func(): _csv_panel.hide()))
	# Kept as the outer overlay API; actual shared grid lines live inside each scroll region.
	rules = Control.new(); rules.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(rules)
	_refresh()

func _button(text: String, action: Callable) -> Button:
	var button := Button.new(); button.text = text; button.custom_minimum_size.y = 32; button.size_flags_vertical = Control.SIZE_SHRINK_CENTER; button.pressed.connect(action)
	return button

func _new_grid() -> GridContainer:
	var result := GridContainer.new(); result.columns = spec.headers.size()
	result.add_theme_constant_override("h_separation",0); result.add_theme_constant_override("v_separation",0)
	return result

func _new_rules(parent: Control, target: GridContainer) -> Control:
	var result := Rules.new(); result.grid = target; result.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(result)
	target.sort_children.connect(result.queue_redraw.call_deferred); result.resized.connect(result.queue_redraw)
	return result

func _column_widths() -> Array:
	var result: Array = []
	for column: int in spec.headers.size():
		var longest: int = str(spec.headers[column]).length()+3
		# Width sampling is bounded; every row remains accessible through paging.
		for index: int in mini(100,spec.rows.size()): longest = maxi(longest,mini(44,Markdown.plain_inline(str(spec.rows[index][column])).length()))
		result.append(ceilf(clampf(longest*7.3+24,120,340)))
	return result

func _cell(value: Variant, column: int, header: bool = false) -> PanelContainer:
	var cell := PanelContainer.new(); cell.custom_minimum_size.x = _widths[column]
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = Style.box(Color("#272a30") if header else Color("#1d1f23"),0,Color.TRANSPARENT,10)
	style.content_margin_top = 8; style.content_margin_bottom = 8; cell.add_theme_stylebox_override("panel",style)
	var text: String = "" if value == null else str(value)
	var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if spec.alignments[column] == "right" else HORIZONTAL_ALIGNMENT_CENTER if spec.alignments[column] == "center" else HORIZONTAL_ALIGNMENT_LEFT
	if header:
		var button := Button.new(); button.text = Markdown.plain_inline(text)+( (" ▼" if sort_descending else " ▲") if sort_column == column else "")
		button.alignment = alignment; button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; button.custom_minimum_size.x = _widths[column]-20
		button.tooltip_text = Markdown.plain_inline(text)+"\nСортировать по столбцу"; button.pressed.connect(_sort.bind(column)); Style.link(button); cell.add_child(button)
	elif text.contains("**") or text.contains("`") or text.contains("](") or text.contains("~~"):
		var rich := RichTextLabel.new(); rich.bbcode_enabled = true; rich.fit_content = true; rich.scroll_active = false; rich.selection_enabled = true
		rich.custom_minimum_size.x = _widths[column]-20; rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rich.text = ("[right]" if alignment == HORIZONTAL_ALIGNMENT_RIGHT else "[center]" if alignment == HORIZONTAL_ALIGNMENT_CENTER else "[left]")+Markdown.inline(text)
		rich.add_theme_font_size_override("normal_font_size",14); cell.add_child(rich)
	else:
		var label := Style.label(text,14,Color("#d2d6df")); label.vertical_alignment = VERTICAL_ALIGNMENT_TOP; label.horizontal_alignment = alignment
		label.size_flags_vertical = Control.SIZE_FILL; label.custom_minimum_size.x = _widths[column]-20; label.tooltip_text = text; cell.add_child(label)
	return cell

func _sort(column: int) -> void:
	sort_descending = not sort_descending if sort_column == column else false
	sort_column = column; page = 0; _refresh()

func _reset() -> void:
	filter_input.text = ""; sort_column = -1; sort_descending = false; page = 0; _refresh()

func _refresh() -> void:
	order = Table.indices(spec,filter_input.text,sort_column,sort_descending)
	page = clampi(page,0,maxi(0,ceili(float(order.size())/Table.PAGE_SIZE)-1))
	for parent: GridContainer in [header_grid,grid]:
		for child: Node in parent.get_children(): parent.remove_child(child); child.queue_free()
	for column: int in spec.headers.size(): header_grid.add_child(_cell(spec.headers[column],column,true))
	var first: int = page*Table.PAGE_SIZE; var last: int = mini(first+Table.PAGE_SIZE,order.size())
	for index: int in range(first,last):
		for column: int in spec.headers.size(): grid.add_child(_cell(spec.rows[order[index]][column],column))
	counter.text = ("0 строк" if order.is_empty() else str(first+1)+"–"+str(last)+" из "+str(order.size()))+(" · всего "+str(spec.rows.size()) if order.size() != spec.rows.size() else "")
	previous_button.disabled = page <= 0; next_button.disabled = last >= order.size()
	data_scroll.scroll_vertical = 0
	data_scroll.custom_minimum_size.y = minf(420,maxf(42,(last-first)*39.0))
	# Wrapped descriptions grow rows; give the scroll region its final bounded height.
	_resize_body.call_deferred()
	if _csv_panel.visible: csv_text.text = csv_export()

func _resize_body() -> void:
	data_scroll.custom_minimum_size.y = minf(420,maxf(42,grid.get_combined_minimum_size().y))
	_body_rules.queue_redraw(); _header_rules.queue_redraw()

func csv_export() -> String: return Table.csv(spec,order)

func _show_csv() -> void:
	csv_text.text = csv_export(); _csv_panel.show()
