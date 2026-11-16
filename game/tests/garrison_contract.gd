extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.history_path="/tmp/garrison-contract-history-%d.json"%Time.get_ticks_usec();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;return g
func old_position(w):return w.pos
func shelter(g,w,host):
 if not g._order_garrison([w.id],host.id,w.team):return false
 for t in 500:
  g._tick(.05)
  if w.has("garrison_host"):return true
 return false
func run():
 var g=fresh();await process_frame
 var w=g._first(0,"villager");var host=g._first(0,"town_center");var pop=g._population(0,false);var start=w.pos
 check("reject enemy host",not g._order_garrison([w.id],g._first(1,"town_center").id,0))
 check("reject bool host",not g._order_garrison([w.id],true,0))
 check("reject military occupant",not g._order_garrison([g._first(0,"scout").id],host.id,0))
 var original=g.economy.bank_milli(0).duplicate()
 check("manual shelter starts ordinary motion",g._order_garrison([w.id],host.id,0) and w.state=="move" and w.has("garrison_pending") and not w.has("garrison_host") and w.pos==start)
 check("pending checkpoint valid",not Codec.capture(g).is_empty())
 var pending=Codec.capture(g);var clone=fresh();await process_frame
 check("pending checkpoint restores paused candidate",Restore.apply(clone,pending) and clone.paused)
 clone.paused=false
 for t in 50:g._tick(.05);clone._tick(.05)
 check("pending restore arrives identically",w.has("garrison_host") and clone._get_entity(w.id).get("garrison_host",-1)==host.id and clone._get_entity(w.id).pos==w.pos)
 check("entry consumes walking ticks not teleport",g.tick_count>0 and w.pos!=start and g._attack_distance(w.pos,host)<=1.1)
 check("inside remains live population",w.alive and g._population(0,false)==pop)
 check("shelter is free",g.economy.bank_milli(0)==original)
 check("no ground faction publication",g.faction_views[0].get_record(w.id).is_empty() and g.faction_views[1].get_record(w.id).is_empty())
 check("host publication gives occupancy",g.faction_views[0].get_record(host.id).garrison_count==1)
 check("resident cannot be observed",not g._visible_to(w,0) and not g._visible_to(w,1))
 g._select([w.id]);check("direct resident selection refused",g.selected.is_empty())
 g._select_group("villager");check("all villagers shortcut excludes resident",w.id not in g.selected)
 g._begin_unit_motion();check("resident excluded motion priority",w not in g.traffic_priority_order)
 check("resident no longer occupies entry disk",g._known_destination_clear(g._first(0,"scout"),old_position(w)))
 var enemy=g._first(1,"villager");var attack=g._release_attack(enemy,w)
 check("resident attack release rejected",not attack.ok)
 var oldpos=w.pos;g._order_move(w,Vector3.ZERO);g._order(w,"gather",-1)
 check("resident cannot receive direct ground task",w.has("garrison_host") and w.pos==oldpos and w.state=="idle")
 g._update_visuals(0);check("resident hidden visual node",not w.node.visible)
 var saved=Codec.capture(g);check("inside checkpoint valid",not saved.is_empty())
 var h=fresh();await process_frame
 check("inside checkpoint restores",Restore.apply(h,saved))
 check("restored resident immediately hidden",not h._get_entity(w.id).node.visible)
 h.paused=false
 var hp=w.hp
 for t in 250:g._tick(.05);h._tick(.05)
 check("no resident healing or income",w.hp==hp and g.economy.bank_milli(0)==original)
 check("inside restore continuation same",h._get_entity(w.id).hp==w.hp and h._population(0,false)==pop and h._get_entity(w.id).garrison_host==host.id)
 check("reject bool exit count",not g._ungarrison(host.id,true,0))
 check("reject invalid exit batch",not g._ungarrison(host.id,100,0))
 check("ordinary bounded exit succeeds",g._ungarrison(host.id,1,0) and not w.has("garrison_host") and w.alive and w.state=="idle")
 check("exit preserves population and bank",g._population(0,false)==pop and g.economy.bank_milli(0)==original)
 check("exit uses free static ground",not g.navigation.is_point_solid(g._cell(w.pos)))
 g._update_vision();g._update_visuals(0)
 check("exit ground visible and selectable",not g.faction_views[0].get_record(w.id).is_empty() and w.node.visible)
 g._select([w.id]);check("exit unit selectable",g.selected==[w.id])
 # Accepting a later manual order cancels the reservation without teleport.
 g._order_garrison([w.id],host.id,0)
 g._submit("order",{"ids":[w.id],"target":-1,"position":Vector3(-21,0,27)})
 g._tick(.05)
 check("manual map order cancels pending entry",not w.has("garrison_pending") and not w.has("garrison_host"))
 g._order_garrison([w.id],host.id,0);g._path_stop(w,g.BoundedPath.NO_PATH,"controlled_test")
 check("terminal path releases reservation",not w.has("garrison_pending"))
 # Fresh controlled crowd fixtures test reservation/exit boundaries, not natural play.
 var c=fresh();await process_frame
 var ch=c._first(0,"town_center");var workers=[]
 for e in c.entities:
  if e.alive and e.team==0 and e.kind=="villager":workers.append(e)
 while workers.size()<6:workers.append(c._spawn("villager",0,Vector3(-21,0,25+workers.size()),true))
 var ids=[]
 for e in workers:ids.append(e.id)
 check("batch permits five reservations only",c._order_garrison(ids,ch.id,0) and c._garrison_members(ch.id,true).size()==5 and not workers[5].has("garrison_pending"))
 var full_epoch=workers[5].get("work_epoch",0);var full_state=workers[5].state
 check("full shelter refusal preserves other worker task",not c._order_garrison([workers[5].id],ch.id,0) and workers[5].get("work_epoch",0)==full_epoch and workers[5].state==full_state)
 check("repeat command cannot double reserve",not c._order_garrison([workers[0].id,workers[0].id],ch.id,0) and c._garrison_members(ch.id,true).size()==5)
 c._set_stance(workers[0],"STOP")
 check("stop frees slot for another",c._order_garrison([workers[5].id],ch.id,0) and c._garrison_members(ch.id,true).size()==5)
 # Two natural-distance arrivals suffice to verify collision-free sequential exit.
 var z=fresh();await process_frame
 var zh=z._first(0,"town_center");var zw=z._first(0,"villager")
 check("second fixture reaches shelter",shelter(z,zw,zh))
 var other={}
 for e in z.entities:
  if e.alive and e.team==0 and e.kind=="villager" and e.id!=zw.id:other=e;break
 check("second worker walks into same keep",shelter(z,other,zh))
 var blocked=[]
 for cell in z._production_exit_cells(zh,"villager"):
  if not z.navigation.is_point_solid(cell):blocked.append(z._spawn("spearman",0,z._point(cell),true))
 check("blocked exits retain residents",not z._ungarrison(zh.id,5,0) and z._garrison_members(zh.id,false).size()==2 and zw.alive and other.alive)
 for e in blocked:z._kill(e)
 check("cleared exits release batch",z._ungarrison(zh.id,5,0) and z._garrison_members(zh.id,false).is_empty())
 check("released disks do not overlap",zw.pos.distance_to(other.pos)>=zw.radius+other.radius)
 # A legitimately issued hit is still settled before arrival; later releases cannot hit shelter.
 var a=fresh();await process_frame
 var aw=a._first(0,"villager");var ah=a._first(0,"town_center")
 shelter(a,aw,ah);a._ungarrison(ah.id,1,0)
 var foe=a._spawn("spearman",1,aw.pos+Vector3(.7,0,0),true)
 a._update_vision();var before_hit=aw.hp
 check("controlled adjacent attack genuinely issued",a._release_attack(foe,aw).applied)
 a._order_garrison([aw.id],ah.id,0);a._tick(.05)
 check("arrival does not dodge prior issued damage",aw.hp<before_hit)
 for t in 60:
  if aw.has("garrison_host"):break
  a._tick(.05)
 var sheltered_hp=aw.hp;foe.cooldown_ticks=0
 check("later attack cannot target resident",aw.has("garrison_host") and not a._release_attack(foe,aw).ok)
 for t in 10:a._tick(.05)
 check("resident takes no later attack damage",aw.hp==sheltered_hp)
 var guard=a._first(0,"scout");var guard_epoch=guard.get("work_epoch",0);var guard_state=guard.state
 a._order_escort([guard.id],aw.id,0)
 check("resident escort replacement rejected atomically",guard.get("work_epoch",0)==guard_epoch and guard.state==guard_state)
 # Farm occupancy releases via ledger, cargo is neither deposited nor discarded.
 var f=fresh();await process_frame
 var fw=f._first(0,"villager");var fh=f._first(0,"town_center");var farm=f._spawn("farm",0,Vector3(-20,0,26),true)
 f._order(fw,"gather",farm.id)
 for t in 200:f._tick(.05)
 var cargo=f._cargo_amount(fw);var before=f.economy.bank_milli(0).duplicate()
 check("controlled farmer has real harvest",cargo>0 and f.economy.farm_view(farm.id).worker_id==fw.id)
 check("harvesting worker reaches shelter",shelter(f,fw,fh))
 check("entry frees exclusive farm slot",f.economy.farm_view(farm.id).worker_id==-1)
 check("entry preserves carried harvest",f._cargo_amount(fw)==cargo and f.economy.bank_milli(0)==before)
 check("carrying resident checkpoint valid",not Codec.capture(f).is_empty())
 var population_before_death=f._population(0,false)
 var cargo_before_death=f.economy._workers[fw.id].cargo_milli
 f._kill(fh)
 check("destroyed keep kills residents",not fw.alive and not fw.has("garrison_host") and f._population(0,false)==population_before_death-1)
 check("resident death settles cargo",f.economy._workers[fw.id].cargo_milli==0 and not f.economy._workers[fw.id].alive and cargo_before_death>0)
 var after=f.economy.snapshot();f._kill(fh)
 check("repeat destruction idempotent",f.economy.snapshot()==after)
 check("destruction checkpoint remains valid",not Codec.capture(f).is_empty())
 for size in [Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;z._update_vision();z._select([zh.id]);z._update_hud();z._layout_ui()
  for t in 3:await process_frame
  check("keep summary occupancy "+str(size),z.selection_summary.text.contains("避難 0/5"))
  check("keep warning truthful "+str(size),z.selection_detail.text.contains("堡內村民亦會死亡"))
  for name in ["GarrisonNearby","UngarrisonOne","UngarrisonAll"]:
   var button=z.actions.get_node_or_null(name)
   check("reachable shelter button "+name+str(size),button!=null and button.size.y>=44)
  z._select([zw.id]);z._update_hud()
  for t in 2:await process_frame
  check("selected villager shelter action "+str(size),z.actions.get_node_or_null("GarrisonSelected")!=null)
 check("ledger conservation after all shelter actions",g.economy.audit().ok and z.economy.audit().ok and f.economy.audit().ok)
 for match_game in [g,h,c,z,f,clone,a]:match_game.queue_free()
 var failed=checks.filter(func(v):return not v.passed).size()
 print(JSON.stringify({"suite":"garrison_contract","checks":checks,"failed":failed,"scope":"Controlled shelter entry, exit, ground exclusion and checkpoint boundaries; not natural combat or physical phone proof"}))
 quit(1 if failed else 0)
