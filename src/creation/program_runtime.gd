extends Node
const VM=preload("res://mods/pax_harness/src/creation/program_vm.gd")
const Host=preload("res://mods/pax_harness/src/creation/program_host.gd")
const Spec=preload("res://mods/pax_harness/src/creation/program_spec.gd")
const Flight=preload("res://mods/pax_harness/src/creation/ship_flight.gd")
var service: Node
var entries: Dictionary={}
var _frame_runs:=0
var _queue: Array=[]
func setup(value: Node) -> void: service=value; process_priority=1300
func install(record_id: String,preserve: bool=false) -> void:
	var record: Dictionary=service.records[record_id]
	var owner_id: String=record_id if record.kind in ["object","body"] else str(record.definition.object_id)
	var program: Dictionary=record.definition.program
	var state: Dictionary=program.state.duplicate(true)
	if preserve: state.merge(record.get("runtime",{}).get("state",{}),true)
	if not record.has("runtime") or not preserve:
		record["runtime"]={"state":state,"enabled":true,"clock":0.0,"runs":0,"last_error":{},"receipts":[],"placements":{},"cooldowns":{}}
	else: record.runtime.state=state
	var host:=Host.new(); host.setup(service,record,owner_id)
	entries[record_id]={"record":record,"owner_id":owner_id,"host":host,"previous":{},"timers":{},"scan":0.0,"day":service.game.day()}
	for placement: Dictionary in record.runtime.get("placements",{}).values(): service._flights().restore_record(placement)
func status(id: String) -> Dictionary:
	if not entries.has(id): return {"ok":false,"code":"program.not_found"}
	return {"ok":true,"result":entries[id].record.runtime.duplicate(true)}
func set_enabled(id: String,enabled: bool) -> void:
	if not entries.has(id): return
	var entry: Dictionary=entries[id]
	entry.record.runtime.enabled=enabled; entry.previous.clear()
	if enabled: entry.record.runtime.last_error={}
	service.changed.emit()
func invalidate_actor(id: String) -> void:
	for entry: Dictionary in entries.values():
		for event: Dictionary in entry.record.definition.program.events:
			if event.type=="plane_cross": entry.previous.erase(str(event.name)+":"+id)
func before_move(id: String) -> void:
	for entry: Dictionary in entries.values():
		var info: Dictionary=entry.host.object_info(entry.owner_id)
		var actor: Variant=entry.host.unit(id)
		if not info.ok or actor==null: continue
		var data: Dictionary=entry.host.actor_info(actor,info.result.body)
		var axes:=Basis(Host.vector(info.result.axes.x),Host.vector(info.result.axes.y),Host.vector(info.result.axes.z))
		var relative: Vector3=axes.transposed()*(Host.vector(data.position_km)-Host.vector(info.result.position_km))
		for event: Dictionary in entry.record.definition.program.events:
			if event.type=="sphere_enter": entry.previous[str(event.name)+":"+id]=relative-Host.vector(event.center_km)
func dispatch(id: String,event_name: String,payload: Dictionary={}) -> Dictionary:
	if not entries.has(id): return {"ok":false,"code":"program.not_found"}
	var entry: Dictionary=entries[id]; var record: Dictionary=entry.record
	if not record.runtime.enabled: return {"ok":false,"code":"program.paused"}
	if not record.definition.program.handlers.has(event_name): return {"ok":false,"code":"program.unknown_event"}
	if _frame_runs>=16:
		if _queue.size()>=256:
			record.runtime.enabled=false; record.runtime.last_error={"code":"program.event_queue_full","path":"handlers."+event_name,"detail":"The shared queue is full"}; service.changed.emit()
			return {"ok":false,"code":"program.event_queue_full"}
		_queue.append({"id":id,"event":event_name,"payload":payload.duplicate(true)}); return {"ok":true,"queued":true}
	_frame_runs+=1
	var event: Dictionary=payload.duplicate(true); event.merge({"name":event_name,"time":float(record.runtime.clock)},true)
	var result: Dictionary=VM.new().run(record.definition.program.handlers[event_name],record.runtime.state,event,{"id":entry.owner_id,"body":entry.host.object_info(entry.owner_id).get("result",{}).get("body","")},entry.host.call_operation)
	record.runtime.state=result.state; record.runtime.runs=int(record.runtime.runs)+1
	if not result.ok:
		record.runtime.enabled=false; record.runtime.last_error=result.error
		service.changed.emit()
	return result
func interact(id: String,event: String,input: Dictionary={}) -> Dictionary:
	if not entries.has(id): return {"ok":false,"code":"program.not_found"}
	if not VM.plain(input) or JSON.stringify(input).length()>8192: return {"ok":false,"code":"program.invalid_input"}
	var program: Dictionary=entries[id].record.definition.program
	if not program.events.any(func(e: Dictionary): return e.name==event and e.type=="interaction"): return {"ok":false,"code":"program.not_interaction"}
	return dispatch(id,event,{"input":input})
