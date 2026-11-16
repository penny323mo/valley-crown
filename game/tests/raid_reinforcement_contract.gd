extends SceneTree
const Policy=preload("res://scripts/ai_raid_reinforcement.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func run():
 var castle={"pos":Vector3.ZERO,"radius":2.0,"owned":true,"alive":true,"remembered":false,"team":1,"built":true,"category":"building","kind":"town_center"}
 var army=[]
 for i in 5:army.append({"id":i+10,"category":"unit","owned":true,"remembered":false,"alive":true,"team":1,"kind":"cavalry","state":"idle","pos":Vector3(i,0,0)})
 check("whole standard cohort releases after cooldown",Policy.batch(army,[1],castle,"standard",1800,0)==[10,11,12,13,14])
 check("no solitary reinforcement",Policy.batch(army.slice(0,1),[1],castle,"standard",1800,0).is_empty())
 check("four recruits wait",Policy.batch(army.slice(0,4),[1],castle,"standard",1800,0).is_empty())
 check("pressure uses existing three member policy",Policy.batch(army.slice(0,3),[1],castle,"pressure",1200,0).size()==3)
 check("existing cooldown enforced",Policy.batch(army,[1],castle,"standard",1799,0).is_empty())
 check("practice never reinforces",Policy.batch(army,[1],castle,"practice",1800,0).is_empty())
 check("no cohort without active raid",Policy.batch(army,[],castle,"standard",1800,0).is_empty())
 check("existing members not counted twice",Policy.batch(army,[10],castle,"standard",1800,0).is_empty())
 for field in ["state","pos","owned","remembered","alive","team","category","kind"]:
  var copy=army.duplicate(true)
  copy[0][field]={"state":"move","pos":Vector3(20,0,0),"owned":false,"remembered":true,"alive":false,"team":0,"category":"building","kind":"villager"}[field]
  check("reject ineligible reserve "+field,Policy.batch(copy,[1],castle,"standard",1800,0).is_empty())
 for field in ["owned","alive","remembered","team","built","category","kind"]:
  var bad=castle.duplicate()
  bad[field]={"owned":false,"alive":false,"remembered":true,"team":0,"built":false,"category":"unit","kind":"storehouse"}[field]
  check("reject invalid muster castle "+field,Policy.batch(army,[1],bad,"standard",1800,0).is_empty())
 check("duplicate IDs cannot inflate quorum",Policy.batch([army[0],army[0],army[0],army[0],army[0]],[1],castle,"standard",1800,0).is_empty())
 var corners=army.duplicate(true)
 for r in corners:r.pos=Vector3(4,0,4)
 check("square corner arrival eligible",Policy.batch(corners,[1],castle,"standard",1800,0).size()==5)
 for r in corners:r.pos=Vector3(4.2,0,4.2)
 check("outside square muster boundary excluded",Policy.batch(corners,[1],castle,"standard",1800,0).is_empty())
 var g=load("res://main.tscn").instantiate();g.history_path="/tmp/reinforcement-contract-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 await process_frame
 var home=g._first(1,"town_center")
 var parked=corners.duplicate(true)
 for r in parked:r.pos=home.pos+Vector3(4,0,4)
 g.commands.clear();g._ai_move_home(parked,home)
 var observed_home={"pos":home.pos,"owned":true,"alive":true,"remembered":false,"team":1,"built":true,"category":"building","kind":"town_center"}
 check("actual move-home stopping region matches batch corner",g.commands.is_empty() and Policy.batch(parked,[1],observed_home,"standard",1800,0).size()==5)
 var old=g._spawn("archer",1,home.pos+Vector3(-8,0,0))
 var recruits=[]
 for i in 5:recruits.append(g._spawn("cavalry",1,home.pos+Vector3(0,0,float(i)-2)))
 g._update_vision();g._publish_faction_views()
 var records=g.faction_views[1].records().values()
 # Controlled observations use public remembered keep, not hidden authority.
 var keep={"id":g._first(0,"town_center").id,"team":0,"kind":"town_center","category":"building","owned":false,"alive":true,"remembered":true,"pos":Vector3(-25,0,24),"radius":2.0}
 records.append(keep)
 var ownhome=g.faction_views[1].records()[home.id]
 g.ai_raid_members=[old.id];g.ai_raid_departure_count=1;g.ai_raid_keep=keep.duplicate(true);g.ai_last_raid_tick=-1800
 var before=g.economy.bank_milli(1).duplicate()
 g.commands.clear();g._ai_army(records,ownhome)
 check("active raid adds five real recruits",recruits.all(func(e):return e.id in g.ai_raid_members))
 var batch=g.commands.filter(func(c):return c.get("ids",[]).size()==5)
 check("integration emits one whole cohort ordinary order",batch.size()==1 and batch[0].get("type", "")=="order")
 check("remembered keep receives ground order only",batch.size()==1 and batch[0].target==-1 and batch[0].position==keep.pos)
 check("existing retreat denominator includes cohort",g.ai_raid_departure_count==6)
 check("shared departure timing updated",g.ai_last_raid_tick==g.tick_count)
 check("no resource gift or fee bypass",g.economy.bank_milli(1)==before)
 g.commands.clear();g._ai_army(records,ownhome)
 check("same recruits never duplicate membership",g.ai_raid_members.size()==6)
 check("repeat policy emits no new batch",not g.commands.any(func(c):return c.get("ids",[]).size()==5))
 var Codec=load("res://scripts/checkpoint_codec.gd");var Restore=load("res://scripts/checkpoint_restore.gd")
 var snapshot=Codec.capture_result(g)
 check("active reinforcement checkpoint validates",snapshot.ok)
 if snapshot.ok:
  var h=load("res://main.tscn").instantiate();h.history_path="/tmp/reinforcement-restored-"+str(Time.get_ticks_usec())+".json"
  root.add_child(h);h.set_process(false);h.test_mode=true
  await process_frame
  var applied=Restore.apply(h,snapshot.data)
  check("reinforcement existing state restores",applied)
  if applied:
   check("capture exactly retained without new schema fields",Codec.capture(h)==snapshot.data)
   h.paused=false;g.commands.clear();h.commands.clear()
   g._ai_army(records,ownhome);h._ai_army(records,ownhome)
   check("restored policy commands identical",g.commands==h.commands)
   check("restored cohort and cooldown identical",g.ai_raid_members==h.ai_raid_members and g.ai_last_raid_tick==h.ai_last_raid_tick and g.ai_raid_departure_count==h.ai_raid_departure_count)
   for i in 40:g._tick(g.Rules.TICK);h._tick(h.Rules.TICK)
   check("forty ordinary ticks continue identically",Codec.capture(g)==Codec.capture(h))
   check("continued economics conserved",g.economy.audit().ok and h.economy.audit().ok)
  h.free()
 g.ai_raid_members=[old.id];g.ai_raid_departure_count=1;g.ai_raid_retreating=true;g.ai_last_raid_tick=-1800;g.commands.clear();g._ai_army(records,ownhome)
 check("retreat takes priority over fresh reserves",g.ai_raid_members==[old.id] and g.ai_status.army=="retreat")
 g.ai_raid_retreating=false;g.commands.clear();g._ai_army(records.filter(func(r):return r.id!=keep.id),ownhome)
 check("no enemy memory means retreat not reinforcement",g.ai_raid_retreating and g.ai_raid_members==[old.id])
 g.ai_raid_retreating=false;g.ai_last_raid_tick=-1800
 var wounded=records.duplicate(true)
 for r in wounded:
  if r.id==recruits[0].id:r.hp=1
 g.commands.clear();g._ai_army(wounded,ownhome)
 check("wounded reserve excluded before batch quorum",not recruits[0].id in g.ai_raid_members and not g.commands.any(func(c):return c.get("ids",[]).size()==5))
 var invader=g._spawn("siege",0,home.pos+Vector3(1,0,0))
 g._update_vision();g._publish_faction_views();var danger=g.faction_views[1].records().values();danger.append(keep)
 g.ai_raid_members=[old.id];g.ai_raid_departure_count=1;g.ai_raid_retreating=false;g.commands.clear();g._ai_army(danger,ownhome)
 check("keep emergency precedes reinforcement",g.ai_status.army=="home_defense" and g.ai_raid_retreating and g.ai_raid_members==[old.id])
 check("isolated history untouched",not FileAccess.file_exists(g.history_path))
 # Controlled actual scout movement must not be overwritten by reserve muster.
 var scout=g._spawn("scout",1,home.pos+Vector3(-12,0,-8))
 var reserve=g._spawn("spearman",1,home.pos+Vector3(-10,0,-8))
 var scout_goal=home.pos+Vector3(-18,0,-12)
 g._execute({"type":"order","team":1,"ids":[scout.id],"target":-1,"position":scout_goal})
 var scout_epoch=scout.work_epoch
 var scout_dest=scout.dest
 g._update_vision();g._publish_faction_views()
 var isolated=g._ai_records().filter(func(r):return r.id in [home.id,old.id,scout.id,reserve.id])
 isolated.append(keep)
 g.ai_raid_members=[old.id];g.ai_raid_departure_count=1;g.ai_raid_retreating=false;g.ai_last_raid_tick=-1800
 g.commands.clear();g._ai_army(isolated,ownhome)
 check("active exploring scout receives no reserve return command",not g.commands.any(func(c):return scout.id in c.get("ids",[])))
 check("active scout movement goal and epoch preserved",scout.state=="move" and scout.dest==scout_dest and scout.work_epoch==scout_epoch)
 check("under-quorum military reserve still moves home",g.commands.any(func(c):return c.type=="order" and reserve.id in c.get("ids",[]) and c.position==home.pos) and reserve.id not in g.ai_raid_members)
 print(JSON.stringify({"suite":"raid_reinforcement_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size()}))
 g.free();quit(0 if checks.all(func(c):return c.passed) else 1)
