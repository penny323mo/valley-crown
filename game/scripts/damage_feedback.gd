extends RefCounted
## Detached presentation of witnessed settled HP loss. No entity references.
const MAX_CUES=24
const LIFETIME=1.1
var cues=[]
func add(parent: Node3D,position: Vector3,amount: int,owned: bool,lethal: bool):
	if amount<=0 or not position.is_finite():return
	while cues.size()>=MAX_CUES:discard(0)
	var label=Label3D.new();label.name="SettledDamageCue"
	label.font=load("res://assets/fonts/ui_tc.otf")
	label.font_size=38 if lethal else 32;label.outline_size=8;label.pixel_size=0.016
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=false;label.shaded=false
	label.modulate=Color("ffbdad") if owned else Color("ffe0a0")
	label.outline_modulate=Color("221c19")
	label.text=("-%d\n擊破" if lethal else "-%d") % amount
	parent.add_child(label);label.position=position+Vector3(0,2.5,0)
	cues.append({"node":label,"origin":position,"owned":owned,"age":0.0,"lethal":lethal})
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
		if running:cue.age+=elapsed
		if cue.age>=LIFETIME:discard(index);continue
		cue.node.position=cue.origin+Vector3(0,2.5+cue.age*0.8,0)
		cue.node.modulate.a=1.0-clampf((cue.age-0.65)/(LIFETIME-0.65),0.0,1.0)
