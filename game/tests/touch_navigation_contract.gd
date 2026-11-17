extends "res://tests/contextual_touch_phone.gd"
func hold():
 var t=Time.get_ticks_msec()
 while Time.get_ticks_msec()-t<380:
  await process_frame;OS.delay_msec(1)
func run():
 root.size=Vector2i(390,844)
 game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game._test_reset();await settle()
 var worker=game._first(0,"villager");game._select([worker.id]);await settle()
 var p=Vector2.ZERO
 for y in range(180,400,25):
  for x in range(60,270,25):
   var q=Vector2(x,y)
   if game._box_point_in_world(q) and game._pick(q)<0:p=q;break
  if p!=Vector2.ZERO:break
 check("world point exists",p!=Vector2.ZERO)
 touch(p,true);await hold();touch(p,false);await settle()
 check("slow stationary press issues one contextual order",game.commands.size()==1 and game.commands[0].type=="order" and game.commands[0].ids==[worker.id])
 game.commands.clear();var focus=game.camera_focus;var selected=game.selected.duplicate()
 touch(p,true);drag(p+Vector2(25,25),Vector2(25,25));drag(p+Vector2(55,55),Vector2(30,30));await settle()
 check("quick single drag displays box from original anchor",game.touch_box_automatic and game.drag_rect.visible and game.drag_rect.get_rect()==Rect2(p,Vector2(55,55)))
 var expected=game._box_selection_ids(Rect2(p,Vector2(55,55)))
 var count=game.drag_rect.get_node_or_null("SelectionCount")
 check("box preview displays actual owned visible selection count",count!=null and count.text==str(expected.size()) and count.mouse_filter==Control.MOUSE_FILTER_IGNORE)
 touch(p+Vector2(55,55),false);await settle()
 check("quick single drag never pans camera",game.camera_focus==focus)
 check("box release selects rectangle without order",game.commands.is_empty() and game.selected==expected)
 touch(p,true);drag(p+Vector2(25,0),Vector2(25,0));touch(p+Vector2(90,0),true,1);var second=game.camera_focus
 drag(p+Vector2(35,0),Vector2(10,0));drag(p+Vector2(100,0),Vector2(10,0),1);await settle()
 check("second finger hands off to paired camera",game.camera_focus!=second and game.commands.is_empty())
 touch(p+Vector2(100,0),false,1);focus=game.camera_focus;drag(p+Vector2(65,0),Vector2(30,0));touch(p+Vector2(65,0),false);await settle()
 check("pinch remaining finger cannot resume box or order",game.camera_focus==focus and game.commands.is_empty())
 touch(p,true);drag(p+Vector2(25,0),Vector2(25,0));game._cancel_pointer_streams();focus=game.camera_focus;drag(p+Vector2(55,0),Vector2(30,0));touch(p,false);await settle()
 check("cancel quarantines late box and release",game.camera_focus==focus and game.commands.is_empty())
 touch(p,true);await hold();touch(p,false,0,true);await settle()
 check("slow canceled release never issues order",game.commands.is_empty())
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"touch_navigation_contract","checks":checks,"failed":failed,"scope":"Native viewport-routed synthetic touch with real monotonic hold clock; not physical-device acceptance."}));quit(1 if failed else 0)
