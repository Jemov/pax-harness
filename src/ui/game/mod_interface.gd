extends RefCounted
## Observed mod controls only. No desktop input or model-selected method.
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
var api: Node
var game: RefCounted
var refs: Dictionary={}
var sequence:=0
func setup(p_api: Node,p_game: RefCounted) -> void:
	api=p_api; game=p_game; refs.clear()
func _script_mod(object: Object,id: String) -> bool:
	if not is_instance_valid(object): return false
	var script: Variant=object if object is Script else object.get_script()
	return script is Script and script.resource_path.begins_with("res://mods/"+id+"/")
func _signal_mod(control: Control,signal_name: String,id: String) -> bool:
	for connection: Dictionary in control.get_signal_connection_list(signal_name):
		var callback: Callable=connection.get("callable",Callable())
		if callback.is_valid() and _script_mod(callback.get_object(),id): return true
	return false
func _native_decoration(object: Object) -> bool:
	# The game attaches a sound callback to every button. It does not own the
	# panel's gameplay; keep all other foreign callbacks subject to the guards.
	if not is_instance_valid(object):return false
	var script: Variant=object if object is Script else object.get_script()
	return script is Script and script.resource_path=="res://src/ui/Sound.gd"
func _exclusive_scope(root: Control,id: String,registered: bool=false) -> bool:
	# A mod may build a plain overlay under the game's CanvasLayer. Read its
	# labels/fields only when every scripted UI owner in that overlay agrees.
	# A mixed native HUD or another mod's controls never inherit ownership.
	var pending: Array=[root]; var owned:=false; var visited:=0
	while not pending.is_empty() and visited<4000:
		var node: Node=pending.pop_back(); visited+=1
		if node is Node3D or node is SubViewport: continue
		pending.append_array(node.get_children())
		if not node is Control: continue
		var script: Variant=node.get_script()
		if script is Script:
			if _script_mod(node,id):owned=true
			elif not registered or script.resource_path.begins_with("res://mods/"):return false
		# A theme's hover/drag/draw hooks are decoration, not ownership of the
		# controls inside a window registered through the game's add_window API.
		var signals: Array=["pressed","toggled","value_changed","item_selected","text_changed","text_submitted","tab_changed"] if registered else ["pressed","mouse_entered","gui_input","value_changed","item_selected","text_changed"]
		for signal_name: String in signals:
			if not node.has_signal(signal_name): continue
			for connection: Dictionary in node.get_signal_connection_list(signal_name):
				var callback: Callable=connection.get("callable",Callable())
				if not callback.is_valid(): continue
				var target: Object=callback.get_object()
				if not is_instance_valid(target):continue
				var target_script: Variant=target if target is Script else target.get_script()
				if not target_script is Script: continue
				if _native_decoration(target):continue
				if _script_mod(target,id):owned=true
				elif not registered or target_script.resource_path.begins_with("res://mods/"):return false
	return owned and pending.is_empty()
func _registered_windows() -> Array:
	var main: Variant=game.scene_root() if is_instance_valid(game) and game.has_method("scene_root") else null
	var windows: Variant=Data.property(main,"mod_windows")
	return windows.slice(0,128) if windows is Array else []
func _window_caption(window: Control) -> String:
	var key: String=str(window.get_meta("window_float_key",""))
	return key.trim_prefix("mod:").left(200) if key.begins_with("mod:") else ""
func _owned_windows(id: String,scope_cache: Dictionary) -> Array:
	var key: String="registered:"+id
	if not scope_cache.has(key):
		var owned: Array=[]
		for window: Variant in _registered_windows():
			if window is Control and is_instance_valid(window) and window.is_inside_tree() and _window_caption(window)!="" and _exclusive_scope(window,id,true):owned.append(window)
		scope_cache[key]=owned
	return scope_cache[key]
