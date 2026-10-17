extends RefCounted
## Deterministic bounded force layout, computed once, independent of frame rate.
static func compute(nodes: Array, links: Array) -> Dictionary:
	var positions: Dictionary = {}; var indices: Dictionary = {}
	var n: int = nodes.size()
	for i: int in n:
		indices[nodes[i].id] = i
		positions[nodes[i].id] = Vector2(0.5,0.5)+Vector2.from_angle(TAU*i/maxi(1,n)-PI/2)*0.34
	if n == 1: positions[nodes[0].id] = Vector2(0.5,0.5); return positions
	var optimal: float = 0.6/sqrt(n)
	for iteration: int in 90:
		var forces: Dictionary = {}
		for node: Dictionary in nodes: forces[node.id] = (Vector2(0.5,0.5)-positions[node.id])*0.08
		for i: int in n:
			for j: int in range(i+1,n):
				var a: String = nodes[i].id; var b: String = nodes[j].id
				var difference: Vector2 = positions[a]-positions[b]
				if difference.length_squared() < 0.000001: difference = Vector2.from_angle(i+j+0.3)*0.001
				var force: Vector2 = difference.normalized()*optimal*optimal/maxf(0.01,difference.length())
				forces[a] += force; forces[b] -= force
		for edge: Dictionary in links:
			var difference: Vector2 = positions[edge.target]-positions[edge.source]
			var force: Vector2 = difference.normalized()*difference.length_squared()/optimal*0.35
			forces[edge.source] += force; forces[edge.target] -= force
		var temperature: float = lerpf(0.045,0.003,float(iteration)/89)
		for node: Dictionary in nodes:
			var step: Vector2 = forces[node.id]
			positions[node.id] += step.limit_length(temperature)
			positions[node.id] = positions[node.id].clamp(Vector2(0.08,0.08),Vector2(0.92,0.92))
	return positions
