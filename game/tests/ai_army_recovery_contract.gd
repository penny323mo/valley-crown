extends SceneTree
const Policy=preload("res://scripts/ai_army_recovery.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var u={"id":1,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"spearman","hp":35,"max_hp":100,"pos":Vector3(20,0,0)}
 var b={"id":2,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"town_center","built":true,"pos":Vector3.ZERO}
 var before=u.duplicate(true)
 check("critical soldier returns to safe known home",Policy.base_for(u,[b]).get("id",-1)==2)
 check("policy never mutates unit",u==before)
 u.hp=36
 check("noncritical forward troop retains assignment",Policy.base_for(u,[b]).is_empty())
 u.pos=Vector3(6,0,0);u.hp=79
 check("wounded reserve stays until eighty percent",not Policy.base_for(u,[b]).is_empty())
 u.hp=80
 check("eighty percent ready to redeploy",Policy.base_for(u,[b]).is_empty())
 u.hp=20
 var enemy={"id":9,"alive":true,"remembered":false,"team":0,"category":"unit","pos":Vector3(8,0,0)}
 check("unsafe base not recovery destination",Policy.base_for(u,[b,enemy]).is_empty())
 enemy.pos=Vector3(15,0,0)
 check("near resting soldier threat also prevents reserve",Policy.base_for(u,[b,enemy]).is_empty())
 enemy.remembered=true
 check("hidden enemy truth not read",not Policy.base_for(u,[b,enemy]).is_empty())
 u.kind="siege"
 check("unhealable siege excluded",Policy.base_for(u,[b]).is_empty())
 u.kind="villager"
 check("workers never requisitioned",Policy.base_for(u,[b]).is_empty())
 u.kind="spearman";u.owned=false
 check("enemy soldier not ordered",Policy.base_for(u,[b]).is_empty())
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 var home=g._first(1,"town_center");var soldier=g._spawn("spearman",1,home.pos+Vector3(-10,0,0));soldier.hp=10
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 g.ai_raid_members=[soldier.id];g.ai_raid_departure_count=1
 g._ai_army(g._ai_records(),home)
 var orders=g.commands.filter(func(c):return soldier.id in c.get("ids",[]))
 check("actual strategic turn sends critical soldier home",orders.size()==1 and orders[0].type=="order" and orders[0].target==-1 and orders[0].position==home.pos)
 check("withdrawn soldier retired from raid",soldier.id not in g.ai_raid_members)
 g._tick(.05);g._publish_faction_views()
 var epoch=soldier.work_epoch;var failures=soldier.path_failures;var retries=soldier.path_retry_ticks.duplicate()
 g.commands.clear();g._ai_army(g._ai_records(),home)
 check("repeat recovery turn preserves active home route",g.commands.filter(func(c):return soldier.id in c.get("ids",[])).is_empty() and soldier.work_epoch==epoch and soldier.path_failures==failures and soldier.path_retry_ticks==retries)
 var arrived=false
 for i in 1200:
  g._tick(.05)
  if i%20==0:g._ai_army(g._ai_records(),home)
  if soldier.state=="idle" and soldier.pos.distance_to(home.pos)<=7:arrived=true;break
 check("ordinary path movement reaches rest area",arrived)
 var hp=soldier.hp
 for i in 280:
  g._tick(.05)
  if i%20==0:g._ai_army(g._ai_records(),home)
 check("ordinary safe rest actually heals over time",soldier.hp>hp and soldier.hp<soldier.max_hp)
 g.commands.clear();g._update_vision(false);g._publish_faction_views();g._ai_army(g._ai_records(),home)
 check("resting reserve not repeatedly stopped or redirected",g.commands.filter(func(c):return soldier.id in c.get("ids",[])).is_empty())
 # Keep normal AI decisions running while real healing reaches redeploy health.
 var ready_hp=ceili(soldier.max_hp*.8)
 for i in 5000:
  g._tick(.05)
  if i%20==0:g._ai_army(g._ai_records(),home)
  if soldier.hp>=ready_hp:break
 check("reserve physically heals to redeploy threshold",soldier.hp>=ready_hp)
 g.commands.clear();g._update_vision(false);g._publish_faction_views()
 check("healed actual soldier no longer reserved",Policy.base_for(g._ai_records().filter(func(r):return r.id==soldier.id)[0],g._ai_records()).is_empty())
 soldier.hp=10
 # A visible raid at home overrides reserve and invokes normal defensive attack.
 var foe=g._spawn("spearman",0,home.pos+Vector3(-6,0,0));g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g.commands.clear()
 g._ai_army(g._ai_records(),home)
 check("home defense overrides wounded reserve",g.commands.any(func(c):return c.type=="order" and soldier.id in c.get("ids",[]) and c.target==foe.id))
 check("healing does not alter economy ledger",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_army_recovery_contract","checks":checks,"failed":failed,"scope":"Controlled actual retreat and timed healing; not natural-match balance"}))
 g.queue_free();quit(1 if failed else 0)