func belongs(control: Node,mod: Node,id: String,scope_cache: Dictionary,allow_hover: bool=true) -> bool:
	if mod.is_ancestor_of(control) or control==mod: return true
	var cursor: Node=control
	while cursor!=null:
		if _script_mod(cursor,id): return true
		cursor=cursor.get_parent()
	if control is Control:
		for signal_name: String in ["pressed","toggled","mouse_entered","value_changed","item_selected","text_changed","text_submitted","tab_changed","gui_input"]:
			if signal_name=="mouse_entered" and not allow_hover:continue
			if control.has_signal(signal_name) and _signal_mod(control,signal_name,id): return true
	for window: Control in _owned_windows(id,scope_cache):
		if window==control or window.is_ancestor_of(control):return true
	var overlay: Node=control
	while overlay is Control:
		if overlay.get_parent() is CanvasLayer:
			var key: int=overlay.get_instance_id()
			if not scope_cache.has(key): scope_cache[key]=_exclusive_scope(overlay,id)
			return scope_cache[key]
		overlay=overlay.get_parent()
	return false
func _label(control: Control) -> String:
	if control is LineEdit and control.secret: return "[private]"
	if control is Label or control is Button or control is LineEdit or control is TextEdit: return str(control.text).left(1000)
	if control is RichTextLabel: return control.get_parsed_text().left(2000)
	return str(control.name).left(160)
func _caption_labels(root: Control) -> Array:
	var labels: Array=[];var pending: Array=[[root,0]];var visited:=0
	while not pending.is_empty() and visited<64 and labels.size()<8:
		var item: Array=pending.pop_front();var node: Node=item[0];visited+=1
		if not node is Control or not node.is_visible_in_tree():continue
		if node is LineEdit or node is TextEdit:continue
		if node is Label or node is RichTextLabel:
			var text: String=_label(node).left(120)
			if text!="" and text not in labels:labels.append(text)
		if item[1]<4:
			for nested: Node in node.get_children():pending.append([nested,item[1]+1])
	return labels
func _context(control: Control) -> Array:
	# Associate repeated +/- buttons and unnamed inputs with their actual table
	# row. Never infer a resource from coordinates or from a previous inspection.
	var labels: Array=[]; var child: Node=control
	# Buttons and clickable cards may render captions in nested containers.
	# Include only visible rendered labels, never editable/private field values.
	if control is BaseButton or not control.get_signal_connection_list("gui_input").is_empty():
		labels=_caption_labels(control)
	# A panel may overlay a non-interactive caption beside its single button.
	# Do not guess an association when the panel contains several buttons.
	var row: Node=control.get_parent()
	if control is BaseButton and row is PanelContainer and row.get_children().filter(func(node: Node):return node is BaseButton).size()==1:
		for sibling: Node in row.get_children():
			if sibling==control or not sibling is Control or sibling.mouse_filter!=Control.MOUSE_FILTER_IGNORE:continue
			for text: String in _caption_labels(sibling):
				if text not in labels and labels.size()<8:labels.append(text)
	for depth: int in 3:
		var parent: Node=child.get_parent()
		if not parent is Control: break
		var siblings: Array=parent.get_children()
		if parent is GridContainer:
			var index: int=child.get_index(); var start: int=(index/parent.columns)*parent.columns
			siblings=siblings.slice(start,start+parent.columns)
		if parent is GridContainer or parent is HBoxContainer:
			for sibling: Node in siblings:
				if sibling==control or not sibling is Control or not sibling.is_visible_in_tree(): continue
				if sibling is Label or sibling is RichTextLabel:
					var text: String=_label(sibling).left(120)
					if text!="" and text not in labels: labels.append(text)
				if labels.size()>=8: return labels
		child=parent
	return labels
func _actions(control: Control,id: String,scope_cache: Dictionary={}) -> Array:
	var mod: Node=api.get_mod(id)
	var actions: Array=_primary_actions(control,id) if is_instance_valid(mod) and belongs(control,mod,id,scope_cache,false) else []
	# Reveal native hover menus through their observed mod-owned signal.
	# No arbitrary method selection or movement of the desktop pointer.
	if not (control is BaseButton and control.disabled) and control.mouse_filter!=Control.MOUSE_FILTER_IGNORE and _signal_mod(control,"mouse_entered",id): actions.append("hover")
	return actions
func _pointer_owned(control: Control,id: String) -> bool:
	if control.mouse_filter==Control.MOUSE_FILTER_IGNORE:return false
	var owned:=_script_mod(control,id) and control.has_method("_gui_input")
	# A plain Label/Panel often wires gui_input to a mod controller instead of
	# overriding _gui_input. Observe that signal without granting another
	# controller's gameplay callbacks access through the same ref.
	for connection: Dictionary in control.get_signal_connection_list("gui_input"):
		var callback: Callable=connection.get("callable",Callable())
		if not callback.is_valid():continue
		if not _script_mod(callback.get_object(),id):return false
		owned=true
	return owned
