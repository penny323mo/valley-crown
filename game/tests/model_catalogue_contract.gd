extends SceneTree
const Catalogue=preload("res://scripts/model_catalogue.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func touch(id,down,point,cancelled=false):
 var e=InputEventScreenTouch.new();e.index=id;e.pressed=down;e.position=point;e.canceled=cancelled;return e
func drag(id,point):
 var e=InputEventScreenDrag.new();e.index=id;e.position=point;return e
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(640,360)
 var preview=Catalogue.new();root.add_child(preview);preview.position=Vector2(20,20);preview.size=Vector2(360,230);await process_frame
 check("isolated viewport begins disabled",preview.viewport.own_world_3d and preview.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED)
 var prior=null
 for kind in Rules.UNIT_KINDS+["town_center"]+Rules.BUILDABLE_KINDS:
  var old=preview.pivot
  check(kind+" actual model loads",preview.set_entry(kind) and preview.model_kind==kind and preview.active)
  check(kind+" finite visible mesh bounds",preview.model_bounds.is_finite() and preview.model_bounds.size.length()>0 and preview.pivot.find_children("*","MeshInstance3D",true,false).size()>0)
  check(kind+" replaces prior model without battle",not is_instance_valid(old) and preview.stage.get_node_or_null("CatalogueModel")==preview.pivot)
 check("all sixteen model entries supported",Rules.UNIT_KINDS.size()+1+Rules.BUILDABLE_KINDS.size()==16)
 preview.set_entry("villager");var pose=preview.actor.pose_applications
 for i in 10:preview._process(.05)
 check("walking rig uses real idle animation",preview.actor.clip=="idle" and preview.actor.pose_applications>pose and preview.actor.player.has_animation("idle"))
 var before=preview.yaw;preview.set_yaw(INF);preview.set_yaw(NAN)
 check("nonfinite rotation rejected",preview.yaw==before)
 preview.set_yaw(9000)
 check("rotation remains bounded",preview.yaw>=-PI and preview.yaw<=PI)
 var clip=Rect2(Vector2.ZERO,Vector2(640,360));var point=preview.image.get_global_rect().get_center()
 before=preview.yaw
 check("touch inside preview captured",preview.handle_touch(touch(0,true,point),clip))
 preview.handle_touch(drag(0,point+Vector2(30,0)),clip)
 check("one finger rotates real pivot",preview.yaw!=before and is_equal_approx(preview.pivot.rotation.y,preview.yaw))
 preview.handle_touch(touch(1,true,point),clip);before=preview.yaw
 preview.handle_touch(drag(0,point+Vector2(60,0)),clip)
 check("second finger cancels rotation",preview.blocked and preview.pointer==-1 and preview.yaw==before)
 preview.handle_touch(touch(1,false,point),clip);preview.handle_touch(drag(0,point),clip)
 check("remaining finger cannot restart gesture",preview.yaw==before and preview.pointer==-1)
 preview.handle_touch(touch(0,false,point),clip)
 check("all fingers released unlocks gesture",not preview.blocked and preview.touch_ids.is_empty())
 preview.handle_touch(touch(2,true,point),clip);preview.handle_touch(touch(2,false,point,true),clip)
 check("cancelled touch clears pointer",preview.pointer==-1 and preview.touch_ids.is_empty())
 preview.handle_touch(touch(3,true,point),clip);before=preview.yaw
 preview.handle_touch(drag(3,Vector2(639,359)),clip)
 check("leaving preview cancels without rotation",preview.pointer==-1 and preview.yaw==before)
 preview.handle_touch(touch(3,false,point),clip)
 check("clipped and outside points not captured",not preview.handle_touch(touch(4,true,point),Rect2(0,0,10,10)) and preview.pointer==-1)
 preview.handle_touch(touch(4,false,point),clip)
 preview.handle_touch(touch(5,true,point),clip);preview.cancel_input()
 check("focus or layout cancellation stops gesture",preview.pointer==-1 and preview.blocked)
 preview.handle_touch(touch(5,false,point),clip)
 preview.handle_touch(touch(6,true,point),clip);preview._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
 check("background cancellation releases stale touch identities",preview.touch_ids.is_empty() and preview.pointer==-1 and not preview.blocked)
 preview.handle_touch(touch(7,true,point),clip);before=preview.yaw
 preview.handle_touch(drag(7,point+Vector2(1,30)),clip)
 check("vertical preview drag yields to prose without rotation",preview.pointer==-1 and preview.yaw==before and preview.scroll_request.get("index",-1)==7)
 preview.handle_touch(touch(7,false,point),clip);preview.cancel_input()
 var press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=Vector2(80,80);preview._mouse_input(press)
 var motion=InputEventMouseMotion.new();motion.button_mask=MOUSE_BUTTON_MASK_LEFT;motion.position=Vector2(110,80);before=preview.yaw;preview._mouse_input(motion)
 check("mouse dragging rotates preview",preview.yaw!=before)
 motion.position=Vector2(-10,80);before=preview.yaw;preview._mouse_input(motion)
 check("mouse outside cancels",not preview.mouse_drag and before==preview.yaw)
 check("unknown kind rejected and previous freed",not preview.set_entry("unknown") and preview.pivot==null and not preview.active)
 preview.set_entry("archer");preview.hide()
 check("hidden preview releases model and rendering",preview.pivot==null and preview.actor==null and preview.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and not preview.is_processing())
 check("hidden catalogue cannot start renderer",not preview.set_entry("cavalry") and not preview.active)
 preview.show();preview.set_entry("cavalry");preview.clear_entry();preview.clear_entry()
 check("clear is idempotent",preview.pivot==null and preview.model_kind=="" and not preview.active)
 preview.queue_free();await process_frame
 var menu=load("res://main_menu.tscn").instantiate();root.add_child(menu);await process_frame
 check("home exposes catalogue without starting battle",menu.buttons.get_node_or_null("CatalogueMenuButton")!=null and not is_instance_valid(menu.match_node))
 menu._show_page("manual");await process_frame
 check("manual shows actual entry with existing prose",menu.manual_preview.model_kind=="villager" and menu.description.text.contains("成本") and not is_instance_valid(menu.match_node))
 menu.manual_section=1;menu.manual_index=8;menu._show_page("manual");await process_frame
 check("building catalogue reaches workshop",menu.manual_preview.model_kind=="workshop")
 menu.manual_section=2;menu._show_page("manual");await process_frame
 check("technology retains prose without fake model",not menu.manual_preview.visible and menu.manual_preview.pivot==null and menu.description.text.contains("研究"))
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;menu.manual_section=0;menu._show_page("manual");await process_frame;menu._layout();await process_frame
  var fits=true
  for button in menu.buttons.get_children():
   var rect=button.get_global_rect();fits=fits and rect.position.x>=0 and rect.position.y>=0 and rect.end.x<=size.x+1 and rect.end.y<=size.y+1
  check("manual controls fit "+str(size),fits and menu.scroll.size.y>100)
 var pt=menu.manual_preview.image.get_global_rect().intersection(menu.scroll.get_global_rect()).get_center()
 var old_yaw=menu.manual_preview.yaw;menu._input(touch(9,true,pt));menu._input(drag(9,pt-Vector2(1,30)))
 check("menu routes vertical model gesture to scrolling",menu.scroll.scroll_vertical>0 and menu.manual_preview.yaw==old_yaw)
 menu._input(touch(9,false,pt))
 menu._show_page("home")
 check("leaving manual clears rendering",not menu.manual_preview.active and menu.manual_preview.pivot==null and not is_instance_valid(menu.match_node))
 menu.queue_free();await process_frame
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"model_catalogue_contract","checks":checks,"failed":failed,"scope":"Real read-only model factories, isolated viewport and native input/layout contracts; not pixel or physical-device acceptance; no battle or save access"}))
 quit(1 if failed else 0)
