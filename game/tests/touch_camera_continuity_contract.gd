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
	# Count completed selection only; actual preview/query is covered by routed touch_navigation_contract.
	func _show_box_preview(rect):
		drag_rect.position=rect.position;drag_rect.size=rect.size;drag_rect.show()
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
func _zoom_regression():
	# Exercise order-dependent browser events using the same real routing.
	for span in [58,116,194]:
		for angle in [0.0,0.75,1.57]:
			for reverse in [false,true]:
				var g=fixture()
				var a=Vector2(140,220); var b=a+Vector2(span,0).rotated(angle)
				var drift=Vector2(span*0.44,18).rotated(angle)
				touch(g,0,a,true);touch(g,1,b,true)
				if reverse:
					drag(g,1,b+drift,drift);drag(g,0,a+drift,drift)
				else:
					drag(g,0,a+drift,drift);drag(g,1,b+drift,drift)
				check("parallel touch span/angle/order %d %.2f %s" % [span,angle,str(reverse)],is_equal_approx(g.camera_zoom,30.0) and (g.pans[0]+g.pans[1]).is_equal_approx(-drift) and g.selected==[42] and g.taps.is_empty())
				touch(g,0,a+drift,false);touch(g,1,b+drift,false);dispose(g)
	var g=fixture()
	var a=Vector2(155,220);var b=Vector2(295,220)
	touch(g,0,a,true);touch(g,1,b,true)
	drag(g,0,a+Vector2(10,0),Vector2(10,0))
	check("dead zone ignores tiny jitter",is_equal_approx(g.camera_zoom,30.0))
	drag(g,0,a+Vector2(12.1,0),Vector2(2.1,0))
	check("continuous onset beyond the deadzone",g.camera_zoom>30.0 and g.camera_zoom<30.1)
	drag(g,0,a-Vector2(42,0),Vector2(-54.1,0))
	drag(g,1,b+Vector2(56,0),Vector2(56,0))
	check("true spread with shifted centroid zooms in",g.camera_zoom<23 and g.camera_zoom>=15)
	drag(g,0,a,Vector2(42,0));drag(g,1,b,Vector2(-56,0))
	check("same span after true pinch returns exact original zoom",is_equal_approx(g.camera_zoom,30.0))
	drag(g,0,a+Vector2(58,0),Vector2(58,0));drag(g,1,b-Vector2(55,0),Vector2(-55,0))
	check("true squeeze zooms out and is capped",is_equal_approx(g.camera_zoom,46.0))
	drag(g,0,a,Vector2(-58,0));drag(g,1,b,Vector2(55,0))
	check("moves freely back from clamp within the same gesture",is_equal_approx(g.camera_zoom,30.0))
	drag(g,1,b+Vector2(45,0),Vector2(45,0));var held_zoom=g.camera_zoom
	touch(g,1,b+Vector2(45,0),false)
	touch(g,1,b+Vector2(70,0),true)
	drag(g,1,b+Vector2(75,0),Vector2(5,0))
	check("replacement finger inherits actual zoom but rebases span",is_equal_approx(g.camera_zoom,held_zoom))
	g._cancel_pointer_streams()
	drag(g,1,b+Vector2(110,0),Vector2(35,0))
	check("canceled pointer streams cannot change zoom",is_equal_approx(g.camera_zoom,held_zoom) and g.touch_camera_pair.is_empty())
	touch(g,0,a,false);touch(g,1,b,false)
	touch(g,0,a,true);touch(g,1,a,true)
	drag(g,1,a+Vector2(40,0),Vector2(40,0))
	check("coincident touch pair establishes first valid span without zoom",is_equal_approx(g.camera_zoom,held_zoom))
	dispose(g)

func _initialize():
	_zoom_regression()
	var g=fixture()
	touch(g,0,Vector2(100,100),true)
	drag(g,0,Vector2(120,100),Vector2(20,0))
	drag(g,0,Vector2(110,100),Vector2(-10,0))
	drag(g,0,Vector2(100,100),Vector2(-10,0))
	check("single swipe never pans even through original slop circle",g.pans.is_empty())
	touch(g,0,Vector2(100,100),false)
	check("returned gesture cannot become a tap/order",g.taps.is_empty() and g.commands.is_empty() and g.selected==[42])
	dispose(g)
	for world_release in [true,false]:
		g=fixture();trio(g)
		var epoch=g.touch_press_epochs[0]
		touch(g,0,Vector2(100,100),false,world_release)
		drag(g,2,Vector2(410,100),Vector2(10,0))
		check("3 to 2 rebases without jump "+str(world_release),g.pans==[Vector2(-5,0)] and is_equal_approx(g.camera_zoom,30.0))
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
	check("GUI reuse cannot contaminate pinch pair",g.pans==[Vector2(-5,0)] and is_equal_approx(g.camera_zoom,30.0))
	g._cleanup_touch_release(0,old_epoch)
	check("old cleanup cannot erase newer press epoch",g.touch_press_epochs[0]!=old_epoch and 0 in g.all_touch_ids)
	dispose(g)
	g=fixture()
	touch(g,0,Vector2(100,100),true);touch(g,1,Vector2(200,100),true)
	old_epoch=g.touch_press_epochs[0]
	touch(g,0,Vector2(100,100),false,false);touch(g,0,Vector2(400,100),true)
	g._cleanup_touch_release(0,old_epoch)
	drag(g,0,Vector2(410,100),Vector2(10,0))
	check("reused world ID rebases to new press lifetime",g.pans==[Vector2(-5,0)] and is_equal_approx(g.camera_zoom,30.0) and g.touch_world_epochs[0]==g.touch_press_epochs[0])
	dispose(g)
	g=fixture();trio(g)
	drag(g,2,Vector2(410,100),Vector2(10,0))
	check("third finger outside selected pair has no camera effect",g.pans==[Vector2.ZERO] and g.camera_zoom==30)
	touch(g,2,Vector2(410,100),false);touch(g,1,Vector2(200,100),false)
	drag(g,0,Vector2(105,100),Vector2(5,0))
	check("two to one gesture stays quarantined without pan",g.pans==[Vector2.ZERO] and g.touch_gesture)
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
