extends RefCounted
## Composable native UI data, independent of the object or its game rules.
var checker: RefCounted
var interactions: Array
var inputs: Array=[]
var buttons: Array=[]
var ids: Array=[]
var budget:=128
static func validate(tree: Variant,events: Array,spec: RefCounted) -> bool:
	var parser:=new(); parser.checker=spec; parser.interactions=events
	if not parser.node(tree,"program.ui.workspace.layout",0): return false
	for button: Dictionary in parser.buttons:
		for input: Variant in button.inputs:
			if input not in parser.inputs: return spec.bad(button.at,"Unknown input binding: "+str(input))
	return true
func bad(at: String,message: String) -> bool: return checker.bad(at,message)
func path(value: Variant) -> bool: return checker.path(value) and str(value).begins_with("state.")
func node(s: Variant,at: String,depth: int) -> bool:
	budget-=1
	if depth>8 or budget<0: return bad(at,"UI tree allows 128 nodes and depth 8")
	if not s is Dictionary or not s.get("type") is String: return bad(at,"Each UI node requires type")
	var common: Array=["type","title","visible_path","enabled_path"]
	if s.has("title") and not checker.label(s.title): return bad(at+".title","Expected {ru,en}")
	for key: String in ["visible_path","enabled_path"]:
		if s.has(key) and not path(s[key]): return bad(at+"."+key,"Expected state path")
	var fields: Array=[]; var required: Array=[]
	match s.type:
		"row","column","grid","tabs","panel","scroll": fields=["children","columns"]; required=["children"]
		"text": fields=["text"]; required=["text"]
		"value": fields=["path"]; required=["path"]
		"input": fields=["id","kind","default","initial_path","min","max","step","max_length","options"]; required=["id","kind","title"]
		"button": fields=["id","event","inputs","payload"]; required=["id","title","event"]
		"table": fields=["path","columns","empty"]; required=["path","columns","empty"]
		"progress": fields=["path","max_path"]; required=["path","max_path"]
		"separator": pass
		_: return bad(at,"Unknown UI node type: "+s.type)
	if not checker.keys(s,common+fields,["type"]+required): return bad(at,"Unexpected/missing UI node fields for "+s.type)
	if s.type in ["row","column","grid","tabs","panel","scroll"]:
		if not s.children is Array or s.children.is_empty() or s.children.size()>24: return bad(at+".children","Expected 1..24 UI nodes")
		if s.has("columns") and (s.type!="grid" or not integer(s.columns,1,6)): return bad(at+".columns","Grid columns must be integer 1..6")
		for i: int in s.children.size():
			if not node(s.children[i],at+".children."+str(i),depth+1): return false
			if s.type=="tabs" and not s.children[i].has("title"): return bad(at+".children."+str(i),"Each tab requires title:{ru,en}")
	if s.type=="text" and not checker.label(s.text): return bad(at+".text","Expected {ru,en}")
	for key: String in ["path","max_path","initial_path"]:
		if s.has(key) and not path(s[key]): return bad(at+"."+key,"Bindings can read state only")
	if s.type in ["input","button"]:
		if not checker.id(s.id) or s.id in ids: return bad(at+".id","Expected unique UI identifier")
		ids.append(s.id)
	if s.type=="button":
		if s.event not in interactions or not s.get("inputs",[]) is Array or s.get("inputs",[]).size()>16: return bad(at,"Button needs interaction event and up to16 input IDs")
		if s.has("payload") and (not s.payload is Dictionary or JSON.stringify(s.payload).length()>2048): return bad(at+".payload","Button payload must be a JSON object up to2048 characters")
		buttons.append({"inputs":s.get("inputs",[]),"at":at})
	if s.type=="input":
		inputs.append(s.id)
		if s.kind not in ["text","textarea","number","slider","toggle","select"]: return bad(at+".kind","Expected text/textarea/number/slider/toggle/select")
		if s.has("max_length") and (not integer(s.max_length,1,2048) or s.kind not in ["text","textarea"]): return bad(at+".max_length","Text max_length must be 1..2048")
		for key: String in ["min","max","step"]:
			if s.has(key) and (s.kind not in ["number","slider"] or not (s[key] is int or s[key] is float) or not is_finite(float(s[key]))): return bad(at+"."+key,"Numeric input bounds must be finite numbers")
		if s.kind in ["number","slider"] and (s.get("min",0)>=s.get("max",100) or s.get("step",1)<=0): return bad(at,"Input requires min<max and step>0")
		if s.has("options") and s.kind!="select": return bad(at+".options","Options belong to select input")
		if s.kind=="select":
			if not s.get("options") is Array or s.options.is_empty() or s.options.size()>32: return bad(at+".options","Select requires 1..32 options")
			for option: Variant in s.options:
				if not option is Dictionary or not checker.keys(option,["title","value"],["title","value"]) or not checker.label(option.title) or not scalar(option.value): return bad(at+".options","Options need title:{ru,en} and scalar value")
		if s.has("default"):
			var d: Variant=s.default
			if not scalar(d) or (s.kind in ["text","textarea"] and not d is String) or (s.kind=="toggle" and not d is bool) or (s.kind in ["number","slider"] and not (d is int or d is float)): return bad(at+".default","Default must match input kind")
			if s.kind=="select" and not s.options.any(func(o: Dictionary): return same_scalar(o.value,d)): return bad(at+".default","Select default must match an option value")
	if s.type=="table":
		if not checker.label(s.empty) or not s.columns is Array or s.columns.is_empty() or s.columns.size()>12: return bad(at,"Table requires empty:{ru,en} and 1..12 columns")
		for column: Variant in s.columns:
			if not column is Dictionary or not checker.keys(column,["key","title"],["key","title"]) or not checker.id(column.key) or not checker.label(column.title): return bad(at+".columns","Table columns need key identifier and title:{ru,en}")
	return true
