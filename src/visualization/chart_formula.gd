extends RefCounted
## A small mathematical grammar, with no Godot Expression or script execution.
const VARIABLES := ["x","a","b","c","d","L","k","x0"]
const ARITY := {"sin":[1,1],"cos":[1,1],"tan":[1,1],"asin":[1,1],"acos":[1,1],"atan":[1,1],"atan2":[2,2],"sinh":[1,1],"cosh":[1,1],"tanh":[1,1],"exp":[1,1],"ln":[1,1],"log":[1,2],"log10":[1,1],"log2":[1,1],"sqrt":[1,1],"abs":[1,1],"pow":[2,2],"min":[2,8],"max":[2,8],"clamp":[3,3]}
var error := ""
var tree: Dictionary = {}
var _tokens: Array[String] = []
var _index := 0
var _depth := 0

func parse(source: String) -> bool:
	error = ""; tree = {}; _tokens.clear(); _index = 0; _depth = 0
	if source.length() > 1024: return _fail("Formula exceeds 1024 characters")
	var numeric := RegEx.create_from_string("^(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
	var identifier := RegEx.create_from_string("^[A-Za-z_][A-Za-z_0-9]*")
	var rest: String = source.strip_edges()
	while not rest.is_empty():
		var token := ""
		var number: RegExMatch = numeric.search(rest)
		var name_match: RegExMatch = identifier.search(rest)
		if number != null: token = number.get_string()
		elif name_match != null: token = name_match.get_string()
		elif rest.begins_with("**"): token = "**"
		elif rest[0] in ["+","-","*","/","^","(",")",","]: token = rest[0]
		else: return _fail("Unexpected character: "+rest[0])
		_tokens.append("^" if token == "**" else token)
		if _tokens.size() > 256: return _fail("Formula exceeds 256 tokens")
		rest = rest.substr(token.length()).strip_edges()
	_tokens.append("")
	tree = _expression(0)
	if error.is_empty() and _peek() != "": _fail("Expected an operator before: "+_peek())
	return error.is_empty() and not tree.is_empty()

func _fail(message: String) -> bool:
	if error.is_empty(): error = message
	return false

func _peek() -> String: return _tokens[_index] if _index < _tokens.size() else ""
func _take() -> String:
	var value: String = _peek(); _index += 1
	return value

func _expression(minimum: int) -> Dictionary:
	_depth += 1
	if _depth > 32:
		_fail("Formula nesting exceeds 32 levels")
		return {}
	var first: String = _take()
	var node: Dictionary = {}
	if first in ["+","-"]:
		node = {"op":"neg" if first == "-" else "pos","a":_expression(25)}
	elif first == "(":
		node = _expression(0)
		if _take() != ")": _fail("Expected closing parenthesis")
	elif first.is_valid_float():
		if not is_finite(float(first)): _fail("Numeric literal must be finite")
		node = {"n":float(first)}
	elif first in ["pi","e"]: node = {"n":PI if first == "pi" else exp(1.0)}
	elif first in VARIABLES: node = {"v":first}
	elif ARITY.has(first):
		if _take() != "(": _fail("Expected ( after "+first)
		var arguments: Array = []
		while _peek() not in [")",""] and error.is_empty():
			arguments.append(_expression(0))
			if _peek() != ",": break
			_take()
			if _peek() == ")": _fail("Expected an argument after comma")
		if _take() != ")": _fail("Expected closing parenthesis for "+first)
		if arguments.size() < ARITY[first][0] or arguments.size() > ARITY[first][1]: _fail("Wrong number of arguments for "+first)
		node = {"fn":first,"args":arguments}
	else: _fail("Expected a number, x, parameter or math function; got: "+first)
	while error.is_empty():
		var op: String = _peek()
		var precedence: int = 30 if op == "^" else 20 if op in ["*","/"] else 10 if op in ["+","-"] else -1
		if precedence < minimum: break
		_take()
		node = {"op":op,"a":node,"b":_expression(precedence if op == "^" else precedence+1)}
	_depth -= 1
	return node

func evaluate(x: float, parameters: Dictionary, barriers: Array = []) -> float:
	if not error.is_empty() or tree.is_empty(): return NAN
	var variables: Dictionary = {"x":x,"a":1.0,"b":1.0,"c":0.0,"d":0.0,"L":1.0,"k":1.0,"x0":0.0}
	for key: String in VARIABLES:
		if key != "x" and parameters.has(key): variables[key] = float(parameters[key])
	var value: float = _evaluate(tree,variables,barriers)
	return value if is_finite(value) and absf(value) <= 1.0e15 else NAN

func _evaluate(node: Dictionary, variables: Dictionary, barriers: Array) -> float:
	if node.has("n"): return float(node.n)
	if node.has("v"): return float(variables[node.v])
	if node.has("op"):
		var a: float = _evaluate(node.a,variables,barriers)
		if node.op == "neg": return -a
		if node.op == "pos": return a
		var b: float = _evaluate(node.b,variables,barriers)
		if not is_finite(a) or not is_finite(b): return NAN
		match node.op:
			"+": return a+b
			"-": return a-b
			"*": return a*b
			"/":
				barriers.append(b)
				return a/b if b != 0 else NAN
			"^": return pow(a,b) if not (a == 0 and b < 0) else NAN
	var args: Array[float] = []
	for child: Dictionary in node.args:
		var value: float = _evaluate(child,variables,barriers)
		if not is_finite(value): return NAN
		args.append(value)
	var a: float = args[0]
	match node.fn:
		"sin": return sin(a)
		"cos": return cos(a)
		"tan":
			var denominator: float = cos(a)
			barriers.append(denominator)
			return tan(a) if absf(denominator) > 1.0e-12 else NAN
		"asin": return asin(a) if absf(a) <= 1 else NAN
		"acos": return acos(a) if absf(a) <= 1 else NAN
		"atan": return atan(a)
		"atan2": return atan2(a,args[1])
		"sinh": return (exp(a)-exp(-a))/2
		"cosh": return (exp(a)+exp(-a))/2
		"tanh": return 2/(1+exp(-2*a))-1 if a >= 0 else 1-2/(1+exp(2*a))
		"exp": return exp(a)
		"ln","log","log10","log2":
			if a <= 0: return NAN
			var base: float = args[1] if args.size() == 2 else 10.0 if node.fn == "log10" else 2.0 if node.fn == "log2" else exp(1.0)
			return log(a)/log(base) if base > 0 and base != 1 else NAN
		"sqrt": return sqrt(a) if a >= 0 else NAN
		"abs": return absf(a)
		"pow": return pow(a,args[1]) if not (a == 0 and args[1] < 0) else NAN
		"min": return args.min()
		"max": return args.max()
		"clamp": return clampf(a,args[1],args[2]) if args[1] <= args[2] else NAN
	return NAN

func continuous_between(left: float, right: float, parameters: Dictionary) -> bool:
	var previous: Array = []
	for step: int in 5:
		var barriers: Array = []
		if not is_finite(evaluate(lerpf(left,right,step/4.0),parameters,barriers)): return false
		if step > 0:
			if barriers.size() != previous.size(): return false
			for index: int in barriers.size():
				if float(barriers[index])*float(previous[index]) <= 0: return false
		previous = barriers
	return true
