extends VBoxContainer
const Card=preload("res://mods/pax_harness/src/creation/creation_card.gd")
var _ids: Array=[]
func update_message(ui: Node, message: Dictionary) -> void:
	var service: Node=ui.owner_mod.get("_creations")
	var ids: Array=[]
	if is_instance_valid(service):
		var candidates: Dictionary={}
		for event: Dictionary in message.get("events",[]):
			if event.get("kind")!="tool" or event.get("name")!="creation.propose" or event.get("status")!="complete": continue
			var id: String=str(event.get("result",{}).get("proposal_id",""))
			for proposal: Dictionary in service.proposals:
				if proposal.id!=id or proposal.status=="superseded": continue
				var key: String=str(proposal.definition.get("id",proposal.id))
				if not candidates.has(key) or candidates[key].status!="applied": candidates[key]=proposal
		for proposal: Dictionary in candidates.values(): ids.append(str(proposal.id))
	if _ids==ids: return
	_ids=ids.duplicate()
	for node: Node in get_children(): remove_child(node); node.queue_free()
	for id: String in ids:
		var card:=Card.new(); add_child(card); card.setup(service,id,true)
	visible=not ids.is_empty()
