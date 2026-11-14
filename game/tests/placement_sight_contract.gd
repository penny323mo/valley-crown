extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var checks=[]
func _initialize(): call_deferred("run")
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 print(("PASS " if ok else "FAIL ")+label)
func reset():
 g._cancel_mode(); g._test_reset()
 for e in g.entities:
  if e.category=="unit": g._set_stance(e,"STOP")
func run():
 g=load("res://main.tscn").instantiate(); root.add_child(g); g.test_mode=true; g.set_process(false)
 reset()
 var geometry=[]
 for e in g.entities: geometry.append({"kind":e.kind,"category":e.category,"pos":[e.pos.x,e.pos.z],"alive":e.alive,"radius":e.radius})
 FileAccess.open("res://reports/placement-opening-oracle-inputs.json",FileAccess.WRITE).store_string(JSON.stringify({"entities":geometry,"visible":Array(g.visible_cells[0])}))
 var worker=g._first(0,"villager")
 var candidate=Vector3.INF
 # Natural opening sight. Find genuinely clear ground rejected by old halo.
 for z in range(15,33):
  for x in range(-35,-15):
   var p=Vector3(x+0.5,0,z+0.5)
   if not g._placement_reason("range",p,0,worker.id).is_empty(): continue
   var outside_dark=false
   for c in g._occupied_cells({"kind":"range","pos":p}):
    for dy in range(-1,3):
     for dx in range(-1,3):
      var q=c+Vector2i(dx,dy)
      if g.visible_cells[0][q.y*Rules.MAP_SIZE+q.x]==0: outside_dark=true
   if outside_dark: candidate=p; break
  if candidate!=Vector3.INF: break
 check("natural-opening-visible-empty-edge-plot-no-arbitrary-halo",candidate!=Vector3.INF)
 if candidate!=Vector3.INF:
  var bank=g.economy.bank_milli(0).duplicate(true)
  g._select([worker.id]); g._start_build("range"); g.pointer_world=candidate; g.build_preview_held=true; g._update_ghost(); g._update_hud()
  check("real-preview-green-and-confirm-enabled",g.placement_ok and not g.build_confirm.disabled)
  g._confirm_build(); check("confirmation-queues-without-debit",g.commands.size()==1 and g.economy.bank_milli(0)==bank)
  g._execute(g.commands.pop_front())
  check("actual-site-created-and-exact-cost-debited",g._count(0,"range")==1 and g.stocks[0].wood==80)
 reset(); worker=g._first(0,"villager"); worker.pos=Vector3(14,0,14); worker.node.position=worker.pos; g._update_vision()
 var site=Vector3(17,0,14)
 check("visible-far-from-home-plot-legal",g._placement_reason("house",site,0,worker.id).is_empty())
 var home=g._first(0,"town_center")
 check("site-more-than-thirty-from-keep",site.distance_to(home.pos)>30)
 var created=g._place_building("house",site,worker.id,0)
 check("remote-actual-build-order-created",not created.is_empty() and worker.state=="build")
 if not created.is_empty():
  g._test_advance(40)
  check("remote-worker-completes-house",created.built)
 reset(); worker=g._first(0,"villager")
 g.visible_cells[0].fill(0)
 var p=Vector3(12,0,12)
 var footprint=g._occupied_cells({"kind":"house","pos":p})
 for c in footprint: g.visible_cells[0][c.y*Rules.MAP_SIZE+c.x]=1
 g._refresh_work_memory(); g._publish_faction_views()
 check("only-footprint-visible-is-enough",g._placement_reason("house",p,0,worker.id).is_empty())
 var blocker=g._spawn("barracks",1,Vector3(13.5,0,12.5)); g._navigation_rebuild(); g._refresh_work_memory(); g._publish_faction_views()
 check("partly-visible-overlapping-building-is-observed",g._visible_to(blocker,0) and not g.faction_views[0].get_record(blocker.id).is_empty())
 check("actual-overlap-still-blocks",g._placement_reason("house",p,0,worker.id)=="與建築或資源重疊")
 blocker.pos=Vector3(25,0,25); g._navigation_rebuild(); g._refresh_work_memory(); g._publish_faction_views()
 check("entirely-hidden-building-not-observed",not g._visible_to(blocker,0))
 check("entirely-hidden-building-does-not-change-clear-site",g._placement_reason("house",p,0,worker.id).is_empty())
 var dark=footprint[0]; g.visible_cells[0][dark.y*Rules.MAP_SIZE+dark.x]=0
 check("actual-footprint-fog-remains-explicit",g._placement_reason("house",p,0,worker.id)=="先派村民探索建築範圍")
 reset(); worker=g._first(0,"villager"); g.visible_cells[0].fill(1); g._refresh_work_memory(); g._publish_faction_views()
 p=Vector3(12,0,12)
 g._pay({"wood":200},0,g.Economy.REFUND_STARTED)
 g._select([worker.id]); g._start_build("range"); g.pointer_world=p; g.build_preview_held=true; g._update_ghost(); g._update_hud()
 check("clear-land-shortage-not-a-geometric-block",g._placement_reason("range",p,0,worker.id,false).is_empty())
 check("insufficient-funds-explicit-and-confirm-disabled",g.selection_detail.text.contains("資源不足") and g.queue_label.text.contains("資源不足") and g.build_confirm.disabled)
 check("clear-unaffordable-land-is-amber-not-red",g.ghost.get_child(0).material_override.albedo_color==Color("e4bc68"))
 var before=g.economy.bank_milli(0).duplicate(true); g._confirm_build()
 check("shortage-never-queues-or-debits",g.commands.is_empty() and g.economy.bank_milli(0)==before)
 reset(); worker=g._first(0,"villager"); g.visible_cells[0].fill(0)
 footprint=g._occupied_cells({"kind":"house","pos":p})
 for c in footprint: g.visible_cells[0][c.y*Rules.MAP_SIZE+c.x]=1
 var unit=g._first(1,"scout"); unit.pos=Vector3(13.1,0,12)
 check("unit-disk-intersecting-visible-site-is-observed",g._visible_to(unit,0))
 check("intersecting-unit-still-prevents-site",g._placement_reason("house",p,0,worker.id)=="地點有單位")
 unit.pos=Vector3(25,0,25)
 check("entirely-hidden-unit-not-observed",not g._visible_to(unit,0))
 check("entirely-hidden-unit-does-not-change-clear-site",g._placement_reason("house",p,0,worker.id).is_empty())
 var view=load("res://scripts/faction_view.gd").new()
 var remembered={"id":991,"kind":"barracks","category":"building","owned":false,"team":1,"pos":Vector3(13.5,0,12.5)}
 view.publish({991:remembered},g.visible_cells[0],1)
 view.publish({},g.visible_cells[0],2)
 check("visible-footprint-absence-retires-memory-with-hidden-centre",view.get_record(991).is_empty())
 var failed=checks.filter(func(r):return not r.passed).size()
 print(JSON.stringify({"suite":"placement_sight_contract","checks":checks,"failed":failed,"scope":"Native real preview/confirmation/build lifecycle with controlled placement visibility and actors; not phone/browser screenshot."}))
 quit(1 if failed else 0)
