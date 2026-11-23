extends SceneTree
var g
var rows=[]
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func usable_filter(b,clip):
 if not b is Button or not b.is_visible_in_tree() or b.disabled:return false
 var rect=b.get_global_rect()
 var hit=rect.intersection(clip).intersection(root.get_visible_rect())
 return hit.size.x>=44 and hit.size.y>=44 and hit.has_point(rect.get_center())
func primary_train():
 for b in g.actions.get_children():
  if b is Button and b.get_meta("primary_train",false):return b
 return null
func touch(point,pressed,index=0):
 var e=InputEventScreenTouch.new();e.index=index;e.position=point;e.pressed=pressed;root.push_input(e)

func _initialize():call_deferred("run")
func settle():
 g._update_hud();g._layout_ui();await process_frame;await process_frame;g._layout_ui();await process_frame
func snapshot(label):
 var r=g.action_scroll.get_global_rect();var buttons=[]
 for b in g.actions.get_children():
  if b is Button and b.is_visible_in_tree():
   var q=b.get_global_rect();var intersection=q.intersection(r)
   buttons.append({"text":b.text,"rect":str(q),"visible_width":maxf(0,intersection.size.x),"full_width":q.size.x,"enabled":not b.disabled,"icon":b.icon!=null,"right_margin":b.get_theme_stylebox("normal").get_content_margin(SIDE_RIGHT)})
 var row={"label":label,"tick":g.tick_count,"size":str(root.size),"bottom":str(g.hud_bottom.get_global_rect()),"top":str(g.hud_top.get_global_rect()),"strip":str(r),"offset":g.action_scroll.scroll_horizontal,"max":g.action_scroll.get_h_scroll_bar().max_value,"page":g.action_scroll.get_h_scroll_bar().page,"buttons":buttons,"selected":g.selected.duplicate(),"commands":g.commands.duplicate(true)}
 rows.append(row);print("UI "+JSON.stringify(row))
func swipe():
 var r=g.action_scroll.get_global_rect();var a=r.get_center()+Vector2(r.size.x*.35,0);var b=a-Vector2(r.size.x*.65,0)
 var e=InputEventScreenTouch.new();e.index=0;e.position=a;e.pressed=true;root.push_input(e)
 var d=InputEventScreenDrag.new();d.index=0;d.position=b;d.relative=b-a;root.push_input(d)
 e=InputEventScreenTouch.new();e.index=0;e.position=b;e.pressed=false;root.push_input(e)
 await process_frame;await process_frame
