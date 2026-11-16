extends SceneTree
## Real viewport event routing, not physical-device certification.
var g
var checks=[]
func check(name,value):
 checks.append({"name":name,"passed":bool(value)})
 if not value:push_error(name)
func _initialize():call_deferred("run")
func settle():
 for i in 4:await process_frame
func touch(point,pressed,index=0):
 var e=InputEventScreenTouch.new();e.position=point;e.pressed=pressed;e.index=index
 root.push_input(e,false)
func tap(point):
 touch(point,true);await process_frame;touch(point,false);await settle()
func button(prefix):
 for child in g.actions.get_children():
  if child is Button and child.text.begins_with(prefix):return child
 return null
func show_button(b):
 var parent=b.get_parent()
 while parent!=null:
  if parent is ScrollContainer:parent.ensure_control_visible(b);break
  parent=parent.get_parent()
 await settle()
 return b.get_global_rect().get_center()
func ground():
 for y in range(90,root.size.y-85,15):
  for x in range(30,root.size.x-30,20):
   var p=Vector2(x,y)
   if g._box_point_in_world(p) and g._pick(p)<0 and g.TacticalRoute.valid_points([g._world_at(p)]):return p
 return Vector2.ZERO
func run():
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size
  g=load("res://main.tscn").instantiate();g.history_path="/tmp/tactical-input-"+str(Time.get_ticks_usec())+".json"
  root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
  await settle()
  var scout=g._first(0,"scout");g._select([scout.id]);g._start_tactical_route();await settle()
  var p=ground();check(str(size)+" world point available",p!=Vector2.ZERO)
  await tap(p)
  check(str(size)+" routed ground tap adds one waypoint",g.tactical_draft.size()==1 and g.commands.is_empty())
  var stored=g.tactical_draft.duplicate()
  await tap(g.hud_top.get_global_rect().get_center())
  check(str(size)+" HUD tap does not append waypoint",g.tactical_draft==stored and g.commands.is_empty())
  touch(p,true,0);touch(p+Vector2(20,0),true,1)
  var drag=InputEventScreenDrag.new();drag.index=1;drag.position=p+Vector2(40,10);drag.relative=Vector2(20,10)
  root.push_input(drag,false);await process_frame
  touch(p+Vector2(40,10),false,1);touch(p,false,0);await settle()
  check(str(size)+" two fingers never append route or world command",g.tactical_draft==stored and g.commands.is_empty())
  check(str(size)+" two fingers retire route targeting",not g.touch_command)
  g._cancel_mode();g._start_tactical_route();await settle();p=ground();await tap(p)
  var confirm=button("出發")
  check(str(size)+" confirmation action exists",confirm!=null)
  if confirm!=null:
   var at=await show_button(confirm);await tap(at)
   check(str(size)+" routed confirmation dispatches exactly one route",g.commands.size()==1 and g.commands[0].type=="tactical_route" and not g.touch_command)
   touch(at,false);await settle()
   check(str(size)+" duplicate confirm release cannot leak order",g.commands.size()==1 and g.commands[0].type=="tactical_route")
  g.commands.clear();g._start_tactical_route();await settle();p=ground();await tap(p)
  var cancel=button("取消路線")
  check(str(size)+" cancel action exists",cancel!=null)
  if cancel!=null:
   var at=await show_button(cancel);await tap(at);touch(at,false);await settle()
   check(str(size)+" routed cancellation clears plan without order",g.tactical_draft.is_empty() and not g.touch_command and g.commands.is_empty())
  check(str(size)+" history remains untouched",not FileAccess.file_exists(g.history_path))
  g.queue_free();await settle()
 var result={"suite":"tactical_route_input_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Real Godot viewport touch routing at two sizes; controlled new worlds, not physical iPhone proof"}
 print(JSON.stringify(result));quit(0 if result.failed==0 else 1)
