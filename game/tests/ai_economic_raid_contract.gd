extends SceneTree
const Policy=preload("res://scripts/ai_economic_raid.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func run():
 var rider={"id":1,"category":"unit","remembered":false,"owned":true,"alive":true,"team":1,"kind":"cavalry","pos":Vector3(0,0,0)}
 var worker={"id":2,"category":"unit","owned":false,"alive":true,"remembered":false,"team":0,"kind":"villager","state":"gather","pos":Vector3(2,0,0)}
 var keep={"id":3,"category":"building","kind":"town_center","pos":Vector3(-25,0,24),"radius":2.0,"remembered":false}
 var bad=rider.duplicate();bad.remembered=true
 check("remembered attacker rejected",Policy.choose(bad,[worker],keep).is_empty())
 bad=rider.duplicate();bad.category="building"
 check("nonunit attacker rejected",Policy.choose(bad,[worker],keep).is_empty())
 var bad_worker=worker.duplicate();bad_worker.category="building"
 check("nonunit worker rejected",Policy.choose(rider,[bad_worker],keep).is_empty())
 check("exposed current visible worker is raided",Policy.choose(rider,[worker],keep).get("id")==2)
 worker.remembered=true
 check("remembered workers are never raided",Policy.choose(rider,[worker],keep).is_empty())
 worker.remembered=false;worker.state="build"
 check("enemy private work state is not consulted",Policy.choose(rider,[worker],keep).get("id")==2)
 worker.state="deliver"
 check("selection does not depend on private work state",Policy.choose(rider,[worker],keep).get("id")==2)
 worker.pos=keep.pos+Vector3(1,0,0);rider.pos=keep.pos+Vector3(6,0,0)
 check("home economy buffer is respected",Policy.choose(rider,[worker],keep).is_empty())
 rider.pos=Vector3.ZERO;worker.pos=Vector3(2,0,0)
 for kind in ["spearman","archer","cavalry","siege","tower"]:
  var guard={"id":4,"category":"building" if kind=="tower" else "unit","owned":false,"alive":true,"remembered":false,"team":0,"kind":kind,"built":true,"pos":Vector3(3,0,0),"radius":1.0}
  check(kind+" protects nearby economy",Policy.choose(rider,[worker,guard],keep).is_empty())
  guard.remembered=true
  check(kind+" hidden state does not affect decision",Policy.choose(rider,[worker,guard],keep).get("id")==2)
 worker.pos=Vector3(30,0,0)
 check("shared remote observation cannot divert cavalry",Policy.choose(rider,[worker],keep).is_empty())
 worker.pos=Vector3(2,0,0);rider.kind="spearman"
 check("infantry stay with main assault",Policy.choose(rider,[worker],keep).is_empty())
 var g=load("res://main.tscn").instantiate();g.history_path="/tmp/economic-raid-contract-history.json"
 root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 await process_frame
 # Controlled fixture proving normal AI command integration, not natural progression.
 var cav=g._spawn("cavalry",1,Vector3(0,0,7))
 var victim=g._spawn("villager",0,Vector3(2,0,7))
 victim.state="gather";victim.resource_target=g._first(-1,"berry").id
 g._update_vision();g._publish_faction_views()
 var records=g.faction_views[1].records().values()
 var sanitized=g.faction_views[1].records()[victim.id]
 check("real enemy observation exposes neither state nor target",not sanitized.has("state") and not sanitized.has("target"))
 check("policy chooses actual sanitized enemy observation",Policy.choose(g.faction_views[1].records()[cav.id],records,keep).get("id")==victim.id)
 g._ai_raid_order(g.faction_views[1].records()[cav.id],records,keep)
 check("actual AI raid submits normal target order",g.commands.size()>0 and g.commands[-1].get("target",-1)==victim.id)
 check("command uses enemy team",g.commands[-1].team==1)
 var before=g.economy.bank_milli(1).duplicate()
 g._tick(g.Rules.TICK)
 check("normal order executes without economy gift",g.economy.bank_milli(1)==before and cav.target==victim.id)
 var guard=g._spawn("spearman",0,Vector3(3,0,7))
 g._update_vision();g._publish_faction_views();g.commands.clear()
 g._ai_raid_order(g.faction_views[1].records()[cav.id],g.faction_views[1].records().values(),keep)
 check("visible guard redirects cavalry from worker",not g.commands.is_empty() and g.commands[-1].get("target",-1)==guard.id)
 g.commands.clear()
 var observed=g.faction_views[1].records()[cav.id].duplicate(true)
 observed.state="attack";observed.target=victim.id
 var hidden=worker.duplicate(true);hidden.id=victim.id;hidden.remembered=true
 var known_keep=keep.duplicate(true);known_keep.remembered=true
 g._ai_raid_order(observed,[observed,hidden],known_keep)
 check("lost worker vision cancels old pursuit for ground keep order",not g.commands.is_empty() and g.commands[-1].get("target",-1)==-1 and g.commands[-1].get("position")==keep.pos)
 g.commands.clear()
 var visible_keep=keep.duplicate(true);visible_keep.remembered=false
 var nearby=worker.duplicate(true);nearby.id=victim.id;nearby.pos=keep.pos+Vector3(2,0,0)
 observed.pos=keep.pos+Vector3(6,0,0)
 g._ai_raid_order(observed,[observed,nearby],visible_keep)
 check("home worker cannot bypass policy through fallback",not g.commands.is_empty() and g.commands[-1].get("target",-1)==keep.id)
 for kind in ["spearman","archer"]:
  var infantry=observed.duplicate(true);infantry.kind=kind;infantry.pos=Vector3.ZERO;infantry.target=-1;infantry.state="idle"
  var exposed=worker.duplicate(true);exposed.category="unit";exposed.pos=Vector3(2,0,0)
  var original=g.RaidTactics.choose(infantry,[exposed])
  g.commands.clear();g._ai_raid_order(infantry,[exposed],visible_keep)
  check(kind+" original target selection remains identical",not original.is_empty() and not g.commands.is_empty() and g.commands[-1].get("target",-1)==original.id)
 check("resource conservation maintained",g.economy.audit().ok)
 g.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_economic_raid_contract","checks":checks,"failed":failed}));quit(0 if failed==0 else 1)
