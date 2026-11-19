extends RefCounted
## Detached presentation of witnessed settled HP loss. No entity references.
const MAX_CUES=24
const MAX_GROUP_HITS=12
const LIFETIME=1.1
const MERGE_UNTIL=0.44
const GROUP_RADIUS_SQUARED=4.0
# Camera right for the fixed battlefield azimuth (23, 0, -19).
const SCREEN_SIDE=Vector3(0.7704,0,-0.6368)
var cues=[]

func _label(cue: Dictionary) -> void:
	var amount=0
	var knockouts=0
	for hit in cue.hits:
		amount+=hit.amount
		knockouts+=int(hit.lethal)
	var label:Label3D=cue.node
	label.font_size=33 if knockouts>0 else 30
	label.text=("總 -%d" if cue.hits.size()>1 else "-%d") % amount
	if knockouts>0:
		label.text+=("\n擊倒 ×%d" % knockouts) if knockouts>1 else "\n擊倒"

func _position(cue:Dictionary) -> Vector3:
	var side=-0.38 if cue.owned else 0.38
	return cue.origin+SCREEN_SIDE*side+Vector3(0,2.5+cue.age*0.8,0)

func add(parent: Node3D,position: Vector3,amount: int,owned: bool,lethal: bool):
	if amount<=0 or not position.is_finite():return
	var hit={"position":position,"amount":amount,"lethal":lethal}
	var best=-1
	var distance=GROUP_RADIUS_SQUARED
	for index in range(cues.size()-1,-1,-1):
		var old=cues[index]
		if old.owned!=owned or old.age>MERGE_UNTIL or old.hits.size()>=MAX_GROUP_HITS:continue
		var d:float=old.origin.distance_squared_to(position)
		if d<=distance:
			best=index
			distance=d
	if best>=0:
		var cue=cues[best]
		cue.hits.append(hit)
		_label(cue)
		return
	while cues.size()>=MAX_CUES:discard(0)
	var label=Label3D.new();label.name="SettledDamageCue"
	label.font=load("res://assets/fonts/ui_tc.otf")
	label.outline_size=8;label.pixel_size=0.013
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=false;label.shaded=false
	label.modulate=Color("ffbdad") if owned else Color("ffe0a0")
	label.outline_modulate=Color("221c19")
	parent.add_child(label)
	var cue={"node":label,"origin":position,"owned":owned,"age":0.0,"hits":[hit]}
	cues.append(cue)
	_label(cue)
	label.position=_position(cue)

func discard(index: int):
	var node=cues[index].node
	if is_instance_valid(node):node.visible=false;node.queue_free()
	cues.remove_at(index)

func clear():
	while not cues.is_empty():discard(cues.size()-1)

func update(delta: float,running: bool,ended: bool,visible: Callable):
	if ended:clear();return
	var elapsed=clampf(delta,0.0,0.1) if is_finite(delta) else 0.0
	for index in range(cues.size()-1,-1,-1):
		var cue=cues[index]
		if not is_instance_valid(cue.node) or (not cue.owned and not visible.call(cue.origin)):discard(index);continue
		# Never carry hidden enemy numbers forward in a still-visible group.
		# Pruned events are not restored when a cell becomes visible again.
		if not cue.owned:
			var old_count:int=cue.hits.size()
			cue.hits=cue.hits.filter(func(hit):return visible.call(hit.position))
			if cue.hits.is_empty():discard(index);continue
			if cue.hits.size()!=old_count:_label(cue)
		if running:cue.age+=elapsed
		if cue.age>=LIFETIME:discard(index);continue
		cue.node.position=_position(cue)
		cue.node.modulate.a=1.0-clampf((cue.age-0.65)/(LIFETIME-0.65),0.0,1.0)