static func scalar(value: Variant) -> bool:
	return value is bool or (value is String and value.length()<=2048) or ((value is int or value is float) and is_finite(float(value)))
static func integer(value: Variant,low: int,high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value==floorf(value) and value>=low and value<=high
static func same_scalar(a: Variant,b: Variant) -> bool:
	if not scalar(a) or not scalar(b): return false
	return a==b if typeof(a)==typeof(b) or ((a is int or a is float) and (b is int or b is float)) else false
static func schema() -> Dictionary:
	return {"format":"workspace:{title:{ru,en},subtitle?:{ru,en},layout:node}. Use layout OR legacy columns. Author your own nested native UI; no object presets. All text {ru,en}; game language/fallback en. Bounds:128 nodes,depth8,24 children/node. Common optional fields: title:{ru,en},visible_path:state.bool,enabled_path:state.bool.",
	"containers":"{type:column|row|panel|scroll|tabs|grid,children:[node,...],columns?:1..6}. columns only for grid. Every direct child of tabs requires title. Nest containers freely; scroll for long content.",
	"display":"{type:text,text:{ru,en}}; {type:value,path:state.x,title?:{ru,en}}; {type:progress,path:state.progress,max_path:state.duration}; {type:separator}; {type:table,path:state.array_of_maps,columns:[{key:field_id,title:{ru,en}}],empty:{ru,en}} (max64 displayed rows,12 columns; live values).",
	"input":"{type:input,id:unique_id,title:{ru,en},kind:text|textarea|number|slider|toggle|select,default?:scalar,initial_path?:state.x,min?:0,max?:100,step?:1,max_length?:2048,options?:[{title:{ru,en},value:scalar}]} (options required only for select). Inputs are UI-local drafts, initialized once; switching language preserves drafts. No automatic state writes/world effects.",
	"button":"{type:button,id:unique_id,title:{ru,en},event:interaction_name,inputs?:[input_id,...],payload?:{plain data}}. Sends payload merged with current typed inputs under event.input.<id> (inputs take precedence). Many buttons may share one interaction handler with different payloads. Handler implements validation, state changes and world effects. UI display never executes arbitrary code or world operations."}
