extends SceneTree
# ENGINE_UNRUN. Synthetic tracker/world/minimap calls, not native GUI dispatch,
# rendered layout, browser, physical phone or natural combat proof.
class GameFixture:
	extends "res://scripts/game.gd"
	var taps=[]
	var pans=[]
	func _release_world_camera_focus(): pass
	func _track_camera_key(_event,_viewport): pass
	func _track_action_scroll(_event,_viewport): pass
	func _update_hud(): pass
	func _tap(point,touch): taps.append([point,touch])
	func _pan_camera(pixels): pans.append(pixels)
class MapFixture:
	extends "res://scripts/minimap.gd"
	func _draw(): pass # Fixture never renders the world or fake screenshot.
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func setup():
	var game=GameFixture.new(); game.drag_rect=ReferenceRect.new(); game.selected=[42]
	var viewport=SubViewport.new(); root.add_child(viewport)
	var map=MapFixture.new(); map.game=game; map.size=Vector2(178,178); viewport.add_child(map)
	return {"game":game,"viewport":viewport,"map":map}
func dispose(f):
	f.viewport.free(); f.game.drag_rect.free(); f.game.free()
func touch(id,point,pressed=true):
	var e=InputEventScreenTouch.new(); e.index=id; e.position=point; e.pressed=pressed; return e
func track(f,event,world=false):
	f.game._track_pointer_input(event,f.viewport)
	if world: f.game._unhandled_input(event)
func release(f,id,point,world=false):
	var epoch=f.game.touch_press_epochs.get(id,-1)
	track(f,touch(id,point,false),world)
	# Force the ordinary deferred cleanup boundary explicitly in this fixture.
	f.game._cleanup_touch_release(id,epoch); f.game._cleanup_button_touch(id,epoch)
func _initialize():
	for world_first in [true,false]:
		var f=setup(); var g=f.game
		var first=touch(4,Vector2(100,100)); track(f,first,world_first)
		g.camera_focus=Vector3(3,0,4)
		var second=touch(7,Vector2(150,150)); track(f,second)
		check("tracker owns both touches before map "+str(world_first),g.all_touch_ids==[4,7] and g.touch_gesture)
		var old=g.camera_focus; f.map._gui_input(second)
		check("second minimap finger cannot teleport camera "+str(world_first),g.camera_focus==old and f.viewport.is_input_handled())
		check("minimap suppression cannot command "+str(world_first),g.commands.is_empty() and g.selected==[42])
		release(f,7,second.position)
		check("remaining held finger retains gesture quarantine "+str(world_first),g.touch_gesture and g.all_touch_ids==[4])
		release(f,4,first.position,world_first)
		check("final release cannot become world tap "+str(world_first),g.taps.is_empty() and g.commands.is_empty())
		var fresh=touch(7,Vector2(129,49)); track(f,fresh); f.map._gui_input(fresh)
		check("fresh sole touch recenters after cleanup "+str(world_first),g.camera_focus.is_equal_approx(Vector3(20,0,-20)))
		dispose(f)
	for point in [Vector2(9,9),Vector2(89,89),Vector2(169,169),Vector2(0,178)]:
		var f=setup(); var e=touch(2,point); track(f,e); f.map._gui_input(e)
		var uv=(point-Vector2(9,9))/Vector2(160,160)
		var expected=Vector3(clampf(uv.x*80-40,-35,35),0,clampf(uv.y*80-40,-35,35))
		check("single touch mapping and clamp "+str(point),f.game.camera_focus.is_equal_approx(expected))
		dispose(f)
	var f=setup(); var g=f.game; g.camera_focus=Vector3(3,0,4)
	# Direct invalid-counter controls are predicate coverage, not routed events.
	g.all_touch_ids=[2]; g.touch_gesture=true; f.map._gui_input(touch(2,Vector2(150,150)))
	check("latched gesture cannot recenter",g.camera_focus==Vector3(3,0,4))
	g.touch_gesture=false; f.map._gui_input(touch(9,Vector2(150,150)))
	check("unowned ID cannot recenter",g.camera_focus==Vector3(3,0,4))
	g.all_touch_ids.clear(); f.map._gui_input(touch(2,Vector2(150,150)))
	check("untracked touch cannot recenter",g.camera_focus==Vector3(3,0,4))
	var mouse=InputEventMouseButton.new(); mouse.button_index=MOUSE_BUTTON_LEFT; mouse.pressed=true; mouse.position=Vector2(129,49)
	f.map._gui_input(mouse)
	check("ordinary mouse mapping unchanged",g.camera_focus.is_equal_approx(Vector3(20,0,-20)))
	var old=g.camera_focus
	mouse.pressed=false; mouse.position=Vector2(150,150); f.map._gui_input(mouse)
	f.map._gui_input(touch(2,Vector2(150,150),false))
	var drag=InputEventScreenDrag.new(); drag.index=2; drag.position=Vector2(150,150); f.map._gui_input(drag)
	check("mouse release, touch release and drag do not recenter",g.camera_focus==old)
	dispose(f)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"minimap_touch_ownership_contract","checks":checks,"failed":failed,"scope":"Synthetic tracker/world/minimap handlers, not GUI routing or phone","source_sha256":FileAccess.get_sha256("res://scripts/minimap.gd")}))
	quit(1 if failed else 0)
