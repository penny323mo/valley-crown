extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
var g
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func fresh():
 var h=load("res://main.tscn").instantiate();h.test_mode=true;h.history_path="/tmp/construction-return-contract-history-%d.json" % Time.get_ticks_usec();root.add_child(h);h.set_process(false);h.test_mode=true;h.ai_enabled=false
 return h
func run():
 g=fresh();await process_frame
 var w=g._first(0,"villager");var tree=g._nearest_known_resource(w.pos,"wood",0)
 g._order(w,"gather",tree.id)
 var site=g._spawn("house",0,Vector3(32.5,0,32.5),false)
 g._order(w,"build",site.id)
 check("gather build captures exact prior intent",w.get("construction_return",{})=={"site":site.id,"resource":tree.id,"type":"wood"})
 var data=Codec.capture(g)
 check("new optional intent captures",not data.is_empty())
 var h=fresh();await process_frame
 check("fresh paused candidate restores intent",Restore.apply(h,data) and h._get_entity(w.id).construction_return==w.construction_return)
 check("same boundary roundtrip exact",Codec.capture(h)==data)
 var bads=[{}, {"site":site.id,"resource":tree.id,"type":"gold"},{"site":float(site.id),"resource":tree.id,"type":"wood"},{"site":site.id,"resource":-1,"type":"wood"},{"site":site.id,"resource":tree.id,"type":"wood","extra":1},null]
 for bad in bads:
  var changed=data.duplicate(true)
  for e in changed.entities:
   if e.id==w.id:e.construction_return=bad
  check("reject malformed intent "+str(bad),not Codec.validate(changed))
  var before=Codec.capture(h)
  check("bad restore leaves candidate untouched "+str(bad),not Restore.apply(h,changed) and Codec.capture(h)==before)
 var store=load("res://scripts/checkpoint_store.gd")
 var slot="/tmp/construction-return-isolated-%d.bin" % Time.get_ticks_usec()
 g.paused=true
 check("fresh exact build slot saves valid intent",store.save_slot(g,slot).ok)
 var saved_bytes=FileAccess.get_file_as_bytes(slot)
 var keep_intent=w.construction_return.duplicate()
 w.construction_return={"site":site.id,"resource":tree.id,"type":"bad"}
 check("invalid intent cannot replace existing slot",not store.save_slot(g,slot).ok and FileAccess.get_file_as_bytes(slot)==saved_bytes and not FileAccess.file_exists(slot+".tmp"))
 w.construction_return=keep_intent
 DirAccess.remove_absolute(slot)
 var forged=data.duplicate(true)
 for e in forged.entities:
  if e.id==w.id:e.construction_return.resource=-5
 var payload=var_to_bytes(forged);var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload)
 var envelope={"magic":Codec.MAGIC,"schema":Codec.SCHEMA,"build":g.Rules.BUILD_ID,"sha256":hash.finish().hex_encode(),"payload":payload}
 check("checksum valid malformed intent still fails decode",not Codec.decode(var_to_bytes(envelope),g.Rules.BUILD_ID).ok)
 var legacy=data.duplicate(true)
 for e in legacy.entities:e.erase("construction_return")
 check("same build absent optional field remains valid",Codec.validate(legacy))
 g._set_stance(w,"STOP");check("stop clears intent",not w.has("construction_return"))
 g._order(w,"build",site.id);check("idle worker has no automatic job",not w.has("construction_return"))
 g._order(w,"gather",tree.id);g._order(w,"build",site.id);g._order_move(w,w.pos+Vector3(1,0,0));check("move clears intent",not w.has("construction_return"))
 g._order(w,"gather",tree.id);g._order(w,"build",site.id);g._path_stop(w,"NO_PATH","test");check("bounded route failure clears intent",not w.has("construction_return"))
 g._order(w,"gather",tree.id);g._order(w,"build",site.id);g._kill(site);check("site destruction clears without resume",not w.has("construction_return") and w.state=="build")
 h.free();g.free()
 await crew_case("house")
 await crew_case("farm")
 await boundaries()
 await natural()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"construction_return_contract","checks":checks,"failed":failed,"scope":"Fresh isolated intent validation and ordinary paid construction continuation; no historical samples or physical phone proof"}))
 quit(1 if failed else 0)
