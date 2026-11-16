extends SceneTree
var g
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func reset():
 g._test_reset([{"food":2000,"wood":2000,"stone":2000,"iron":1000},{"food":2000,"wood":2000,"stone":2000,"iron":1000}]);g.set_process(false);g.ai_enabled=false
func crew_fixture(count):
 reset();var site=g._spawn("tower",0,Vector3(14,0,14),false)
 g._navigation_rebuild();g.visible_cells[0].fill(1);g._refresh_work_memory()
 var crew=[]
 for cell in g._perimeter_cells(site):
  var p=g._point(cell);var clear=true
  for worker in crew:
   if worker.pos.distance_to(p)<1:clear=false
  if not clear:continue
  var worker=g._spawn("villager",0,p,true);worker.state="build";worker.target=site.id;crew.append(worker)
  if crew.size()==count:break
 g._update_vision(false)
 return {"site":site,"crew":crew}
func work(fixture,ticks):
 for i in ticks:
  g.tick_count+=1
  for worker in fixture.crew:g._update_unit(worker,g.Rules.TICK)
func _initialize():call_deferred("run")
func run():
 g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g.set_process(false);await process_frame
 for count in range(1,6):
  var f=crew_fixture(count);work(f,20)
  check("bounded work for crew "+str(count),f.site.build_ticks==[0,20,30,40,50,50][count])
  check("construction hp only follows earned work "+str(count),f.site.hp==ceili(f.site.max_hp*0.1)+floori((f.site.max_hp-ceili(f.site.max_hp*0.1))*f.site.build_ticks/900.0))
 var f=crew_fixture(4);work(f,1);var earned=f.site.build_ticks
 for worker in f.crew:g._update_unit(worker,g.Rules.TICK)
 check("same tick repeated calls cannot double work",f.site.build_ticks==earned)
 f.crew[1].alive=false;f.crew[2].pos=Vector3(25,0,25);f.crew[3].team=1
 var before=f.site.build_ticks;work(f,20)
 check("dead distant and opposing workers never contribute",f.site.build_ticks==before+20)
 f=crew_fixture(4);f.site.hp-=10;work(f,10)
 check("damage is not erased by cooperative work",f.site.hp==f.site.construction_hcap-10)
 reset();var ids=[]
 for i in 4:
  var worker=g._spawn("villager",0,Vector3(12,0,12+i),true);ids.append(worker.id)
 g._update_vision(false);g._publish_faction_views();g._select(ids)
 var bank=g.economy.bank_milli(0).duplicate()
 g._start_build("tower");g.pointer_world=Vector3(17,0,14);g.build_preview_held=true;g._update_ghost();g._update_hud();g._confirm_build()
 check("public confirm captures selected four workers",g.commands.size()==1 and g.commands[0].ids==ids)
 if not g.commands.is_empty():g._execute(g.commands.pop_front())
 var site=g._first(0,"tower")
 check("one site and one ordinary price for whole crew",not site.is_empty() and g._count(0,"tower")==1 and g.economy.bank_milli(0).wood==bank.wood-80000 and g.economy.bank_milli(0).stone==bank.stone-100000)
 var assigned=0
 for id in ids:
  var worker=g._get_entity(id)
  if worker.state=="build" and not site.is_empty() and worker.target==site.id:assigned+=1
 check("all captured workers assigned to same site",assigned==4)
 g._test_advance(35)
 check("actual cooperative tower completes before solo45seconds",not site.is_empty() and site.built)
 check("ledger remains conserved",g.economy.audit().ok)
 reset();var own=g._first(0,"villager");var enemy=g._first(1,"villager");bank=g.economy.bank_milli(0).duplicate()
 g._execute({"type":"build","team":0,"kind":"house","position":Vector3(17,0,14),"builder":own.id,"ids":[own.id,enemy.id]})
 check("foreign helper rejects before payment",g.economy.bank_milli(0)==bank and g._count(0,"house")==0)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"cooperative_build_contract","build":g.Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"funded controlled authority plus real public confirm and simulated construction route; not physical phone or natural balance"}));g.queue_free();quit(1 if failed else 0)
