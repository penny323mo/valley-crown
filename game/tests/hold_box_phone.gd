extends "res://tests/contextual_touch_phone.gd"
# Real viewport event routing and real clock, not physical-phone acceptance.
func run():
 root.size=Vector2i(390,844)
 game=load("res://main.tscn").instantiate();root.add_child(game)
 game.set_process(false);game.test_mode=true;game._test_reset();await settle()
 var points=[]
 for e in game.faction_views[0].records().values():
  if e.owned and e.category=="unit" and e.kind=="villager":
   var p=game.camera.unproject_position(e.pos+Vector3(0,0.6,0))
   if game._box_point_in_world(p):points.append(p)
 check("visible worker group exists",points.size()>=2)
 if points.size()<2:finish_hold();return
 var rect=Rect2(points[0],Vector2.ZERO)
 for p in points:rect=rect.expand(p)
 rect=rect.grow(6)
 var first=rect.position;var last=rect.end
 check("box endpoints are battlefield",game._box_point_in_world(first) and game._box_point_in_world(last))
 var expected=game._box_selection_ids(rect);var before=game.camera_focus
 touch(first,true);await create_timer(0.37).timeout
 drag(last,last-first);await settle()
 check("hold drag shows rectangle without menu",game.drag_rect.visible and game.touch_box_automatic and not game.box_select_mode)
 touch(last,false);await settle()
 check("release selects actual boxed units",game.selected==expected and expected.size()>=2)
 check("box gesture issues no movement and does not pan",game.commands.is_empty() and game.camera_focus==before)
 check("box release clears transient ownership",not game.touch_box_automatic and game.touch_hold.is_empty() and not game.drag_rect.visible)
 # Contextual tap after box must act on the selected group, not require mode.
 var point=Vector2.ZERO
 for y in range(180,460,25):
  for x in range(45,345,25):
   var candidate=Vector2(x,y)
   if game._pick(candidate)<0:point=candidate;break
  if point!=Vector2.ZERO:break
 await tap(point)
 check("selected group next tap moves once",game.commands.size()==1 and game.commands[0].ids==expected and game.commands[0].target==-1 and not game.touch_command)
 game.commands.clear();before=game.camera_focus
 touch(point,true);drag(point+Vector2(40,0),Vector2(40,0));touch(point+Vector2(40,0),false);await settle()
 check("quick single swipe neither pans nor orders",game.camera_focus==before and game.commands.is_empty())
 touch(point,true);touch(point+Vector2(70,0),true,1);drag(point+Vector2(20,0),Vector2(20,0));drag(point+Vector2(90,0),Vector2(20,0),1);await settle()
 check("two finger drag pans",game.camera_focus!=before and game.commands.is_empty())
 touch(point+Vector2(90,0),false,1);before=game.camera_focus
 drag(point+Vector2(40,0),Vector2(20,0));touch(point+Vector2(40,0),false);await settle()
 check("last pinch finger cannot pan or emit order",game.camera_focus==before and game.commands.is_empty())
 # UI ownership and scroll protections remain real routed checks.
 await check_action_scroll_release()
 finish_hold()
func finish_hold():
 print("HOLD_BOX_PHONE "+JSON.stringify(checks));quit(0 if checks.all(func(c):return c.passed) else 1)
