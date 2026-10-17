extends RefCounted
const InstructionsDialog = preload("res://mods/pax_harness/src/ui/chat/instructions_dialog.gd")
## Plan disclosure and player-editable rules. No extra permanent footer panels.
static func render(ui: Node) -> void:
	var plan: Dictionary = ui.store.current().get("plan",{})
	if plan.is_empty(): return
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation",6)
	ui.feed.add_child(block)
	var done: int = plan.get("steps",[]).filter(func(step: Dictionary): return step.get("status") == "done").size()
	var key: String = "plan:"+ui.store.selected
	var button: Button = ui._button(("▾  " if ui._expanded.get(key,false) else "▸  ")+"План · "+str(done)+"/"+str(plan.get("steps",[]).size())+" · "+str(plan.get("goal","")),ui._toggle.bind(key))
	button.name = "TaskPlan"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.tooltip_text = str(plan.get("goal",""))
	block.add_child(button)
	if not ui._expanded.get(key,false): return
	for condition: String in plan.get("conditions",[]): block.add_child(ui._label("• "+condition,13,ui.QUIET))
	var icons := {"pending":"○","in_progress":"◌","done":"✓","blocked":"!"}
	for step: Dictionary in plan.get("steps",[]):
		var label: Label = ui._label(str(icons.get(step.get("status"),"○"))+"  "+str(step.get("text","")),14,ui.TEXT)
		label.tooltip_text = str(step.get("evidence",""))
		block.add_child(label)

static func edit(ui: Node) -> void:
	if ui.get_node_or_null("InstructionsDialog") != null: return
	InstructionsDialog.new().setup(ui)
