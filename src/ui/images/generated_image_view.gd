extends VBoxContainer
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Resolves only a retained artifact ID. Model-provided paths/URLs are never opened.
var _picture: TextureRect
func setup(service: Node, descriptor: Dictionary) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new(); title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = L.text("Созданное изображение"); add_child(title)
	var resolved: Dictionary = service.resolve_image(descriptor) if is_instance_valid(service) and service.has_method("resolve_image") else {"ok":false}
	if not resolved.get("ok",false):
		var missing := Label.new(); missing.text = L.text("Сохранённое изображение недоступно."); missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(missing); return
	_picture = TextureRect.new(); _picture.texture = resolved.texture
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(_picture)
	resized.connect(_resize_image); _resize_image()
	var caption := Label.new(); L.bind(caption,"text",[{"format":"Создано генератором игры · %d × %d","args":[resolved.descriptor.width,resolved.descriptor.height]}])
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(caption)

func _resize_image() -> void:
	if is_instance_valid(_picture) and _picture.texture != null:
		_picture.custom_minimum_size.y = clampf(maxf(160,size.x)*_picture.texture.get_height()/float(_picture.texture.get_width()),120,720)
