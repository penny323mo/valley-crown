extends SceneTree
var g
var checks=[]
var shots=[]
var errors=[]
var proof={"scope":"Ordinary survival scenario with disclosed preplaced troops; ordinary movement, actual hostile injury, entry and exit commands, then visible-resource gathering. No HP, position, resource, time or vision mutation."}
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func shot(label,focus,ids):
 g._select(ids);g.camera_focus=focus;g.camera_zoom=14;g._camera_update();g._update_visuals(0);g._update_hud()
 shots.append({"stage":label,"tick":g.tick_count})
 if DisplayServer.get_name()=="headless":return
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var err=ERR_INVALID_DATA if image==null or image.is_empty() else image.save_png("/tmp/capture/garrison-"+label+".png")
 if err!=OK:errors.append({"stage":label,"error":err})
func _initialize():call_deferred("run")
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture");root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";g.history_path="/tmp/garrison-natural-history-"+str(Time.get_ticks_usec())
 root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 var worker=g._first(0,"villager");var keep=g._first(0,"town_center")
 var army=[]
 for record in g.faction_views[0].records().values():
  if record.get("owned",false) and record.kind in ["spearman","archer","cavalry","siege"]:army.append(record.id)
 var original_bank=g.economy.bank_milli(0).duplicate(true)
 var hit=false;var entered=false;var exit_sent=false;var released=false;var harvest=false;var delivered=false
 var safe_ticks=0;var phase_start=0;var berry=-1;var start=Time.get_ticks_msec()
 g._submit("order",{"ids":[worker.id],"position":Vector3(-14,0,17)})
 proof.initial_worker={"id":worker.id,"hp":worker.hp,"position":str(worker.pos)}
 for i in 6500:
  if Time.get_ticks_msec()-start>285000 or g.game_over:break
  g._tick(g.Rules.TICK)
  if not worker.alive:proof.death_tick=g.tick_count;break
  if not hit and worker.hp<worker.max_hp:
   hit=true;proof.hit_tick=g.tick_count;proof.hit_hp=worker.hp;proof.hit_position=str(worker.pos)
   g._submit("garrison",{"ids":[worker.id],"building":keep.id})
   g._submit("advance",{"ids":army,"position":Vector3(-15,0,18)})
   phase_start=g.tick_count
  if hit and g.tick_count==phase_start+1:await shot("injured-return",worker.pos,[worker.id])
  if not entered and worker.get("garrison_host",-1)==keep.id:
   entered=true;proof.entry_tick=g.tick_count;proof.entry_hp=worker.hp;proof.entry_position=str(worker.pos)
   await shot("inside",keep.pos,[keep.id])
  if entered and not exit_sent:
   var threat=false
   for r in g.faction_views[0].records().values():
    if r.get("alive",false) and not r.get("remembered",false) and r.get("team",-1)==1 and r.get("category","")=="unit" and r.pos.distance_to(keep.pos)<12:threat=true
   safe_ticks=0 if threat else safe_ticks+1
   if safe_ticks>=200:
    exit_sent=true;proof.exit_requested_tick=g.tick_count
    g._submit("ungarrison",{"building":keep.id,"count":1})
  if exit_sent and not released and not worker.has("garrison_host"):
   released=true;proof.exit_tick=g.tick_count;proof.exit_hp=worker.hp;proof.exit_position=str(worker.pos)
   await shot("released",keep.pos,[worker.id])
   var closest=INF
   for r in g.faction_views[0].records().values():
    if not r.get("alive",false) or r.get("remembered",false) or r.get("kind","")!="berry":continue
    var distance=r.pos.distance_squared_to(keep.pos)
    if distance<closest:closest=distance;berry=r.id
   if berry>=0:g._submit("order",{"ids":[worker.id],"target":berry})
  if released and not harvest and g._cargo_amount(worker)>0:
   harvest=true;proof.harvest_tick=g.tick_count;proof.cargo=g._cargo_amount(worker)
   await shot("working",worker.pos,[worker.id])
  if harvest and g.economy.bank_milli(0).food>original_bank.food:
   delivered=true;proof.delivery_tick=g.tick_count;break
 proof.ticks=g.tick_count;proof.stages=shots;proof.errors=errors;proof.original_bank=original_bank;proof.final_bank=g.economy.bank_milli(0)
 proof.audit=g.economy.audit();proof.rendered=DisplayServer.get_name()!="headless";proof.elapsed_ms=Time.get_ticks_msec()-start
 check("normal scenario starts with living villager",proof.initial_worker.hp==35)
 check("villager suffers real combat damage",hit)
 check("ordinary command walks injured villager into own keep",entered and proof.get("entry_tick",0)>proof.get("hit_tick",0))
 check("entry preserves surviving hit points without free healing",entered and proof.get("entry_hp",0)>0 and proof.get("entry_hp",36)<=proof.get("hit_hp",0))
 check("exit follows observed safe interval and ordinary command",released and proof.get("exit_tick",0)>proof.get("exit_requested_tick",0))
 check("exit preserves garrison hit points",released and proof.get("exit_hp",-1)==proof.get("entry_hp",-2))
 check("normal visible-resource gathering resumes",berry>=0 and harvest)
 check("gathered food is normally delivered",delivered)
 check("economy audit remains clean",proof.audit.get("ok",false))
 check("history remains isolated and test mode enabled",g.test_mode and not FileAccess.file_exists(g.history_path))
 check("journey finishes inside bounded budget",delivered and g.tick_count<=6500 and proof.elapsed_ms<=285000)
 check("all four screenshots recorded and native writes succeed",shots.size()==4 and errors.is_empty())
 var failed=checks.filter(func(c):return not c.passed).size()
 var report={"suite":"garrison_natural_journey","checks":checks,"failed":failed,"scope":proof.scope}
 for pair in [["garrison-natural-proof.json",proof],["garrison-natural-contract.json",report]]:
  var f=FileAccess.open("/tmp/capture/"+pair[0],FileAccess.WRITE)
  if f==null:quit(1);return
  f.store_string(JSON.stringify(pair[1]));f.close()
 print("GARRISON_NATURAL_PROOF "+JSON.stringify(proof));print(JSON.stringify(report));quit(1 if failed else 0)
