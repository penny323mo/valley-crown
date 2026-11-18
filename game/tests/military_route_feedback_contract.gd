extends SceneTree
var checks=[]
func c(n,b):checks.append({"name":n,"passed":bool(b)})
func settle():
 for i in 4:await process_frame
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(390,844)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.ai_enabled=false
 # Controlled map obstacle enclosure, not claimed player-paid construction.
 var center=Vector3(-30,0,0)
 for x in [-2,0,2]:
  for z in [-2,0,2]:
   if x!=0 or z!=0:g._spawn("house",0,center+Vector3(x,0,z))
 var soldier=g._spawn("spearman",0,center+Vector3(.5,0,.5));g._navigation_rebuild();g._update_vision()
 var legal_start=g._static_unit_step_is_free(soldier,soldier.pos)
 g._select([soldier.id]);g._submit("order",{"ids":[soldier.id],"target":-1,"position":center+Vector3(8,0,0)})
 for i in 100:g._tick(g.Rules.TICK)
 g._update_hud()
 print("MILITARY_FEEDBACK "+JSON.stringify({"legal_start":legal_start,"state":soldier.state,"path_status":soldier.path_status,"path_reason":soldier.path_reason,"path_pending":soldier.path_pending,"path_size":soldier.path.size(),"hud":g.selection_summary.text,"guides":preload("res://scripts/order_routes.gd").routes(g.faction_views[0].records(),g.selected).size()}))
 c("controlled start is legal",legal_start)
 c("ordinary move genuinely exhausts route",soldier.path_status=="NO_PATH" and soldier.path_reason=="frontier_exhausted" and not soldier.path_pending and soldier.path.is_empty())
 c("terminal move HUD no longer claims movement",g.selection_summary.text.contains("已停止") and not g.selection_summary.text.ends_with("移動"))
 c("failed intent guide is hidden",preload("res://scripts/order_routes.gd").routes(g.faction_views[0].records(),g.selected).is_empty())
 var Status=preload("res://scripts/military_route_status.gd");var record=g.faction_views[0].get_record(soldier.id).duplicate(true)
 for field in ["owned","alive"]:
  var bad=record.duplicate(true);bad[field]=false;c("noncurrent military excluded "+field,Status.failure(bad).is_empty())
 for field in ["remembered","path_pending"]:
  var bad=record.duplicate(true);bad[field]=true;c("inapplicable route excluded "+field,Status.failure(bad).is_empty())
 var enemy=record.duplicate(true);enemy.team=1;c("enemy route never inspected",Status.failure(enemy).is_empty())
 c("pending player intent suppresses stale failure",Status.failure(record,true).is_empty())
 var healthy=g._first(0,"scout");var epoch=healthy.work_epoch;var before=soldier.work_epoch;var searches=soldier.path_searches;var bank=g.economy.snapshot()
 g._select([soldier.id,healthy.id]);await settle()
 c("group names stopped military count",g.selection_summary.text.contains("軍隊路線停止 1"))
 var identity=g._military_failure_identity()
 for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;g._layout_ui();g._select([soldier.id,healthy.id]);await settle()
  var button=g.actions.get_node("SelectBlockedMilitary")
  g.action_scroll.ensure_control_visible(button);await settle()
  c("recovery touch target reachable "+str(size),button.size.y>=44 and g.action_scroll.get_global_rect().encloses(button.get_global_rect()))
  var point=button.get_global_rect().get_center()
  for down in [true,false]:
   var event=InputEventScreenTouch.new();event.index=71;event.position=point;event.pressed=down;root.push_input(event);await settle()
  c("real recovery touch only selects failed member "+str(size),g.selected==[soldier.id] and g.commands.is_empty())
 c("recovery selects only failed members",g.selected==[soldier.id])
 c("recovery selection changes no orders budgets hp or payment",g.commands.is_empty() and healthy.work_epoch==epoch and soldier.work_epoch==before and soldier.path_searches==searches and g.economy.snapshot()==bank)
 g._submit("order",{"ids":[soldier.id],"target":-1,"position":center+Vector3(-.5,0,.5)})
 g._update_hud();c("new pending command retires displayed old failure",g._military_failure_identity().is_empty() and not g.selection_summary.text.contains("已停止"))
 for i in 100:g._tick(g.Rules.TICK)
 g._update_hud();c("new explicit reachable move actually succeeds",soldier.pos.distance_to(center+Vector3(-.5,0,.5))<.2 and soldier.path_status not in ["NO_PATH","LIMIT_REACHED"])
 g._select_blocked_military([soldier.id],identity);c("stale recovery identity cannot mutate newer job",g.commands.is_empty() and g._military_failure_identity().is_empty())
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"military_route_feedback_contract","checks":checks,"failed":failed,"scope":"Controlled legal enclosure, normal MOVE and true bounded search; sanitized own status and selection-only recovery, not natural full-match blockage."}))
 g.free();quit(1 if failed else 0)
