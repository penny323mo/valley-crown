extends SceneTree
var g
var checks=[]
func c(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():
 for i in 4:await process_frame
func run():
 root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;await settle()
 var w=g._first(0,"villager");var plot=Vector3.INF
 for z in range(-6,7):
  for x in range(-6,7):
   var p=g._snap_build_position("house",g.MapRoutes.PLAYER_HOME+Vector3(x,0,z))
   if plot==Vector3.INF and g._placement_reason("house",p,0,w.id).is_empty():plot=p
 c("visible legal ordinary house plot",plot!=Vector3.INF)
 if plot==Vector3.INF:quit(1);return
 var bank=g.economy.bank_milli(0).duplicate(true)
 g._submit("build",{"kind":"house","position":plot,"builder":w.id,"ids":[w.id]});g._tick(g.Rules.TICK)
 var site=g._get_entity(w.target)
 c("ordinary command pays once and assigns real site",site.get("kind","")=="house" and not site.built and bank.wood-g.economy.bank_milli(0).wood==g.Rules.COSTS.house.wood*1000)
 # Controlled terminal route isolates the advertised recovery, not natural blockage.
 g._path_stop(w,g.BoundedPath.NO_PATH,"controlled_test");g._publish_faction_views();g._select([site.id]);g._update_hud()
 c("actual HUD instructs direct tap recovery",g.selection_detail.text.contains("選村民後直接點工地"))
 g._select([w.id]);g.camera_focus=site.pos;g._camera_update();await settle()
 var screen=g.camera.unproject_position(site.pos);c("target is visible site in world",g._pick(screen)==site.id and g._box_point_in_world(screen))
 for down in [true,false]:
  var e=InputEventScreenTouch.new();e.index=77;e.position=screen;e.pressed=down;root.push_input(e);await settle()
 c("advertised direct tap actually queues build order",g.commands.any(func(o):return o.type=="order" and o.get("target",-1)==site.id and w.id in o.get("ids",[])))
 var paid_bank=g.economy.bank_milli(0).duplicate(true)
 g._tick(g.Rules.TICK)
 c("direct tap restarts ordinary construction route without repaying",w.state=="build" and w.target==site.id and w.path_status not in ["NO_PATH","LIMIT_REACHED"] and g.economy.bank_milli(0)==paid_bank)
 for i in 1600:
  g._tick(g.Rules.TICK)
  if site.built:break
 c("normal travel and work actually finish paid house",site.built and site.progress==1.0 and g.economy.bank_milli(0)==paid_bank)
 g._select([w.id]);g._tap(screen,true)
 c("completed friendly house still selects normally",g.selected==[site.id] and g.commands.is_empty())
 # A second ordinary paid site; selected escort is not commandeered.
 var second=Vector3.INF
 for z in range(-6,7):
  for x in range(-6,7):
   var p=g._snap_build_position("house",g.MapRoutes.PLAYER_HOME+Vector3(x,0,z))
   if second==Vector3.INF and g._placement_reason("house",p,0,w.id).is_empty():second=p
 g._submit("build",{"kind":"house","position":second,"builder":w.id});g._tick(g.Rules.TICK)
 var site2=g._get_entity(w.target);var scout=g._first(0,"scout");var scout_epoch=scout.work_epoch;var scout_state=scout.state
 g._select([w.id,scout.id]);g.camera_focus=site2.pos;g._camera_update();await settle()
 var point=g.camera.unproject_position(site2.pos)
 g._tap(point,true)
 c("mixed selection continuation only submits selected villagers",g.commands.size()==1 and g.commands[0].ids==[w.id] and g.commands[0].target==site2.id)
 g._tick(g.Rules.TICK)
 c("mixed escort original job survives continuation",scout.work_epoch==scout_epoch and scout.state==scout_state)
 g._select([scout.id]);g._tap(point,true)
 c("military only tap selects unfinished site",g.selected==[site2.id] and g.commands.is_empty())
 g._select([w.id]);g.paused=true;g._tap(point,true)
 c("paused tap selects site without construction order",g.selected==[site2.id] and g.commands.is_empty());g.paused=false
 # Distinguish reserved/living hard cap from ordinary housing shortage.
 var keep=g._first(0,"town_center")
 while g._population(0)<50:g._spawn("spearman",0,Vector3(-10+(g._population(0)%10),0,25+int(g._population(0)/10)))
 var hard_bank=g.economy.bank_milli(0).duplicate(true);g.commands.clear()
 g._submit("train",{"building":keep.id,"kind":"villager"});g._tick(g.Rules.TICK)
 c("hard cap rejection never suggests building more houses",g.toast_label.text.contains("建民居不會增加上限") and g.economy.bank_milli(0)==hard_bank and keep.queue.is_empty())
 c("ordinary building economy audit conserved",g.economy.audit().ok)
 print("DETAIL "+JSON.stringify({"selected":g.selected,"commands":g.commands,"worker_state":w.state,"worker_path_status":w.path_status,"site":site.id,"screen":str(screen)}))
 var failed=checks.filter(func(x):return not x.passed).size();print(JSON.stringify({"suite":"contextual_construction_resume_contract","checks":checks,"failed":failed,"scope":"Ordinary paid build; controlled route terminal; real routed screen touch; no natural blockage claim."}));g.free();quit(1 if failed else 0)