func _menu_owned(control: MenuButton,id: String) -> bool:
	var owned:=false
	for signal_name: String in ["id_pressed","index_pressed"]:
		for connection: Dictionary in control.get_popup().get_signal_connection_list(signal_name):
			var callback: Callable=connection.get("callable",Callable())
			if not callback.is_valid():continue
			if not _script_mod(callback.get_object(),id):return false
			owned=true
	return owned
func _menu_options(control: MenuButton) -> Array:
	var popup:=control.get_popup();var options: Array=[]
	for index: int in mini(popup.item_count,100):
		options.append({"index":index,"id":popup.get_item_id(index),"text":popup.get_item_text(index),"disabled":popup.is_item_disabled(index),"separator":popup.is_item_separator(index),"checked":popup.is_item_checked(index),"submenu":popup.get_item_submenu(index)!=""})
	return options
func _primary_actions(control: Control,id: String) -> Array:
	if control is BaseButton:
		if control.disabled: return []
		if control is MenuButton:return ["press","select"] if control.get_popup().visible and _menu_owned(control,id) else ["press"]
		if control is OptionButton: return ["select"]
		return ["press","toggle"] if control.toggle_mode else ["press"]
	if control is LineEdit: return ["set_text","submit_text"] if control.editable and not control.secret else []
	if control is TextEdit: return ["set_text"] if control.editable else []
	if control is SpinBox: return ["set_number"] if control.editable else []
	if control is Slider: return ["set_number"] if control.editable else []
	if control is TabContainer: return ["select_tab"]
	if control is ItemList: return ["select"]
	if _pointer_owned(control,id):return ["click_at"]
	return []
func _remember(snapshot: Dictionary) -> String:
	# A fresh opaque ID on every unchanged read would look like new data to the
	# runtime's no-progress guard. Reuse only the exact live identity and action
	# snapshot; stale labels/menu options still require a new observed reference.
	for key: String in refs:
		var old: Dictionary=refs[key]
		if old.get("id")!=snapshot.id or old.has("menu_items")!=snapshot.has("menu_items"):continue
		var same:=true
		for field: String in snapshot:
			if not old.has(field):same=false;break
			if snapshot[field] is WeakRef:
				if not old[field] is WeakRef or old[field].get_ref()!=snapshot[field].get_ref():same=false;break
			elif old[field]!=snapshot[field]:same=false;break
		if same:return key
	sequence+=1
	var key: String="mod-ui:"+str(sequence)
	refs[key]=snapshot
	return key
func _ref(control: Control,mod: Node,id: String) -> String:
	var snapshot: Dictionary={"node":weakref(control),"mod":weakref(mod),"id":id,"label":_label(control),"tooltip":control.tooltip_text,"context":_context(control),"hover_bindings":control.get_signal_connection_list("mouse_entered")}
	if control is MenuButton and control.get_popup().visible:snapshot["menu_items"]=_menu_options(control)
	return _remember(snapshot)
func _visible_ids() -> Dictionary:
	var root: Variant=game.call("scene_root") if game.has_method("scene_root") else null
	var pending: Array=[root] if root is Node else []; var result: Dictionary={}; var visited:=0
	while not pending.is_empty() and visited<20000:
		var node: Node=pending.pop_back(); visited+=1
		if not is_instance_valid(node) or node.is_queued_for_deletion(): continue
		pending.append_array(node.get_children())
		if node is Control and node.is_visible_in_tree(): result[node.get_instance_id()]=true
	return result
func _reveal(entry: Dictionary,mod: Node) -> void:
	if not refs.has(entry.get("opener","")) or Time.get_ticks_msec()>int(entry.get("reveal_until",0)): return
	var opening: Dictionary=refs[entry.opener]; var control: Variant=opening.node.get_ref()
	if not is_instance_valid(control) or control.is_queued_for_deletion() or not control.is_visible_in_tree(): return
	if not belongs(control,mod,entry.id,{}) or _label(control)!=opening.label or control.tooltip_text!=opening.tooltip or _context(control)!=opening.context: return
	if "hover" not in _actions(control,entry.id) or control.get_signal_connection_list("mouse_entered")!=opening.hover_bindings: return
	control.mouse_entered.emit()