func run():
 root.size=Vector2i(390,844);g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 var worker=g._first(0,"villager");var scout=g._first(0,"scout");var home=g._first(0,"town_center")
 for size in [Vector2i(640,360),Vector2i(390,844)]:
  root.size=size;g._select([worker.id]);await settle();snapshot("worker-initial")
  for i in 3:await swipe()
  snapshot("worker-after-three-real-swipes")
  var scroll=g.action_scroll.scroll_horizontal
  check("true action swipes scroll without commands "+str(size),scroll>0 and g.commands.is_empty())
  g._update_hud();await settle()
  check("same-selection periodic refresh preserves offset "+str(size),g.action_scroll.scroll_horizontal==scroll)
  g._select([worker.id]);await settle()
  check("explicit same selection preserves offset "+str(size),g.action_scroll.scroll_horizontal==scroll)
  g._select([home.id]);await settle();snapshot("home-after-scrolled-worker")
  check("new home selection exposes primary training "+str(size),g.action_scroll.scroll_horizontal==0 and g.action_scroll.get_global_rect().encloses(primary_train().get_global_rect()))
  g._select([worker.id,scout.id]);await settle();snapshot("mixed-worker-scout")
  var army_filter=g.actions.get_node_or_null("FilterSelectedMilitary")
  var villager_filter=g.actions.get_node_or_null("SelectType_villager")
  var clip=g.action_scroll.get_global_rect()
  check("new mixed selection exposes army then villager shortcuts "+str(size),usable_filter(army_filter,clip) and usable_filter(villager_filter,clip) and army_filter.get_index()==0 and army_filter.get_index()<villager_filter.get_index() and g.action_scroll.scroll_horizontal==0 and g.commands.is_empty())
  await swipe();var mixed_scroll=g.action_scroll.scroll_horizontal;g._select([scout.id,worker.id]);await settle()
  check("same membership reversed order preserves scroll "+str(size),g.action_scroll.scroll_horizontal==mixed_scroll)
 var plot=Vector3.INF;var best=INF
 for y in g.Rules.MAP_SIZE:
  for x in g.Rules.MAP_SIZE:
   var p=g._point(Vector2i(x,y));var distance=p.distance_squared_to(worker.pos)
   if distance<best and g._placement_reason("barracks",p,0,worker.id).is_empty():plot=p;best=distance
 if not plot.is_finite():push_error("no visible legal barracks plot");quit(1);return
 g._select([worker.id]);g._start_build("barracks");g.pointer_world=plot;g.build_preview_held=true;g._update_ghost();g._confirm_build();g._tick(g.Rules.TICK)
 var barracks={}
 for ent in g.entities:
  if ent.alive and ent.team==0 and ent.kind=="barracks":barracks=ent
 for i in 1600:
  if barracks.is_empty() or barracks.built:break
  g._tick(g.Rules.TICK)
 if barracks.is_empty() or not barracks.built:push_error("paid ordinary barracks incomplete");quit(1);return
 for size in [Vector2i(640,360),Vector2i(390,844)]:
  root.size=size;g._select([worker.id]);await settle();g._select([barracks.id]);await settle();snapshot("paid-barracks-initial")
  check("paid producer first train is wholly reachable "+str(size),g.action_scroll.get_global_rect().encloses(primary_train().get_global_rect()))
  await swipe();snapshot("paid-barracks-after-real-swipe")
  var after_swipe=g.action_scroll.scroll_horizontal;g._update_hud();await settle()
  check("producer routine refresh does not steal intentional scroll "+str(size),g.action_scroll.scroll_horizontal==after_swipe)
 # A held command from the old context cannot pay for a replacement context.
 g._select([worker.id]);await settle();g._select([barracks.id]);await settle()
 var b=primary_train();var point=b.get_global_rect().get_center();var bank=g.economy.bank_milli(0).duplicate(true)
 touch(point,true);g._select([worker.id]);await settle();touch(point,false);await process_frame;await process_frame
 check("held old train release after context switch never submits",g.commands.is_empty() and g.economy.bank_milli(0)==bank)
 # Late drag after a membership replacement cannot resurrect the old offset.
 var strip=g.action_scroll.get_global_rect();var start=strip.get_center()
 touch(start,true);var d=InputEventScreenDrag.new();d.index=0;d.position=start-Vector2(50,0);d.relative=Vector2(-50,0);root.push_input(d)
 g._select([home.id]);await settle();d=InputEventScreenDrag.new();d.index=0;d.position=start-Vector2(100,0);d.relative=Vector2(-50,0);root.push_input(d);touch(d.position,false);await process_frame;await process_frame
 check("late old drag cannot scroll replacement selection",g.action_scroll.scroll_horizontal==0 and g.commands.is_empty())
 g._select([barracks.id]);await settle();b=primary_train();point=b.get_global_rect().get_center()
 var count=g._count(0,"spearman");touch(point,true);touch(point,false)
 check("fresh visible train touch queues one normal payment",g.commands.size()==1 and g.commands[0].type=="train" and g.commands[0].kind=="spearman")
 g._tick(g.Rules.TICK)
 check("training costs ordinary fifty food twenty wood once",g.economy.bank_milli(0).food==bank.food-50000 and g.economy.bank_milli(0).wood==bank.wood-20000)
 await swipe();var queue_scroll=g.action_scroll.scroll_horizontal;g._update_hud();await settle()
 check("same producer paid queue refresh keeps scroll",g.action_scroll.scroll_horizontal==queue_scroll)
 for i in 700:
  if g._count(0,"spearman")>count:break
  g._tick(g.Rules.TICK)
 check("normal paid training physically births spearman",g._count(0,"spearman")==count+1 and barracks.queue.is_empty())
 g._select([worker.id,scout.id]);await settle();await swipe()
 g._request_garrison_selected()
 for i in 800:
  if worker.has("garrison_host"):break
  g._tick(g.Rules.TICK)
 await settle()
 check("ordinary garrison changes selected membership and resets strip",worker.has("garrison_host") and g.selected==[scout.id] and g.action_scroll.scroll_horizontal==0)
 await swipe();g._kill(scout);g._publish_faction_views();await settle()
 check("controlled selected death changes context without tail inheritance",g.selected.is_empty() and g.action_scroll.scroll_horizontal==0)
 check("real paid journey preserves ledger conservation",g.economy.audit().ok)
 print("AUDIT "+JSON.stringify({"rows":rows,"bank":g.economy.bank_milli(0),"receipt":g.economy.receipt_view(barracks.cost_receipt_id),"audit":g.economy.audit()}))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"command_context_scroll_contract","checks":checks,"failed":failed,"scope":"Fresh practice paid barracks/training, real touch scrolling and context switches; controlled selected death separately labelled; no phone FPS claim"}))
 g.free();quit(1 if failed else 0)
