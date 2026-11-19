extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
var g
var size_tag=""
var rows=[]
var checks=[]
func _initialize():call_deferred("run")
func ck(n,v):
 checks.append({"name":n+size_tag,"passed":bool(v)})
 if not v:push_error(n)
 return bool(v)
func settle():
 g._update_hud();g._layout_ui();await process_frame;await process_frame
func touch(p):
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=down;root.push_input(e);await process_frame
func swipe(direction=-1):
 var r=g.action_scroll.get_global_rect();var p=r.get_center()-Vector2(direction*r.size.x*.35,0);var q=p+Vector2(direction*r.size.x*.6,0)
 var e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=true;root.push_input(e)
 var d=InputEventScreenDrag.new();d.index=0;d.position=q;d.relative=q-p;root.push_input(d)
 e=InputEventScreenTouch.new();e.index=0;e.position=q;e.pressed=false;root.push_input(e);await settle()
func save(_done):pass
func run_case(size):
 root.size=size;size_tag=" "+str(size)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.history_path="/tmp/mode-scroll-private-history";root.add_child(g);g.set_process(false)
 for i in 200:g._process(g.Rules.TICK)
 var worker=g._first(0,"villager");var home=g._first(0,"town_center");g._select([worker.id]);await settle()
 var button
 for b in g.actions.get_children():
  if b is Button and b.text.begins_with(g.Rules.NAMES.barracks+"\n"):button=b
 if not ck("barracks existing named build action",button!=null):save(true);g.free();quit(1);return
 for i in 12:
  if g.action_scroll.get_global_rect().encloses(button.get_global_rect()):break
  await swipe()
 ck("real swipe changes no authority command",g.commands.is_empty())
 if not ck("barracks reached by real action swipe",g.action_scroll.get_global_rect().encloses(button.get_global_rect())):save(true);g.free();quit(1);return
 await touch(button.get_global_rect().get_center());await settle();ck("actual root tap enters barracks preview",g.build_mode=="barracks")
 var initial=g.economy.bank_milli(0).duplicate(true)
 ck("build entry offers visible confirmation immediately",g.action_scroll.get_global_rect().encloses(g.build_confirm.get_global_rect()))
 var cancel
 for b in g.actions.get_children():
  if b is Button and b.text=="取消建造":cancel=b
 if not ck("cancel control fully reachable",cancel!=null and g.action_scroll.get_global_rect().encloses(cancel.get_global_rect())):g.free();quit(1);return
 await touch(cancel.get_global_rect().get_center());await settle()
 ck("real cancel returns build list without payment",g.build_mode.is_empty() and g.commands.is_empty() and g.economy.bank_milli(0)==initial and g.action_scroll.scroll_horizontal==0)
 for b in g.actions.get_children():
  if b is Button and b.text.begins_with(g.Rules.NAMES.barracks+"\n"):button=b
 for i in 12:
  if g.action_scroll.get_global_rect().encloses(button.get_global_rect()):break
  await swipe()
 await touch(button.get_global_rect().get_center());await settle()
 var point=g.camera.unproject_position(home.pos)
 if ck("illegal home point lies in world input region",g._box_point_in_world(point)):
  await touch(point);await settle();ck("occupied home preview cannot confirm",g.build_confirm.disabled and not g._build_preview_reason().is_empty() and g.commands.is_empty() and g.economy.bank_milli(0)==initial)
 var plot=Vector3.INF;var best=INF
 for y in g.Rules.MAP_SIZE:
  for x in g.Rules.MAP_SIZE:
   var p=g._point(Vector2i(x,y));var dist=p.distance_squared_to(worker.pos)
   if dist<best and g._box_point_in_world(g.camera.unproject_position(p)) and g._placement_reason("barracks",p,0,worker.id).is_empty():plot=p;best=dist
 if not ck("visible legal paid barracks plot",plot.is_finite()):save(true);g.free();quit(1);return
 await touch(g.camera.unproject_position(plot));await settle();var bank=g.economy.bank_milli(0).duplicate(true)
 ck("valid world tap holds preview without selecting underlying units or paying",not g.build_confirm.disabled and g.build_preview_held and g.selected==[worker.id] and g.commands.is_empty() and bank==initial)
 ck("confirm is fully visible without recovery swipe",g.action_scroll.get_global_rect().encloses(g.build_confirm.get_global_rect()))
 var confirm_center=g.build_confirm.get_global_rect().get_center()
 ck("confirm coordinate is GUI not a world placement point",not g._box_point_in_world(confirm_center))
 var preview=g.pointer_world
 await touch(g.build_confirm.get_global_rect().get_center())
 ck("confirmation tap retires preview without issuing world move",g.build_mode.is_empty() and g.commands.size()==1 and g.commands[0].type=="build" and g.commands[0].position==preview)
 g._process(g.Rules.TICK);ck("ordinary barracks costs120wood",g.economy.bank_milli(0).wood==bank.wood-120000)
 var barracks=g._first(0,"barracks")
 for i in 1600:
  if barracks!=null and not barracks.is_empty() and barracks.built:break
  g._process(g.Rules.TICK)
 if not ck("paid barracks completed normally",barracks!=null and not barracks.is_empty() and barracks.built):save(true);g.free();quit(1);return
 g._select([barracks.id]);await settle()
 var train
 for b in g.actions.get_children():
  if b is Button and b.get_meta("primary_train",false):train=b
 if ck("primary train fully visible after context change",train!=null and g.action_scroll.get_global_rect().encloses(train.get_global_rect())):
  bank=g.economy.bank_milli(0).duplicate(true);var count=g._count(0,"spearman");await touch(train.get_global_rect().get_center());g._process(g.Rules.TICK)
  ck("root tap normal50food20wood payment",g.economy.bank_milli(0).food==bank.food-50000 and g.economy.bank_milli(0).wood==bank.wood-20000)
  for i in 700:
   if g._count(0,"spearman")>count:break
   g._process(g.Rules.TICK)
  ck("normal paid spearman born",g._count(0,"spearman")==count+1)
 ck("ledger conserved",g.economy.audit().ok);g.free();await process_frame
func run():
 await run_case(Vector2i(390,844));await run_case(Vector2i(640,360))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"command_mode_paid_flow_contract","checks":checks,"failed":failed,"scope":"Two fresh original-bank practice matches. Real root swipe/tap, cancel/invalid/valid map placement, visible Confirm without reverse-swipe recovery, ordinary paid barracks and actual paid spearman birth. No authority injection, not physical phone."}))
 quit(1 if failed else 0)