func natural():
 g=fresh();await process_frame
 var w=g._first(0,"villager");var tree={}
 var known=g._gather_records(0)
 for r in known.values():
  if r.alive and r.kind in ["pine","oak"]:
   if tree.is_empty() or w.pos.distance_squared_to(r.pos)<w.pos.distance_squared_to(tree.pos):tree=r
 check("natural initial visible wood exists",not tree.is_empty())
 if tree.is_empty():g.free();return
 g._order(w,"gather",tree.id)
 for i in 800:g._tick(.05)
 check("ordinary gathering establishes earned cargo or wood",g.economy.stats_view(0).extracted.wood>0)
 var point=Vector3.INF
 for z in range(-5,6):
  for x in range(-5,6):
   var p=g._snap_build_position("house",w.pos+Vector3(x,0,z))
   if g._placement_reason("house",p,0,w.id).is_empty():point=p;break
  if point!=Vector3.INF:break
 check("natural legal site found",point!=Vector3.INF)
 if point==Vector3.INF:g.free();return
 var bank=g.economy.bank_milli(0).wood
 var site=g._place_building("house",point,w.id,0)
 check("house paid once and prior work retained",not site.is_empty() and g.economy.bank_milli(0).wood==bank-g.Rules.COSTS.house.wood*1000 and w.has("construction_return"))
 if site.is_empty():g.free();return
 var snapshot=Codec.capture(g);var h=fresh();await process_frame
 check("natural midbuild restored",Restore.apply(h,snapshot));h.paused=false
 var count=0
 while not site.built and count<3000:g._tick(.05);h._tick(.05);count+=1
 check("ordinary travel and paid building completes",site.built)
 check("finisher automatically resumes work or deposit",w.state in ["gather","deliver"] and not w.has("construction_return"))
 var extracted=g.economy.stats_view(0).extracted.wood
 var bank_after_build=g.economy.bank_milli(0).wood
 for i in 800:g._tick(.05);h._tick(.05)
 check("bank increases after ordinary postbuild deliveries",g.economy.bank_milli(0).wood>bank_after_build)
 check("wood extraction continues without player order",g.economy.stats_view(0).extracted.wood>extracted)
 check("saved continuation identical after finish and harvest",Codec.capture(g)==Codec.capture(h))
 check("both economy ledgers conserve",g.economy.audit().ok and h.economy.audit().ok)
 print("NATURAL_RETURN ",JSON.stringify({"ticks":g.tick_count,"build_ticks_elapsed":count,"built":site.built,"state":w.state,"extracted_wood_milli":g.economy.stats_view(0).extracted.wood,"receipt":g.economy.receipt_view(site.cost_receipt_id).state}))
 h.free();g.free()