func feedback(chat_id: String) -> Array:
	var rows: Array=[]
	for id: String in entries:
		var record: Dictionary=entries[id].record
		if record.get("chat_id","")==chat_id and not record.runtime.get("last_error",{}).is_empty(): rows.append({"object_id":entries[id].owner_id,"program_id":id,"error":record.runtime.last_error.duplicate(true),"paused":true,"completed_operations":record.runtime.get("receipts",[]).slice(-4)})
	return rows.slice(-8)
func _process(delta: float) -> void:
	if not is_instance_valid(service) or not service.current(): return
	# Native economic steps run on the world's worker thread. Resume scene events
	# after the step, retaining the last observed day for day_change.
	var rewind: Variant=service.game.scene_root().get("rewind_state")
	if rewind is Object and bool(rewind.get("rewinding")): return
	_frame_runs=0
	while not _queue.is_empty() and _frame_runs<16:
		var pending: Dictionary=_queue.pop_front(); dispatch(pending.id,pending.event,pending.payload)
	for id: String in entries.keys():
		var entry: Dictionary=entries[id]; var record: Dictionary=entry.record
		if not record.runtime.enabled: continue
		if not service.records.has(entry.owner_id): continue
		var dt: float=minf(delta,0.25); record.runtime.clock=float(record.runtime.clock)+dt
		entry.scan=float(entry.scan)+dt; var scan: bool=float(entry.scan)>=0.1
		if scan: entry.scan=0.0
		for event: Dictionary in record.definition.program.events:
			if not record.runtime.enabled: break
			match event.type:
				"tick":
					var elapsed: float=float(entry.timers.get(event.name,0))+dt; entry.timers[event.name]=elapsed
					if elapsed>=float(event.seconds): entry.timers[event.name]=0.0; dispatch(id,event.name,{"dt":elapsed})
				"day_change":
					var day: int=int(service.game.day())
					if day!=int(entry.day): dispatch(id,event.name,{"day":day,"days":day-int(entry.day)})
				"plane_cross","sphere_enter":
					if scan: _sensor(id,entry,event)
		entry.day=service.game.day()
func _sensor(id: String,entry: Dictionary,event: Dictionary) -> void:
	var mod: Node=Flight.provider(service.api); var code: Node=Flight.implementation(mod)
	if code==null:
		entry.record.runtime.enabled=false; entry.record.runtime.last_error={"code":"program.actor_adapter_unavailable","path":"events."+str(event.name),"detail":"Dyson Sphere Program is not enabled or compatible"}; service.changed.emit(); return
	var owner_info: Dictionary=entry.host.object_info(entry.owner_id)
	if not owner_info.ok: return
	var info: Dictionary=owner_info.result; var p: Vector3=Host.vector(info.position_km)
	var axes:=Basis(Host.vector(info.axes.x),Host.vector(info.axes.y),Host.vector(info.axes.z))
	var star: String=str(code.call("_star_for_body",service.game,info.body))
	var ships: Array=mod.call("get_ships","player"); var live: Dictionary={}
	# Direct entity references stay inside the adapter; no objects enter the VM.
	var units: Variant=code.get("_ships")
	if units is Array:
		for unit: Variant in units:
			if Flight.compatible(unit): live[str(unit.title)]=unit
	for summary: Dictionary in ships:
		if not entry.record.runtime.enabled: break
		var actor: Variant=live.get(str(summary.title))
		if actor==null: actor=entry.host.unit("dyson:"+str(summary.title))
		if actor==null or str(actor.star)!=star or int(actor.peer)!=0: continue
		var data: Dictionary=entry.host.actor_info(actor,info.body,summary)
		var relative: Vector3=axes.transposed()*(Host.vector(data.position_km)-p)-Host.vector(event.center_km)
		var key: String=str(event.name)+":"+str(data.id)
		var before: Vector3=entry.previous.get(key,relative); entry.previous[key]=relative
		var cooldown: Dictionary=entry.record.runtime.cooldowns
		if float(cooldown.get(key,0))>float(entry.record.runtime.clock): continue
		var triggered:=false; var radial:=0.0
		if event.type=="sphere_enter": triggered=before.length()>float(event.radius_km) and relative.length()<=float(event.radius_km); radial=relative.length()
		else:
			var normal: Vector3=Host.vector(event.normal).normalized(); var a: float=before.dot(normal); var b: float=relative.dot(normal)
			var direction: String=str(event.get("direction","forward"))
			triggered=(a<0 and b>=0 and direction in ["forward","both"]) or (a>0 and b<=0 and direction in ["backward","both"])
			if triggered:
				var intersection: Vector3=before.lerp(relative,-a/(b-a)); radial=(intersection-normal*intersection.dot(normal)).length(); triggered=radial<=float(event.radius_km)
		if triggered:
			cooldown[key]=float(entry.record.runtime.clock)+float(event.get("cooldown_seconds",0))
			dispatch(id,event.name,{"actor":data,"radial_km":radial,"position_local_km":Host.array(relative+Host.vector(event.center_km))})
