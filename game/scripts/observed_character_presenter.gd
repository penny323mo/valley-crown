extends RefCounted
## Own/currently observed units only. Corpses are bounded, value-only presentation.
const Controller = preload("res://scripts/action_character.gd")
const MAX_DEATH_VISUALS := 16
var controllers: Dictionary = {}
var corpses: Array = []

func reconcile(records: Dictionary) -> void:
	for id in controllers.keys():
		var record: Dictionary = records.get(id, {})
		if record.is_empty() or record.get("remembered", false) or record.get("category", "") != "unit":
			controllers[id].release(); controllers.erase(id)

func present(record: Dictionary, body: Node3D, color: Color, delta: float, running: bool) -> void:
	assert(not record.get("remembered", false) and record.kind in Controller.KINDS)
	if not controllers.has(record.id):
		var controller = Controller.new()
		if not controller.bind(body, record.kind, color): return
		controllers[record.id] = controller
	controllers[record.id].observe(record, delta, running)

func consume_deaths(events: Array, parent: Node3D, blue: Color, red: Color) -> void:
	for event in events:
		# Event contains only death witnessed by faction0. No authority node/target.
		if not event.get("witnessed", false): continue
		if corpses.size() >= MAX_DEATH_VISUALS: _remove_corpse(0)
		var corpse := Node3D.new(); corpse.name = "ObservedDeathOnly"
		parent.add_child(corpse); corpse.position = event.pos; corpse.rotation.y = event.yaw
		var controller = Controller.new()
		if not controller.bind(corpse,event.kind,red if event.team==1 else blue):
			corpse.free(); continue
		controller.start_death()
		corpses.append({"node":corpse,"controller":controller,"pos":event.pos,"team":event.team})

func update_deaths(delta: float, running: bool, visible_at: Callable) -> void:
	for i in range(corpses.size()-1,-1,-1):
		var corpse: Dictionary = corpses[i]
		# A corpse must disappear when its last observed cell enters fog.
		if corpse.team != 0 and not visible_at.call(corpse.pos): _remove_corpse(i); continue
		corpse.controller.advance_death(delta,running)
		if corpse.controller.finished: _remove_corpse(i)

func _remove_corpse(index: int) -> void:
	var corpse: Dictionary = corpses[index]
	corpse.controller.release(); corpse.node.free(); corpses.remove_at(index)

func occlusion_candidates() -> Array:
	# Hook only. A separately reviewed depth/occlusion pass may use these currently
	# authorized rigs. No through-fog shader is implemented or claimed here.
	var result: Array = []
	for controller in controllers.values():
		if is_instance_valid(controller.rig) and controller.rig.is_visible_in_tree(): result.append(controller.rig)
	return result

func visual_evidence_snapshot() -> Dictionary:
	var live: Dictionary = {}
	for id in controllers:
		if is_instance_valid(controllers[id].rig) and controllers[id].rig.is_visible_in_tree(): live[str(id)] = controllers[id].visual_evidence_snapshot()
	var deaths: Array = []
	for corpse in corpses:
		if corpse.node.is_visible_in_tree(): deaths.append(corpse.controller.visual_evidence_snapshot())
	return {"live":live,"deaths":deaths,"death_visual_cap":MAX_DEATH_VISUALS}

func clear() -> void:
	for controller in controllers.values(): controller.release()
	controllers.clear()
	while not corpses.is_empty(): _remove_corpse(corpses.size()-1)
