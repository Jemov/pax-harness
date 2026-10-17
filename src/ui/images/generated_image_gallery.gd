extends VBoxContainer
const View = preload("res://mods/pax_harness/src/ui/images/generated_image_view.gd")
var _cards: Dictionary = {}
func update_images(service: Node, descriptors: Array) -> void:
	var keep: Dictionary = {}
	for descriptor: Dictionary in descriptors:
		var id: String = str(descriptor.get("id",""))
		if id.is_empty() or keep.has(id): continue
		keep[id] = true
		if not is_instance_valid(_cards.get(id)):
			var card := View.new(); add_child(card); card.setup(service,descriptor); _cards[id] = card
		move_child(_cards[id],keep.size()-1)
	for id: String in _cards.keys():
		if keep.has(id): continue
		var old: Node = _cards[id]
		if is_instance_valid(old): remove_child(old); old.queue_free()
		_cards.erase(id)
	visible = not keep.is_empty()
