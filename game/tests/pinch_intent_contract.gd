extends SceneTree
## ENGINE_UNRUN. Synthetic input events passed to actual tracking/world handlers.
## Camera/picking/HUD outputs are captured, not rendered or routed device proof.
class Fixture:
	extends "res://scripts/game.gd"
	var pans=[]
	var taps=[]
	var boxes=[]
	func _pan_camera(pixels): pans.append(pixels)
	func _tap(point,touch): taps.append([point,touch])
	func _release_world_camera_focus(): pass
	func _track_camera_key(_event,_viewport): pass
	func _track_action_scroll(_event,_viewport): pass
	func _update_hud(): pass
	func _world_at(point): return Vector3(point.x,0,point.y)
	func _box_point_in_world(_point): return true
	func _box_selection_ids(rect): boxes.append(rect); return [42]
	func _select(ids): selected=ids.duplicate()
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func fixture():
	var g=Fixture.new(); g.drag_rect=ReferenceRect.new(); g.selected=[42]
	return g
func send(g,event,world=true):
	# Fresh viewport models unhandled state for each isolated synthetic event.
	var viewport=SubViewport.new(); root.add_child(viewport)
	g._track_pointer_input(event,viewport)
	if world and not viewport.is_input_handled():
		if g.game_over:g._aftermath_input(event) # Inner route avoids unattached fixture viewport.
		else:g._unhandled_input(event)
	viewport.free()
func touch(g,id,point,pressed,world=true):
	var e=InputEventScreenTouch.new();e.index=id;e.position=point;e.pressed=pressed
	send(g,e,world)
func drag(g,id,point,relative,world=true):
	var e=InputEventScreenDrag.new();e.index=id;e.position=point;e.relative=relative
	send(g,e,world)
func dispose(g):
	g.drag_rect.free();g.free()
func trio(g):
	touch(g,0,Vector2(100,100),true);touch(g,1,Vector2(200,100),true);touch(g,2,Vector2(400,100),true)
func _initialize():
	var baseline="--baseline" in OS.get_cmdline_user_args()
	var g=fixture()
	touch(g,0,Vector2(100,100),true);touch(g,1,Vector2(300,100),true)
	var max_zoom_drift=0.0
	for i in range(1,21):
		drag(g,0,Vector2(100+i*3,100),Vector2(3,0))
		max_zoom_drift=maxf(max_zoom_drift,absf(g.camera_zoom-30))
		drag(g,1,Vector2(300+i*3+(2 if i%2 else -2),100),Vector2(3,0))
		max_zoom_drift=maxf(max_zoom_drift,absf(g.camera_zoom-30))
	print("PAN_JITTER_MAX_ZOOM_DRIFT "+str(max_zoom_drift))
	check("baseline reproduces zoom or candidate rejects small span jitter",max_zoom_drift>0.1 if baseline else is_zero_approx(max_zoom_drift))
	var total=Vector2.ZERO
	for pan in g.pans:total+=pan
	check("pan follows centroid despite no zoom",total==Vector2(-59,0))
	check("gesture sends no commands or selections",g.commands.is_empty() and g.selected==[42] and g.taps.is_empty())
	dispose(g)
	if not baseline:
		for sign in [-1,1]:
			g=fixture();touch(g,0,Vector2(100,100),true);touch(g,1,Vector2(300,100),true)
			for step in range(1,7):drag(g,1,Vector2(300+sign*step*2,100),Vector2(sign*2,0))
			check("cumulative threshold remains quiet "+str(sign),g.touch_pinch_anchor_distance==200 and g.camera_zoom==30)
			drag(g,1,Vector2(300+sign*14,100),Vector2(sign*2,0))
			check("deliberate pinch activates without jump "+str(sign),absf(g.camera_zoom-30)<0.5 and not is_equal_approx(g.camera_zoom,30.0))
			drag(g,1,Vector2(300+sign*24,100),Vector2(sign*10,0))
			check("pinch zoom continues proportionally "+str(sign),is_equal_approx(g.camera_zoom,30.0*200.0/(200+sign*(24-12))))
			g._cancel_pointer_streams()
			check("cancel resets pinch intent "+str(sign),g.touch_pinch_anchor_distance==0 and is_equal_approx(g.touch_pinch_anchor_zoom,g.camera_zoom))
			dispose(g)
		g=fixture();touch(g,0,Vector2(100,100),true);touch(g,1,Vector2(300,100),true)
		drag(g,1,Vector2(320,100),Vector2(20,0));drag(g,1,Vector2(1000,100),Vector2(680,0))
		check("zoom minimum is preserved",g.camera_zoom==15)
		drag(g,1,Vector2(101,100),Vector2(-899,0))
		check("zoom maximum is preserved",g.camera_zoom==46)
		touch(g,1,Vector2(101,100),false);touch(g,2,Vector2(300,100),true)
		drag(g,2,Vector2(305,100),Vector2(5,0))
		check("new pair resets active pinch and span without zoom jump",g.touch_pinch_anchor_distance==200 and g.camera_zoom==46)
		dispose(g)
		g=fixture();g.game_over=true;g.aftermath_view=true
		touch(g,0,Vector2(100,100),true);touch(g,1,Vector2(300,100),true)
		drag(g,0,Vector2(104,100),Vector2(4,0));drag(g,1,Vector2(305,100),Vector2(5,0))
		check("aftermath uses same no-jitter gate",g.camera_zoom==30 and g.pans==[Vector2(-2,0),Vector2(-2.5,0)])
		drag(g,1,Vector2(325,100),Vector2(20,0))
		check("aftermath activation has no jump",is_equal_approx(g.camera_zoom,30.0*200.0/209.0))
		drag(g,1,Vector2(345,100),Vector2(20,0))
		check("aftermath deliberate pinch works",g.camera_zoom<30)
		dispose(g)
	var failures=checks.filter(func(row):return not row.passed)
	print(JSON.stringify({"suite":"pinch_intent_contract","checks":checks,"failed":failures.size(),"scope":"synthetic native input callbacks; not phone acceptance"}))
	quit(0 if failures.is_empty() else 1)
