extends SceneTree
# Deterministic gesture lifetime checks against product handlers, not device input.
class Fixture:
 extends "res://scripts/game.gd"
 var now=1000
 var pans=[]
 var taps=[]
 var boxes=[]
 var world_ok=true
 func _touch_hold_clock(): return now
 func _pan_camera(pixels): pans.append(pixels)
 func _tap(point,touch): taps.append([point,touch])
 func _release_world_camera_focus(): pass
 func _track_camera_key(_event,_viewport): pass
 func _track_action_scroll(_event,_viewport): pass
 func _update_hud(): pass
 func _world_at(point): return Vector3(point.x,0,point.y)
 func _box_point_in_world(_point): return world_ok
 func _box_selection_ids(rect): boxes.append(rect); return [42,43]
 func _select(ids): selected=ids.duplicate()
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok: push_error(label)
func fixture():
 var g=Fixture.new();g.drag_rect=ReferenceRect.new();g.selected=[42];return g
func send(g,event,world=true):
 var viewport=SubViewport.new();root.add_child(viewport)
 g._track_pointer_input(event,viewport)
 if world and not viewport.is_input_handled(): g._unhandled_input(event)
 viewport.free()
func touch(g,id,p,pressed,world=true,canceled=false):
 var e=InputEventScreenTouch.new();e.index=id;e.position=p;e.pressed=pressed;e.canceled=canceled;send(g,e,world)
func drag(g,id,p,relative):
 var e=InputEventScreenDrag.new();e.index=id;e.position=p;e.relative=relative;send(g,e)
func dispose(g): g._clear_touch_hold();g.drag_rect.free();g.free()
func _initialize():
 var origin=Vector2(100,100)
 var g=fixture();touch(g,0,origin,true);g.now+=349;touch(g,0,origin,false)
 check("short stationary press remains contextual tap",g.taps.size()==1 and g.boxes.is_empty());dispose(g)
 g=fixture();touch(g,0,origin,true);g.now+=350;touch(g,0,origin,false)
 check("long hold alone cannot issue movement",g.taps.is_empty() and g.boxes.is_empty() and g.selected==[42]);dispose(g)
 g=fixture();touch(g,0,origin,true);g.now+=349;drag(g,0,origin+Vector2(20,20),Vector2(20,20));g.now+=100;drag(g,0,origin+Vector2(60,60),Vector2(40,40));touch(g,0,origin,false)
 check("early single swipe cannot pan or arm later",g.pans.is_empty() and g.boxes.is_empty() and g.taps.is_empty());dispose(g)
 for delta in [Vector2(60,50),Vector2(-60,50),Vector2(60,-50),Vector2(-60,-50)]:
  g=fixture();touch(g,0,origin,true);g.now+=350;drag(g,0,origin+delta,delta)
  check("hold shows rectangle "+str(delta),g.touch_box_automatic and g.drag_rect.visible and g.drag_rect.get_rect()==Rect2(origin,delta).abs())
  touch(g,0,origin+delta,false)
  check("hold selects units without mode button "+str(delta),g.selected==[42,43] and g.boxes.size()==1 and g.pans.is_empty() and g.taps.is_empty() and not g.touch_box_automatic and g.touch_hold.is_empty());dispose(g)
 g=fixture();touch(g,0,origin,true);g.now+=100;drag(g,0,origin+Vector2(5,5),Vector2(5,5));g.now+=250;drag(g,0,origin+Vector2(30,30),Vector2(25,25));touch(g,0,origin+Vector2(30,30),false)
 check("small hold jitter keeps original box anchor",g.boxes.size()==1 and g.boxes[0].position==origin);dispose(g)
 g=fixture();touch(g,0,origin,true);g.now+=400;drag(g,0,origin+Vector2(30,30),Vector2(30,30));touch(g,1,origin+Vector2(80,0),true)
 check("second finger cancels automatic rectangle",not g.touch_box_automatic and g.touch_hold.is_empty() and not g.drag_rect.visible)
 drag(g,1,origin+Vector2(90,0),Vector2(10,0));check("two fingers pan map",g.pans.size()==1)
 touch(g,1,origin+Vector2(90,0),false);var pan_count=g.pans.size();drag(g,0,origin+Vector2(35,35),Vector2(5,5));touch(g,0,origin+Vector2(35,35),false)
 check("two to one stays inert until full release",g.pans.size()==pan_count and g.taps.is_empty() and g.boxes.is_empty() and g.selected==[42]);dispose(g)
 g=fixture();touch(g,0,origin,true);g.now+=400;g.world_ok=false;drag(g,0,origin+Vector2(30,30),Vector2(30,30));touch(g,0,origin+Vector2(30,30),false)
 check("HUD boundary cancels pending hold",g.touch_hold.is_empty() and g.boxes.is_empty() and g.taps.is_empty());dispose(g)
 g=fixture();touch(g,0,origin,true);g.now+=400;drag(g,0,origin+Vector2(30,30),Vector2(30,30));touch(g,0,origin+Vector2(30,30),false,true,true)
 check("canceled release cannot select or order",g.boxes.is_empty() and g.taps.is_empty() and not g.touch_box_automatic);dispose(g)
 g=fixture();touch(g,0,origin,true);var old=g.touch_press_epochs[0];touch(g,0,origin,false);touch(g,0,origin,true);g._cleanup_touch_release(0,old)
 check("old cleanup preserves reused press hold",not g.touch_hold.is_empty() and g.touch_hold.epoch==g.touch_press_epochs[0]);dispose(g)
 g=fixture();touch(g,0,origin,true);g.now+=400;g._cancel_pointer_streams();drag(g,0,origin+Vector2(30,30),Vector2(30,30));touch(g,0,origin,false)
 check("global cancellation clears hold and ignores late input",g.touch_hold.is_empty() and g.boxes.is_empty() and g.taps.is_empty());dispose(g)
 g=fixture();touch(g,0,origin,true,false);g.now+=400;drag(g,0,origin+Vector2(30,30),Vector2(30,30));touch(g,0,origin,false,false)
 check("GUI owned press never arms world box",g.touch_hold.is_empty() and g.boxes.is_empty() and g.pans.is_empty());dispose(g)
 g=fixture();g.build_mode="house";touch(g,0,origin,true);g.now+=400;drag(g,0,origin+Vector2(30,30),Vector2(30,30))
 check("build preview retains one finger drag",g.build_preview_held and not g.touch_box_automatic and g.pans.is_empty());dispose(g)
 g=fixture();var accumulated=Input.use_accumulated_input;touch(g,0,origin,true)
 check("hold preserves raw drag boundary samples",not Input.use_accumulated_input)
 g.now+=350;drag(g,0,origin+Vector2(30,30),Vector2(30,30));drag(g,0,origin,Vector2(-30,-30));touch(g,0,origin,false)
 check("zero area hold preserves selection without order",g.selected==[42] and g.boxes.is_empty() and g.taps.is_empty())
 check("hold completion restores input accumulation",Input.use_accumulated_input==accumulated);dispose(g)
 print("HOLD_BOX_CONTRACT "+JSON.stringify(checks));quit(0 if checks.all(func(c):return c.passed) else 1)
