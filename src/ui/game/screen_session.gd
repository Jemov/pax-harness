extends Node
## A single stable view for a whole assistant turn, rather than hide/show per frame.
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const Viewer=preload("res://mods/pax_harness/src/ui/images/image_viewer.gd")
const Data=preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
var owner_mod: Node
var active:=false
var paused:=false
var chrome: CanvasLayer
var _hidden: Array=[]
var _old_focus: WeakRef
func setup(owner: Node) -> void: owner_mod=owner;process_mode=Node.PROCESS_MODE_ALWAYS
func begin() -> bool:
	if paused:return false
	if active:return true
	if not is_instance_valid(owner_mod) or not owner_mod.has_method("chat_busy") or not owner_mod.chat_busy():return false
	var chat: Variant=Data.property(owner_mod,"chat_ui")
	if not chat is CanvasLayer or not is_instance_valid(chat):return false
	for viewer: Node in Viewer.open_views():viewer.dismiss()
	var focus: Control=chat.get_viewport().gui_get_focus_owner()
	if focus!=null:_old_focus=weakref(focus)
	for node: Variant in [chat,Data.property(chat,"native")]:
		if (node is CanvasLayer or node is CanvasItem or node is Window) and is_instance_valid(node):_hidden.append({"node":weakref(node),"visible":node.visible});node.hide()
	active=true
	chrome=CanvasLayer.new();chrome.name="HarnessScreenSession";chrome.layer=95;add_child(chrome)
	var positioner:=Control.new();positioner.name="Controls";positioner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);positioner.mouse_filter=Control.MOUSE_FILTER_IGNORE;chrome.add_child(positioner)
	var panel:=PanelContainer.new();panel.name="ScreenSessionControls";panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);panel.grow_horizontal=Control.GROW_DIRECTION_BEGIN;panel.grow_vertical=Control.GROW_DIRECTION_BEGIN;panel.position-=Vector2(20,20);positioner.add_child(panel)
	var row:=HBoxContainer.new();panel.add_child(row)
	var label:=Label.new();label.text=L.text("ИИ работает с экраном");row.add_child(label)
	var back:=Button.new();back.text=L.text("Вернуться в чат");back.tooltip_text=L.text("Приостановить работу с экраном и открыть чат");back.pressed.connect(_return_to_chat);row.add_child(back)
	var stop:=Button.new();stop.text=L.text("Остановить");stop.pressed.connect(_stop);row.add_child(stop)
	return true
func owns_point(viewport: Viewport, at: Vector2) -> bool:
	if not active or not is_instance_valid(chrome) or chrome.get_viewport()!=viewport:return false
	var panel: Control=chrome.get_node_or_null("Controls/ScreenSessionControls")
	return panel!=null and panel.get_global_rect().has_point(at)
func resume_for_player_task() -> void:paused=false
func _return_to_chat() -> void:
	paused=true
	if is_instance_valid(owner_mod):
		owner_mod.invalidate_game_input_frames()
		var virtual: Variant=Data.property(owner_mod,"_virtual_input")
		if is_instance_valid(virtual):virtual.suspended=true
	end()
	var chat: Variant=Data.property(owner_mod,"chat_ui")
	if is_instance_valid(chat):chat.open()
func _stop() -> void:
	if is_instance_valid(owner_mod):owner_mod.chat_stop()
	end()
	var chat: Variant=Data.property(owner_mod,"chat_ui")
	if is_instance_valid(chat):chat.open()
func end(restore: bool=true) -> void:
	if not active:return
	active=false
	for item: Dictionary in _hidden:
		var node: Variant=item.node.get_ref()
		if restore and is_instance_valid(node) and not node.is_queued_for_deletion():node.visible=item.visible
	_hidden.clear()
	if is_instance_valid(chrome):chrome.queue_free()
	chrome=null
	var previous: Variant=_old_focus.get_ref() if _old_focus!=null else null
	if restore and is_instance_valid(previous) and previous.is_visible_in_tree():previous.grab_focus()
	_old_focus=null
func _exit_tree() -> void:end()