func inspect(id: String,mod: Node,args: Dictionary) -> Dictionary:
	var root: Variant=game.call("scene_root") if game.has_method("scene_root") else null
	if not root is Node: return Data.failed("mods.ui_unavailable")
	var pending: Array=[root]; var rows: Array=[]; var visited:=0; var scope_cache: Dictionary={}
	var search: String=str(args.get("search","")).to_lower()
	# These are actual game-registered mod windows, not model-selected paths.
	# Their native navigation can be folded by HUD replacements.
	for window: Control in _owned_windows(id,scope_cache):
		var caption: String=_window_caption(window)
		if search=="" or caption.to_lower().contains(search):rows.append({"ref":"","kind":"RegisteredModPanel","text":caption,"visible":window.is_visible_in_tree(),"actions":["press"],"_window":window})
	# A public navigation catalogue is also used by companion UI mods. This
	# supports lazy windows whose native navigation buttons are currently folded.
	if mod.has_method("ui_tabs"):
		var tabs: Variant=mod.call("ui_tabs")
		if tabs is Array:
			for tab: Variant in tabs.slice(0,100):
				if not tab is Dictionary or not tab.get("fn") is Callable or not tab.fn.is_valid(): continue
				var caption: String=str(tab.get("caption",tab.get("id",""))).left(200)
				if search!="" and not caption.to_lower().contains(search): continue
				rows.append({"ref":"","kind":"ModPanel","text":caption,"actions":["press"],"_tab":str(tab.get("id",""))})
	while not pending.is_empty() and visited<20000:
		var node: Node=pending.pop_front(); visited+=1
		if not is_instance_valid(node) or node.is_queued_for_deletion(): continue
		# Harness history/Apply buttons and API profiles are outside this interface.
		if _script_mod(node,"pax_harness") or _script_mod(node,"ai_tuning") or _script_mod(node,"prompt_lab_local"): continue
		pending.append_array(node.get_children())
		if not node is Control or not node.is_visible_in_tree() or not belongs(node,mod,id,scope_cache): continue
		var text: String=_label(node); var actions: Array=_actions(node,id,scope_cache)
		if text.begins_with("@") and actions.is_empty(): continue
		var tooltip: String=node.tooltip_text.left(500); var context: Array=_context(node)
		if search!="" and not (text+" "+tooltip+" "+" ".join(context)).to_lower().contains(search): continue
		if text.is_empty() and actions.is_empty(): continue
		var row := {"ref":"","kind":node.get_class(),"text":text,"tooltip":tooltip,"context":context,"actions":actions,"bounds":{"x":node.global_position.x,"y":node.global_position.y,"width":node.size.x,"height":node.size.y}}
		if node is BaseButton: row["disabled"]=node.disabled; row["checked"]=node.button_pressed
		if node is Range: row.merge({"value":node.value,"min":node.min_value,"max":node.max_value,"step":node.step})
		if node is OptionButton:
			var options: Array=[]
			for i: int in mini(node.item_count,100): options.append({"index":i,"text":node.get_item_text(i),"disabled":node.is_item_disabled(i)})
			row.merge({"options":options,"selected":node.selected,"option_count":node.item_count})
		if node is MenuButton:
			row["menu_open"]=node.get_popup().visible
			if node.get_popup().visible:row.merge({"options":_menu_options(node),"option_count":node.get_popup().item_count})
		if node is TabContainer:
			var tabs: Array=[]
			for i: int in node.get_tab_count(): tabs.append({"index":i,"text":node.get_tab_title(i),"disabled":node.is_tab_disabled(i)})
			row.merge({"tabs":tabs,"selected":node.current_tab})
		row["_node"]=node; rows.append(row)
	var offset: int=maxi(0,int(args.get("offset",0))); var limit: int=clampi(int(args.get("limit",50)),1,100)
	if refs.size()>2000: refs.clear()
	var page: Array=rows.slice(offset,offset+limit)
	for row: Dictionary in page:
		if row.has("_window"):
			row.ref=_remember({"mod":weakref(mod),"id":id,"window":weakref(row._window),"label":row.text});row.erase("_window")
		elif row.has("_tab"):
			row.ref=_remember({"mod":weakref(mod),"id":id,"tab":row._tab,"label":row.text});row.erase("_tab")
		else: row.ref=_ref(row._node,mod,id); row.erase("_node")
	return Data.success({"mod":id,"controls":page,"total":rows.size(),"has_more":offset+page.size()<rows.size(),"next_offset":offset+page.size(),"scan_truncated":not pending.is_empty(),"note":"Visible mod controls and observed navigation to game-registered mod windows; inspect again after an action. Refs expire on reload, removal or changed labels."})