func boundaries():
 g=fresh();await process_frame
 var w=g._first(0,"villager");var wood=g._nearest_known_resource(w.pos,"wood",0)
 var site=g._spawn("house",0,Vector3(30.5,0,30.5),false)
 g._order(w,"gather",wood.id);g._order(w,"build",site.id)
 g._update_vision(false);g._publish_faction_views();g._select([w.id]);g._update_hud()
 check("owned UI explains automatic return",g.selection_detail.text.contains("完工回採木材"))
 var observer=g._spawn("scout",1,w.pos+Vector3(2,0,0));g._update_vision(false);g._publish_faction_views()
 check("enemy observation cannot expose return intention",not g.faction_views[1].get_record(w.id).is_empty() and not g.faction_views[1].get_record(w.id).has("construction_return_type"))
 g._kill(observer);g._update_vision(false);g._publish_faction_views()
 var invalid=g._spawn("farm",0,Vector3(32.5,0,32.5),true)
 var helper=g._spawn("villager",0,w.pos+Vector3(1,0,0))
 g._order(helper,"gather",invalid.id)
 var before=w.construction_return.duplicate()
 check("occupied farm command rejects atomically",not g._order(w,"gather",invalid.id) and w.construction_return==before)
 var data=Codec.capture(g)
 for kind in ["dead","state","site","team","nonworker"]:
  var d=data.duplicate(true)
  for e in d.entities:
   if e.id!=w.id:continue
   if kind=="dead":e.alive=false
   if kind=="state":e.state="idle"
   if kind=="site":e.construction_return.site=999999;e.target=999999
   if kind=="team":e.team=1
   if kind=="nonworker":e.kind="scout";e.max_hp=g.Rules.HP.scout
  check("reject wrong return context "+kind,not Codec.validate(d))
 var unknown=g._spawn("pine",-1,Vector3(-35,0,-35))
 g._order(w,"gather",wood.id);g._order(w,"build",site.id)
 var carried=g.economy.worker_view(w.id).duplicate(true)
 g._submit("stop",{"ids":[w.id]},0)
 site.built=true;g._construction_return_work(w,site)
 check("pending manual stop prevents automatic continuation",w.state=="idle" and not w.has("construction_return") and g.economy.worker_view(w.id)==carried)
 g.commands.clear();site.built=false
 g._order(w,"gather",wood.id);g._order(w,"build",site.id)
 g._kill(g._get_entity(wood.id));g._update_vision(false);g._publish_faction_views();g._refresh_work_memory();site.built=true;g._construction_return_work(w,site)
 check("depleted original uses known alternative not hidden tree",w.state=="gather" and w.target!=wood.id and w.target!=unknown.id)
 site.built=false;g._order(w,"gather",w.target);g._order(w,"build",site.id)
 var danger=g._spawn("cavalry",1,w.pos+Vector3(1,0,0));g._update_vision(false);g._publish_faction_views()
 site.built=true;g._construction_return_work(w,site)
 check("observed threat leaves worker waiting without repeated intent",w.state=="idle" and not w.has("construction_return"))
 g._kill(danger);site.built=false;wood=g._nearest_known_resource(w.pos,"wood",0)
 g._order(w,"gather",wood.id);g._order(w,"build",site.id);g._kill(w)
 check("worker death clears intent",not w.has("construction_return"))
 check("boundary fixture economy conserves",g.economy.audit().ok)
 g.free()

func crew_case(kind):
 g=fresh();await process_frame
 var site=g._spawn(kind,0,Vector3(31.5,0,31.5),false)
 var pay=g._pay(g.Rules.COSTS[kind],0,g.Economy.REFUND_STARTED)
 site.cost_receipt_id=pay.receipt_id
 g.economy.mark_started(pay.receipt_id,0)
 g._navigation_rebuild()
 var crew=[];var nodes=[]
 var kinds=["pine","berry","stone","iron"]
 for i in 4:
  var node=g._spawn(kinds[i],-1,Vector3(25.5+i*2,0,25.5));nodes.append(node)
  var worker=g._spawn("villager",0,Vector3(29.5+i,0,29.5));crew.append(worker)
  g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
  g._order(worker,"gather",node.id);g._order(worker,"build",site.id)
  var approach=g._free_adjacent(site,worker.pos,false,0,worker)
  worker.pos=approach;worker.node.position=approach
 g._update_vision(false);g._publish_faction_views();g._refresh_work_memory()
 var carried=[]
 for worker in crew:carried.append(g.economy.worker_view(worker.id).duplicate(true))
 for tick in 1000:
  g.tick_count+=1
  for worker in crew:
   if worker.state=="build":g._update_unit(worker,.05)
  if site.built:break
 check(kind+" controlled paid four worker crew completes",site.built and g.economy.receipt_view(pay.receipt_id).state=="fulfilled")
 var farmers=0
 for i in 4:
  var worker=crew[i]
  if worker.get("farm_id",-1)==site.id:farmers+=1
  var right=worker.state=="gather" and (worker.target==nodes[i].id or (kind=="farm" and worker.target==site.id))
  check(kind+" worker "+str(i)+" resumes appropriate work once",right and not worker.has("construction_return"))
  check(kind+" worker "+str(i)+" completion does not alter cargo",g.economy.worker_view(worker.id)==carried[i])
 if kind=="farm":check("only finisher works new farm",farmers==1 and crew[0].farm_id==site.id)
 check(kind+" summary retains all resumed count",g.toast_label.text.contains("村民已返回工作"))
 check(kind+" cooperative economy conserves",g.economy.audit().ok)
 g.free()
