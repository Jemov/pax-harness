extends CanvasLayer
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
static var _views: Array=[]
static func open_views() -> Array:
	_views=_views.filter(func(ref_: WeakRef):return is_instance_valid(ref_.get_ref()))
	return _views.map(func(ref_: WeakRef):return ref_.get_ref())
var image: TextureRect
var _previous: WeakRef
static func open(parent: Node, texture: Texture2D, caption: String, caption_parts: Array=[]) -> CanvasLayer:
	var viewer=load("res://mods/pax_harness/src/ui/images/image_viewer.gd").new()
	parent.get_viewport().add_child(viewer);_views.append(weakref(viewer));viewer.setup(texture,caption,caption_parts);return viewer
func setup(texture: Texture2D, caption: String, caption_parts: Array=[]) -> void:
	name="HarnessImageViewer";layer=2000;process_mode=Node.PROCESS_MODE_ALWAYS
	var previous: Control=get_viewport().gui_get_focus_owner()
	if previous!=null: _previous=weakref(previous)
	var back:=ColorRect.new();back.color=Color(0.025,0.03,0.04,0.98);back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(back)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+edge,20)
	back.add_child(margin)
	var body:=VBoxContainer.new();margin.add_child(body)
	var bar:=HBoxContainer.new();body.add_child(bar)
	var title:=Label.new()
	if caption_parts.is_empty():title.text=caption;title.set_meta("mod_user_text",true)
	else:L.bind(title,"text",caption_parts)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;bar.add_child(title)
	var close:=Button.new();close.name="CloseImageViewer";close.text="✕";close.tooltip_text=L.text("Закрыть изображение");close.pressed.connect(dismiss);bar.add_child(close)
	image=TextureRect.new();image.name="FullImage";image.texture=texture;image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.size_flags_vertical=Control.SIZE_EXPAND_FILL;image.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(image)
	var hint:=Label.new();hint.text=L.text("Изображение целиком · Esc — закрыть");body.add_child(hint);close.grab_focus()
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: get_viewport().set_input_as_handled();dismiss()
func dismiss() -> void:
	var previous: Variant=_previous.get_ref() if _previous!=null else null
	if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	queue_free()
