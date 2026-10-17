extends Button
func _make_custom_tooltip(for_text: String) -> Object:
	return preload("res://mods/pax_harness/chat_tooltip.gd").make(self,for_text)
