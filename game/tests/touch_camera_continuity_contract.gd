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
	if world and not viewport.is_input_handled(): g._unhandled_input(event)
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
	var g=fixture()
	touch(g,0,Vector2(100,100),true)
	drag(g,0,Vector2(120,100),Vector2(20,0))
	drag(g,0,Vector2(110,100),Vector2(-10,0))
	drag(g,0,Vector2(100,100),Vector2(-10,0))
	check("owned pan follows back through original slop circle",g.pans==[Vector2(-20,0),Vector2(10,0),Vector2(10,0)])
	touch(g,0,Vector2(100,100),false)
	check("returned gesture cannot become a tap/order",g.taps.is_empty() and g.commands.is_empty() and g.selected==[42])
	dispose(g)
	for world_release in [true,false]:
		g=fixture();trio(g)
		var epoch=g.touch_press_epochs[0]
		touch(g,0,Vector2(100,100),false,world_release)
		drag(g,2,Vector2(410,100),Vector2(10,0))
		check("3 to 2 rebases without jump "+str(world_release),g.pans==[Vector2(-5,0)] and is_equal_approx(g.camera_zoom,30.0*200.0/210.0))
		check("released GUI/world ID excluded from camera pair",g.touch_camera_pair==[[1,g.touch_press_epochs[1]],[2,g.touch_press_epochs[2]]])
		g._cleanup_touch_release(0,epoch)
		check("deferred cleanup preserves active pair",g.touch_camera_pair==[[1,g.touch_press_epochs[1]],[2,g.touch_press_epochs[2]]])
		dispose(g)
	g=fixture();trio(g)
	var old_epoch=g.touch_press_epochs[0]
	touch(g,0,Vector2(100,100),false,false)
	touch(g,0,Vector2(900,100),true,false)
	drag(g,0,Vector2(910,100),Vector2(10,0))
	check("reused GUI ID cannot drag retained old world point",g.pans.is_empty() and g.touch_points[0]==Vector2(100,100))
	drag(g,2,Vector2(410,100),Vector2(10,0))
	check("GUI reuse cannot contaminate pinch pair",g.pans==[Vector2(-5,0)] and is_equal_approx(g.camera_zoom,30.0*200.0/210.0))
	g._cleanup_touch_release(0,old_epoch)
	check("old cleanup cannot erase newer press epoch",g.touch_press_epochs[0]!=old_epoch and 0 in g.all_touch_ids)
	dispose(g)
	g=fixture()
	touch(g,0,Vector2(100,100),true);touch(g,1,Vector2(200,100),true)
	old_epoch=g.touch_press_epochs[0]
	touch(g,0,Vector2(100,100),false,false);touch(g,0,Vector2(400,100),true)
	g._cleanup_touch_release(0,old_epoch)
	drag(g,0,Vector2(410,100),Vector2(10,0))
	check("reused world ID rebases to new press lifetime",g.pans==[Vector2(-5,0)] and is_equal_approx(g.camera_zoom,30.0*200.0/210.0) and g.touch_world_epochs[0]==g.touch_press_epochs[0])
	dispose(g)
	g=fixture();trio(g)
	drag(g,2,Vector2(410,100),Vector2(10,0))
	check("third finger outside selected pair has no camera effect",g.pans==[Vector2.ZERO] and g.camera_zoom==30)
	touch(g,2,Vector2(410,100),false);touch(g,1,Vector2(200,100),false)
	drag(g,0,Vector2(105,100),Vector2(5,0))
	check("two to one gesture remains owned inside tap slop",g.pans[-1]==Vector2(-5,0) and g.touch_gesture)
	g._cancel_pointer_streams()
	check("cancel clears both new ownership records",g.touch_world_epochs.is_empty() and g.touch_camera_pair.is_empty() and g.touch_points.is_empty())
	dispose(g)
	g=fixture()
	touch(g,0,Vector2(100,100),true);drag(g,0,Vector2(105,100),Vector2(5,0));touch(g,0,Vector2(105,100),false)
	check("ordinary small movement remains one tap",g.pans.is_empty() and g.taps.size()==1)
	dispose(g)
	g=fixture();g.build_mode="house"
	touch(g,0,Vector2(100,100),true);drag(g,0,Vector2(130,100),Vector2(30,0))
	check("one-finger build preview remains owner",g.build_preview_held and g.pans.is_empty() and g.commands.is_empty())
	dispose(g)
	g=fixture();g.box_select_mode=true
	touch(g,0,Vector2(100,100),true);drag(g,0,Vector2(130,130),Vector2(30,30));touch(g,0,Vector2(130,130),false)
	check("explicit box drag stays selection not camera",g.boxes.size()==1 and g.pans.is_empty() and g.taps.is_empty())
	dispose(g)
	var failures=checks.filter(func(row):return not row.passed)
	print("TOUCH_CAMERA_CONTINUITY "+JSON.stringify({"scope":"synthetic callbacks with captured camera/picking; ENGINE_UNRUN at preparation","checks":checks,"failure_count":failures.size()}))
	quit(0 if failures.is_empty() else 1)
