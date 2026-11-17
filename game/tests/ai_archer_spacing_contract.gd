extends SceneTree
const P=preload("res://scripts/ai_archer_spacing.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func run():
 var u={"id":1,"kind":"archer","team":1,"owned":true,"alive":true,"remembered":false,"state":"attack","pos":Vector3.ZERO,"cooldown_ticks":20}
 var e={"id":2,"kind":"spearman","category":"unit","team":0,"alive":true,"remembered":false,"pos":Vector3(2,0,0)}
 check("close melee prompts cooldown step",P.destination(u,[e])==Vector3(-1.5,0,0))
 for field in ["owned","alive"]:
  var bad=u.duplicate();bad[field]=false;check("reject "+field,P.destination(bad,[e])==Vector3.INF)
 var bad=u.duplicate();bad.cooldown_ticks=0;check("ready archer shoots not retreats",P.destination(bad,[e])==Vector3.INF)
 bad=u.duplicate();bad.state="move";check("existing move never refreshed",P.destination(bad,[e])==Vector3.INF)
 bad=u.duplicate();bad.path_status="NO_PATH";check("failed path budget preserved",P.destination(bad,[e])==Vector3.INF)
 var hidden=e.duplicate();hidden.remembered=true;check("remembered melee ignored",P.destination(u,[hidden])==Vector3.INF)
 var rear=e.duplicate();rear.id=3;rear.pos=Vector3(-3,0,0);check("never step toward second melee",P.destination(u,[e,rear])==Vector3.INF)
 var tower={"id":4,"kind":"tower","team":0,"alive":true,"remembered":false,"built":true,"radius":1,"pos":Vector3(-7,0,0)}
 check("never step into visible tower range",P.destination(u,[e,tower])==Vector3.INF)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.ai_enabled=false;g.set_process(false)
 await process_frame
 var a=g._spawn("archer",1,Vector3(-2,0,0));var b=g._spawn("spearman",0,Vector3(0.4,0,0))
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
 var start=a.pos;g._order(a,"attack",b.id);g._set_stance(b,"STOP")
 g._tick(.05)
 check("first shot normally released",a.cooldown_ticks>0 and b.hp<b.max_hp)
 g._publish_faction_views();g._refresh_work_memory()
 var own=g.faction_views[1].get_record(a.id)
 check("own cooldown observed not enemy cooldown",own.get("cooldown_ticks",-1)==a.cooldown_ticks and not g.faction_views[0].get_record(a.id).has("cooldown_ticks"))
 var before=a.cooldown_ticks;var ledger=g.attack_ledger.snapshot()
 var moved=g._ai_archer_spacing(own,g._ai_records());check("ordinary retreat submitted",moved)
 var snap=Codec.capture(g);check("pending retreat checkpoint valid",Codec.validate(snap))
 var h=load("res://main.tscn").instantiate();root.add_child(h);h.set_process(false);h.test_mode=true
 check("restore pending retreat",Restore.apply(h,snap));h.ai_enabled=false;h.paused=false
 g._tick(.05);h._tick(.05)
 check("move does not reset cooldown or issued damage",a.cooldown_ticks==before-1 and g.attack_ledger.snapshot().records_hex==ledger.records_hex)
 check("restored retreat same command and cooldown",h._get_entity(a.id).state==a.state and h._get_entity(a.id).cooldown_ticks==a.cooldown_ticks and h._get_entity(a.id).dest==a.dest)
 var max_distance=0.0
 for i in 120:
  if i%20==0:
   g._publish_faction_views();g._refresh_work_memory()
   g._ai_raid_order(g.faction_views[1].get_record(a.id),g._ai_records(),g.faction_views[1].get_record(g._first(0,"town_center").id))
   h._publish_faction_views();h._refresh_work_memory()
   h._ai_raid_order(h.faction_views[1].get_record(a.id),h._ai_records(),h.faction_views[1].get_record(h._first(0,"town_center").id))
  g._tick(.05);h._tick(.05);max_distance=maxf(max_distance,a.pos.distance_to(start))
 check("checkpoint continuation has no additional retreat loop",a.pos==h._get_entity(a.id).pos and a.cooldown_ticks==h._get_entity(a.id).cooldown_ticks and g.attack_ledger.snapshot()==h.attack_ledger.snapshot())
 var releases=[]
 for id in range(1,g.attack_ledger.next_attack_id()):
  var event=g.attack_ledger.event(id)
  if event.attacker_id==a.id:releases.append(event.release_tick)
 var spacing=true
 for i in range(1,releases.size()):
  if releases[i]-releases[i-1]<g.Rules.ATTACK_TICKS.archer:spacing=false
 check("native movement creates spacing",max_distance>0.8)
 check("archer resumes firing repeatedly",releases.size()>=3)
 check("no faster fire than authoritative cooldown",spacing)
 # Real chasing opponent, same initial snapshot versus stationary firing.
 g._order(b,"attack",a.id);g._publish_faction_views();g._refresh_work_memory()
 var duel=Codec.capture(g);check("combat checkpoint validates",Codec.validate(duel))
 check("baseline clone restored",Restore.apply(h,duel));h.ai_enabled=false;h.paused=false
 var moves=0;var origins=[]
 for i in 240:
  if not a.alive:break
  if i%20==0:
   g._publish_faction_views();g._refresh_work_memory()
   var r=g.faction_views[1].get_record(a.id)
   if b.alive:g._ai_raid_order(r,g._ai_records(),{})
   if g.commands.any(func(c):return c.type=="order" and c.get("target",-2)==-1 and a.id in c.get("ids",[])):moves+=1
  g._tick(.05)
  if h._get_entity(a.id).alive:h._tick(.05)
  origins.append(str(a.pos))
 check("pursuit generates bounded spacing orders",moves>0 and moves<=12)
 var duel_releases=[]
 for id in range(1,g.attack_ledger.next_attack_id()):
  var ev=g.attack_ledger.event(id)
  if ev.attacker_id==a.id:duel_releases.append(ev.release_tick)
 var legal_rate=true
 for i in range(1,duel_releases.size()):
  if duel_releases[i]-duel_releases[i-1]<30:legal_rate=false
 check("pursuit still obeys cooldown",legal_rate)
 print("PURSUIT "+JSON.stringify({"moves":moves,"archer_hp":a.hp,"opponent_hp":b.hp,"baseline_archer_hp":h._get_entity(a.id).hp,"baseline_opponent_hp":h._get_entity(b.id).hp,"release_ticks":duel_releases}))
 h._test_reset();h.ai_enabled=false;h.set_process(false)
 var blocked_archer=h._spawn("archer",1,Vector3(-2,0,0));var blocked_enemy=h._spawn("spearman",0,Vector3(0.4,0,0))
 h._spawn("wall",1,Vector3(-4,0,0))
 h._navigation_rebuild();h._update_vision(false);h._publish_faction_views();h._refresh_work_memory()
 h._set_stance(blocked_enemy,"STOP");h._order(blocked_archer,"attack",blocked_enemy.id);h._tick(.05)
 h._publish_faction_views();h._refresh_work_memory()
 check("solid rear wall refuses spacing command",not h._ai_archer_spacing(h.faction_views[1].get_record(blocked_archer.id),h._ai_records()) and h.commands.is_empty())
 var old_hp=blocked_enemy.hp
 for i in 35:h._tick(.05)
 check("blocked retreat leaves ordinary firing active",blocked_enemy.hp<old_hp and blocked_archer.state=="attack")
 h._test_reset();h.ai_enabled=false;h.set_process(false)
 for i in 10:h._tick(.05)
 var live_archer=h._spawn("archer",1,Vector3(-2,0,0));var live_enemy=h._spawn("spearman",0,Vector3(0.4,0,0))
 h._spawn("scout",1,Vector3(-16,0,24))
 h._navigation_rebuild();h._update_vision(false);h._publish_faction_views();h._refresh_work_memory()
 var observed_keep=h.faction_views[1].get_record(h._first(0,"town_center").id)
 check("full pipeline keep acquired by actual scout sight",not observed_keep.is_empty())
 h.ai_raid_members=[live_archer.id];h.ai_raid_departure_count=1;h.ai_raid_keep=observed_keep.duplicate(true);h.ai_last_raid_tick=0
 h._order(live_archer,"attack",live_enemy.id);h._order(live_enemy,"attack",live_archer.id);h.ai_enabled=true
 var moved_ticks=0;var observed_status=[]
 for i in 220:
  if not live_archer.alive:break
  h._tick(.05)
  if live_archer.state=="move" and h.ai_status.get("army","")=="raid_active":moved_ticks+=1
  if h.ai_status.get("army","") not in observed_status:observed_status.append(h.ai_status.get("army",""))
 var pipeline_shots=[]
 for id in range(1,h.attack_ledger.next_attack_id()):
  var ev=h.attack_ledger.event(id)
  if ev.attacker_id==live_archer.id:pipeline_shots.append(ev.release_tick)
 check("real ai_update army pipeline moves active raid archer",moved_ticks>0)
 check("real ai_update pipeline resumes arrows",pipeline_shots.size()>=3)
 print("FULL_AI_PIPELINE "+JSON.stringify({"shots":pipeline_shots,"move_ticks":moved_ticks,"statuses":observed_status,"archer_hp":live_archer.hp,"enemy_hp":live_enemy.hp}))
 print("MOTION_DIAGNOSTIC "+JSON.stringify({"shots":releases,"motion":max_distance}))
 print(JSON.stringify({"suite":"ai_archer_spacing_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"controlled stationary and pursuing melee fixtures; normal commands/combat and snapshot baseline; not natural match balance"}))
 quit(0 if checks.all(func(c):return c.passed) else 1)
