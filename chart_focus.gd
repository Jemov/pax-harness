extends RefCounted
static func paths(nodes: Array, edges: Array, seed: String) -> Dictionary:
	var result: Dictionary = {}
	if seed == "": return result
	result[seed] = true
	# Separate upstream and downstream traversals: do not turn an ancestor into
	# a new downstream seed and accidentally select every branch of the graph.
	for backwards: bool in [false,true]:
		var queue: Array = [seed]; var visited: Dictionary = {seed:true}
		while not queue.is_empty():
			var id: String = queue.pop_front()
			for edge: Dictionary in edges:
				var from: String = edge.target if backwards else edge.source
				var to: String = edge.source if backwards else edge.target
				if from == id and not visited.has(to): visited[to] = true; result[to] = true; queue.append(to)
	return result
