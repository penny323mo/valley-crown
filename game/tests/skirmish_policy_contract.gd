extends SceneTree
const Policy=preload("res://scripts/skirmish_policy.gd")
class Fixture:
 extends "res://scripts/game.gd"
 var issued=[]
 func _submit(type: String,data: Dictionary={},team=0): issued.append({"type":type,"data":data,"team":team})
 func _ai_move_home(_army,_castle): pass
 func _ai_scout(_ent): pass
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok: push_error(name)
func run_case(mode,count,tick,known=true,remembered=false,threat=false):
 var g=Fixture.new();g.skirmish_mode=mode;g.tick_count=tick;g.ai_last_raid_tick=0
 var castle={"owned":true,"alive":true,"team":1,"kind":"town_center","category":"building","pos":Vector3.ZERO,"radius":2.0}
 var records=[castle]
 for i in count: records.append({"id":i+1,"owned":true,"alive":true,"remembered":false,"team":1,"kind":"spearman","category":"unit","pos":Vector3(2,0,0),"state":"idle","target":-1})
 if known: records.append({"id":90,"owned":false,"alive":true,"remembered":remembered,"team":0,"kind":"town_center","category":"building","pos":Vector3(25,0,25),"radius":2.0})
 if threat: records.append({"id":91,"owned":false,"alive":true,"remembered":false,"team":0,"kind":"scout","category":"unit","pos":Vector3(3,0,0),"radius":0.35})
 g._ai_army(records,castle)
 var result={"status":g.ai_status.army,"commands":g.issued.duplicate(true),"raids":g.ai_raids}
 g.free();return result
func _initialize():
 check("invalid policy defaults standard",Policy.valid("cheat")=="standard")
 check("standard exact existing policy",Policy.muster("standard")==5 and Policy.interval("standard")==1800)
 check("pressure 3 and 60 seconds",Policy.muster("pressure")==3 and Policy.interval("pressure")==1200)
 for mode in ["standard","pressure"]:
  var n=Policy.muster(mode);var interval=Policy.interval(mode)
  check(mode+" muster threshold",run_case(mode,n-1,interval).raids==0)
  check(mode+" cooldown minus1",run_case(mode,n,interval-1).raids==0)
  var result=run_case(mode,n,interval)
  check(mode+" exact boundary ordinary order",result.raids==1 and result.commands.size()==1 and result.commands[0].type=="order" and result.commands[0].data.ids.size()==n)
  check(mode+" unseen keep no raid",run_case(mode,n,interval,false).raids==0)
  result=run_case(mode,n,interval,true,true)
  check(mode+" remembered target ground only",result.commands.size()==1 and result.commands[0].data.target==-1)
  check(mode+" home defense priority",run_case(mode,n,interval,true,false,true).status=="home_defense")
 check("practice no offensive raid",run_case("practice",10,999999).raids==0)
 check("practice still defends",run_case("practice",5,999999,true,false,true).status=="home_defense")
 var failed=checks.filter(func(c):return not c.passed).size()
 print("SKIRMISH ",checks.size()-failed,"/",checks.size())
 var args=OS.get_cmdline_user_args()
 if args.size(): var f=FileAccess.open(args[0],FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failed":failed},"  "))
 quit(1 if failed else 0)