func act(args: Dictionary) -> Dictionary:
	var key: String=str(args.get("ref","")); var action: String=str(args.get("action",""))
	if not refs.has(key): return Data.failed("mods.ui_ref_expired")
	var entry: Dictionary=refs[key]; var mod: Variant=entry.mod.get_ref()
	if entry.has("window"):
		var window: Variant=entry.window.get_ref()
		if not is_instance_valid(mod) or api.get_mod(entry.id)!=mod or not is_instance_valid(window) or window.is_queued_for_deletion() or window not in _registered_windows() or _window_caption(window)!=entry.label or not _exclusive_scope(window,entry.id,true):return Data.failed("mods.ui_ref_expired")
		if action!="press":return Data.failed("mods.ui_action_unavailable")
		var main: Node=game.scene_root()
		var hud: Variant=main.hud() if main.has_method("hud") else null
		if not is_instance_valid(hud) or not hud.has_method("toggle_window"):return Data.failed("mods.ui_unavailable")
		hud.toggle_window(window)
		return Data.success({"mod":entry.id,"action":action,"dispatched":true,"completed":false,"instruction":"Inspect the registered mod window to verify its contents and state."})
	if entry.has("tab"):
		if not is_instance_valid(mod) or api.call("get_mod",entry.id)!=mod or not mod.has_method("ui_tabs"): return Data.failed("mods.ui_ref_expired")
		if action!="press": return Data.failed("mods.ui_action_unavailable")
		var tabs: Variant=mod.call("ui_tabs")
		if not tabs is Array: return Data.failed("mods.ui_ref_expired")
		for tab: Variant in tabs:
			if not tab is Dictionary: continue
			if str(tab.get("id",""))!=entry.tab or str(tab.get("caption",tab.get("id","")))!=entry.label: continue
			var callback: Variant=tab.get("fn")
			if not callback is Callable or not callback.is_valid(): return Data.failed("mods.ui_ref_expired")
			callback.call()
			return Data.success({"mod":entry.id,"action":action,"dispatched":true,"completed":false,"instruction":"Inspect the opened mod panel to observe its actual controls and result."})
		return Data.failed("mods.ui_changed")
	var control: Variant=entry.node.get_ref()
	if not is_instance_valid(control) or not is_instance_valid(mod) or control.is_queued_for_deletion() or api.call("get_mod",entry.id)!=mod: return Data.failed("mods.ui_ref_expired")
	# Reactivate only the exact native hover menu that revealed this reference.
	# It must genuinely become visible again before the normal guards/actions.
	if not control.is_visible_in_tree(): _reveal(entry,mod)
	if not control.is_visible_in_tree() or not belongs(control,mod,entry.id,{}) or _label(control)!=entry.label or control.tooltip_text!=entry.tooltip or _context(control)!=entry.context: return Data.failed("mods.ui_changed")
	if action not in _actions(control,entry.id): return Data.failed("mods.ui_action_unavailable")
	if action=="hover" and control.get_signal_connection_list("mouse_entered")!=entry.hover_bindings: return Data.failed("mods.ui_changed")
	match action:
		"hover":
			var before_visible: Dictionary=_visible_ids()
			control.mouse_entered.emit()
			var observed: Dictionary=inspect(entry.id,mod,{"limit":100})
			var revealed: Array=[]
			if observed.get("ok",false):
				for row: Dictionary in observed.result.controls:
					var target: Dictionary=refs.get(row.ref,{})
					if not target.has("node"): continue
					var node: Variant=target.node.get_ref()
					if not is_instance_valid(node) or before_visible.has(node.get_instance_id()): continue
					target["opener"]=key; target["reveal_until"]=Time.get_ticks_msec()+120000
					revealed.append(row)
			return Data.success({"mod":entry.id,"action":action,"dispatched":true,"completed":false,"revealed_controls":revealed,"has_more":observed.get("result",{}).get("has_more",false),"instruction":"Use these observed refs to navigate the revealed menu. If it auto-closes, its original hover trigger is reactivated before the action; hidden controls are never invoked without reopening. Refs expire after two minutes or UI changes. Read back the outcome."})
		"press":
			if control is MenuButton:control.show_popup()
			elif control.toggle_mode: control.button_pressed=not control.button_pressed
			control.pressed.emit()
		"toggle":
			if not args.get("checked") is bool: return Data.failed("mods.ui_invalid_value")
			control.button_pressed=args.checked
		"set_text","submit_text":
			if not args.get("text") is String or args.text.length()>4000: return Data.failed("mods.ui_invalid_value")
			control.text=args.text
			if control is LineEdit:
				control.text_changed.emit(control.text)
				if action=="submit_text": control.text_submitted.emit(control.text)
			else: control.text_changed.emit()
		"set_number":
			if not Data.number(args.get("number")) or not is_finite(float(args.number)) or float(args.number)<control.min_value or float(args.number)>control.max_value: return Data.failed("mods.ui_invalid_value")
			control.value=float(args.number)
		"select":
			if control is MenuButton:
				if entry.get("menu_items",[])!=_menu_options(control):return Data.failed("mods.ui_changed")
				if not Data.number(args.get("index")) or float(args.index)!=floorf(float(args.index)):return Data.failed("mods.ui_invalid_value")
				var options: Array=entry.get("menu_items",[]);var index: int=int(args.index)
				if index<0 or index>=options.size():return Data.failed("mods.ui_invalid_value")
				if options[index].disabled or options[index].separator or options[index].submenu:return Data.failed("mods.ui_action_unavailable")
				var popup: PopupMenu=control.get_popup();var item_id: int=options[index].id
				popup.hide();popup.id_pressed.emit(item_id)
				if is_instance_valid(popup) and not popup.is_queued_for_deletion():popup.index_pressed.emit(index)
				return Data.success({"mod":entry.id,"action":action,"dispatched":true,"completed":false,"instruction":"Read back the mod state or interface to verify the selected menu item's actual result."})
			if not Data.number(args.get("index")) or float(args.index)!=floorf(float(args.index)) or args.index<0 or args.index>=control.item_count: return Data.failed("mods.ui_invalid_value")
			var index: int=int(args.index)
			if control is OptionButton:
				if control.is_item_disabled(index): return Data.failed("mods.ui_action_unavailable")
				control.select(index); control.item_selected.emit(index)
			elif control is ItemList:
				if control.is_item_disabled(index): return Data.failed("mods.ui_action_unavailable")
				control.select(index); control.item_selected.emit(index)
		"select_tab":
			if not Data.number(args.get("index")) or float(args.index)!=floorf(float(args.index)) or args.index<0 or args.index>=control.get_tab_count() or control.is_tab_disabled(int(args.index)): return Data.failed("mods.ui_invalid_value")
			control.current_tab=int(args.index)
		"click_at":
			if not Data.number(args.get("x")) or not Data.number(args.get("y")) or not is_finite(float(args.x)) or not is_finite(float(args.y)): return Data.failed("mods.ui_invalid_value")
			var point:=Vector2(float(args.x),float(args.y))
			if not Rect2(Vector2.ZERO,control.size).has_point(point): return Data.failed("mods.ui_invalid_value")
			for pressed: bool in [true,false]:
				if not is_instance_valid(control) or control.is_queued_for_deletion(): break
				var event:=InputEventMouseButton.new(); event.position=point; event.global_position=control.global_position+point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
				if _script_mod(control,entry.id) and control.has_method("_gui_input"):control.call("_gui_input",event)
				if is_instance_valid(control) and not control.is_queued_for_deletion():control.gui_input.emit(event)
	return Data.success({"mod":entry.id,"action":action,"dispatched":true,"completed":false,"instruction":"Read back the mod state or interface to verify the actual result."})
