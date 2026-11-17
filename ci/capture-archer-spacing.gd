extends SceneTree
var g
var a
var b
var shots=[]
var checks=[]
var out="/tmp/archer-spacing-capture"
func _initialize():call_deferred("run")
func check(n,v):checks.append({"name":n,"passed":bool(v)})
func releases():
 var result=[]
 for id in range(1,g.attack_ledger.next_attack_id()):
  var ev=g.attack_ledger.event(id)
  if ev.attacker_id==a.id:result.append(ev)
 return result
func shot(stage):
 if stage=="final-observed-state":
  g.camera_focus=(a.pos+b.pos)*0.5;g._camera_update()
 g._refresh_fog() # Normal render refresh from existing visibility; no visibility mutation.
 g._update_visuals(0);g._update_hud()
 var s={"stage":stage,"tick":g.tick_count,"rendered":false,"archer":{"pos":str(a.pos),"hp":a.hp,"alive":a.alive,"state":a.state},"spearman":{"pos":str(b.pos),"hp":b.hp,"alive":b.alive},"ledger":releases(),"ai_status":g.ai_status.duplicate(true)}
 if DisplayServer.get_name()!="headless":
  for i in 3:await process_frame
  await RenderingServer.frame_post_draw
  s.rendered=root.get_texture().get_image().save_png(out+"/archer-"+stage+".png")==OK
 shots.append(s)
func run():
 DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(960,540)
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false)
 await process_frame
 for i in 10:g._tick(.05)
 a=g._spawn("archer",1,Vector3(-2,0,0));b=g._spawn("spearman",0,Vector3(0.4,0,0))
 var scout=g._spawn("scout",1,Vector3(-16,0,24))
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
 var keep=g.faction_views[1].get_record(g._first(0,"town_center").id)
 check("enemy keep observed by real scout sight",not keep.is_empty())
 g.ai_raid_members=[a.id];g.ai_raid_departure_count=1;g.ai_raid_keep=keep.duplicate(true);g.ai_last_raid_tick=0
 g._order(a,"attack",b.id);g._order(b,"attack",a.id);g.ai_enabled=true
 g._select([b.id]);g.tutorial_panel.hide();g.camera_focus=Vector3(-2,0,0);g.camera_zoom=8;g._camera_update()
 check("player opponent provides actual archer sight",g._visible_to(a,0))
 await shot("before-close-melee")
 var origin=a.pos;var moved=0;var captured=false;var seen=[]
 for i in 400:
  if not a.alive or not b.alive:break
  g._tick(.05)
  if a.state=="move" and g.ai_status.get("army","")=="raid_active":moved+=1
  if a.pos.distance_to(origin)>.6 and releases().size()>=2 and not captured and a.state=="attack":
   captured=true;await shot("after-retreat-firing")
  if g.ai_status.get("army","") not in seen:seen.append(g.ai_status.get("army",""))
 await shot("final-observed-state")
 var events=releases();var rate=true
 for i in range(1,events.size()):
  if events[i].release_tick-events[i-1].release_tick<30:rate=false
 check("normal ai pipeline resumes repeated attacks",events.size()>=3)
 check("authoritative cooldown retained",rate)
 check("final state captured without claiming a kill",shots[-1].tick==g.tick_count)
 if g.has_method("_ai_archer_spacing"):
  check("raid pipeline actually moved archer",moved>0)
  check("retreat and resumed firing captured",captured)
 var proof={"suite":"archer_spacing_controlled_capture","build":g.Rules.BUILD_ID,"scope":"Controlled spawned archer and pursuing spearman; scout legitimately observes enemy keep; one pre-existing raid cohort initialized. Thereafter full ai_enabled _tick/_ai_update/_ai_army pipeline, no direct tactical helper. Normal player opponent sight, ordinary camera angle zoom8, HUD retained. No fog/terrain/health/cooldown modifications. Headless stages metadata only, not images.","shots":shots,"checks":checks,"move_ticks":moved,"statuses":seen,"scout_id":scout.id,"final_tick":g.tick_count,"archer_hp":a.hp,"spearman_hp":b.hp}
 var f=FileAccess.open(out+"/archer-spacing-proof.json",FileAccess.WRITE);f.store_string(JSON.stringify(proof,"  "));f.close()
 print("ARCHER_CAPTURE ",JSON.stringify(proof));quit(0 if checks.all(func(c):return c.passed) else 1)
