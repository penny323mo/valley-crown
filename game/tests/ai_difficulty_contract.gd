extends SceneTree
const D=preload("res://scripts/ai_difficulty.gd")
const R=preload("res://scripts/ai_raid_reinforcement.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func run():
 check("standard interval unchanged",D.interval("standard","conquest","standard")==1800)
 check("lower pressure interval doubled",D.interval("standard","conquest","easy")==3600)
 check("lower pressure first raid waits exactly 180 seconds",not D.initial_ready("standard","conquest","easy",3599) and D.initial_ready("standard","conquest","easy",3600))
 check("standard first raid has no new time gate",D.initial_ready("standard","conquest","standard",0))
 check("unsupported modes do not acquire easy behavior",D.valid_for("pressure","conquest","easy")=="standard" and D.valid_for("standard","control","easy")=="standard")
 var castle={"id":100,"owned":true,"alive":true,"remembered":false,"team":1,"built":true,"category":"building","kind":"town_center","pos":Vector3.ZERO}
 var army=[]
 for i in 8:army.append({"id":i+1,"owned":true,"alive":true,"remembered":false,"team":1,"category":"unit","kind":"spearman","state":"idle","pos":Vector3(2,0,2)})
 check("standard reinforcement retains full ready cohort",R.batch(army,[99],castle,"standard",1800,0)==[1,2,3,4,5,6,7,8])
 check("lower pressure refuses early reinforcement",R.batch(army,[99],castle,"standard",3599,0,"easy").is_empty())
 check("lower pressure reinforcement caps five normally ready troops",R.batch(army,[99],castle,"standard",3600,0,"easy")==[1,2,3,4,5])
 check("insufficient mustered units still cannot reinforce",R.batch(army.slice(0,4),[99],castle,"standard",3600,0,"easy").is_empty())
 var g=load("res://main.tscn").instantiate();g.ai_difficulty="easy";root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false)
 await process_frame
 check("new match preserves selected pressure",g.ai_difficulty=="easy")
 var snapshot=Codec.capture(g)
 check("new pressure checkpoint validates",Codec.validate(snapshot))
 for value in ["hard","",1,null]:
  var bad=snapshot.duplicate(true);bad.game.ai_difficulty=value
  check("malformed pressure rejected "+str(value),not Codec.validate(bad))
 var absent=snapshot.duplicate(true);absent.game.erase("ai_difficulty")
 check("missing new field rejected not migrated",not Codec.validate(absent))
 var wrong=snapshot.duplicate(true);wrong.game.victory_mode="control"
 check("unsupported easy save rejected",not Codec.validate(wrong))
 var h=load("res://main.tscn").instantiate();root.add_child(h);h.set_process(false);h.test_mode=true
 check("save restore preserves pressure and raid timing",Restore.apply(h,snapshot) and h.ai_difficulty=="easy" and h.ai_last_raid_tick==g.ai_last_raid_tick)
 var mismatch=snapshot.duplicate(true);mismatch.build="other-build"
 check("cross build restore remains rejected",not Restore.apply(h,mismatch))
 check("identical opening resources no difficulty bonus",h.economy.bank_milli(0)==g.economy.bank_milli(0) and h.economy.bank_milli(1)==g.economy.bank_milli(1))
 check("identical opening visibility and units",h.visible_cells==g.visible_cells and h.entities.size()==g.entities.size())
 # Same real initial entity state and actual visibility, controlled raid-ready cohort.
 var keep=g._first(1,"town_center")
 for offset in [Vector3(-3,0,-2),Vector3(-3,0,-1),Vector3(-3,0,0),Vector3(-3,0,1),Vector3(-3,0,2),Vector3(3,0,1),Vector3(3,0,2),Vector3(3,0,-1)]:
  var unit=g._spawn("spearman",1,keep.pos+offset);g._set_stance(unit,"STOP")
 g._spawn("scout",1,Vector3(-16,0,24));g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
 var records=g._ai_records();var ownkeep=g.faction_views[1].get_record(keep.id)
 g.tick_count=3599;g._ai_army(records,ownkeep)
 check("native lower pressure gate queues no raid before 180 seconds",g.ai_raids==0 and g.ai_raid_members.is_empty())
 g.commands.clear();g.tick_count=3600;g._ai_army(records,ownkeep)
 var orders=g.commands.filter(func(c):return c.type=="order" and c.get("target",-1)==g._first(0,"town_center").id)
 check("native lower pressure first raid contains at most five",g.ai_raids==1 and g.ai_raid_members.size()==5 and orders.size()==1 and orders[0].ids.size()==5)
 check("native departure records actual capped cohort",g.ai_raid_departure_count==5)
 # Existing home emergency overrides offensive cohort policy; it is not capped.
 g._tick(.05)
 var intruders=[]
 for offset in [Vector3(3,0,0),Vector3(3,0,-1),Vector3(3,0,1)]:intruders.append(g._spawn("spearman",0,keep.pos+offset).id)
 g._update_vision(false);g._publish_faction_views();g._refresh_work_memory();g._ai_army(g._ai_records(),g.faction_views[1].get_record(keep.id))
 var defenders=[]
 for command in g.commands:
  if command.type=="order" and command.get("target",-1) in intruders:defenders.append_array(command.ids)
 check("lower pressure never caps urgent home defense",g.ai_status.get("army","")=="home_defense" and defenders.size()>5)
 check("home defense does not create a new offensive departure",g.ai_raids==1 and g.ai_raid_departure_count==5)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_difficulty_contract","checks":checks,"failed":failed,"scope":"Native policy, controlled ready cohort, and strict checkpoint validation/restore. Separate natural match run required; no balance or physical phone claim."}))
 quit(1 if failed else 0)
