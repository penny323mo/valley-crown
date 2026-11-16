extends SceneTree
## All state is created in this isolated run. No historical checkpoint samples.
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
var g
var histories=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh():
 var h=load("res://main.tscn").instantiate()
 h.history_path="/tmp/wall-contract-history-%d.json" % Time.get_ticks_usec();histories.append(h.history_path)
 root.add_child(h);h.set_process(false);h.test_mode=true;h.ai_enabled=false
 return h
func ticks(n):
 for i in n:g._tick(Rules.TICK)
func site_for(worker):
 for distance in range(2,9):
  for dz in range(-distance,distance+1):
   for dx in range(-distance,distance+1):
    var point=g._snap_build_position("wall",worker.pos+Vector3(dx,0,dz))
    if g._placement_reason("wall",point,0,worker.id).is_empty():return point
 return Vector3.INF
func run():
 check("wall is ordinary buildable", "wall" in Rules.BUILDABLE_KINDS)
 check("wall price exactly thirty wood",Rules.COSTS.wall=={"wood":30})
 check("wall ten second construction",Rules.BUILD_TIME.wall==10.0)
 check("wall two cell footprint",Rules.FOOTPRINT.wall==2)
 check("wall defensive values",Rules.HP.wall==250 and Rules.ARMOR.wall==0 and Rules.SIGHT.wall==1)
 g=fresh();await process_frame
 var w=g._first(0,"villager");var tree=g._nearest_known_resource(w.pos,"wood",0)
 g._submit("order",{"ids":[w.id],"target":tree.id,"position":tree.pos});ticks(1)
 var point=site_for(w);check("legal visible wall site exists",point!=Vector3.INF)
 var bank=g.economy.bank_milli(0).wood
 var next_id=g.next_id
 g._submit("build",{"builder":w.id,"ids":[w.id],"kind":"wall","position":point});ticks(1)
 var site=g._get_entity(next_id)
 check("normal command creates wall site",not site.is_empty() and site.kind=="wall" and not site.built)
 if site.is_empty():finish();return
 check("build charges exactly once",g.economy.bank_milli(0).wood==bank-30000)
 check("site has actual cost receipt",not site.cost_receipt_id.is_empty())
 check("wall construction captures old gather job",w.has("construction_return") and w.construction_return.resource==tree.id)
 var paid_bank=g.economy.bank_milli(0).wood
 g._submit("build",{"builder":w.id,"ids":[w.id],"kind":"wall","position":point});ticks(1)
 check("occupied wall placement does not charge twice",g.economy.bank_milli(0).wood==paid_bank)
 var occupied=g._occupied_cells(site)
 check("unfinished wall blocks all four cells",occupied.size()==4 and occupied.all(func(c):return g.navigation.is_point_solid(c)))
 var snapshot=Codec.capture(g);check("fresh midbuild wall capture valid",not snapshot.is_empty())
 var h=fresh();await process_frame
 check("fresh midbuild wall restore succeeds",Restore.apply(h,snapshot))
 check("restored unfinished wall blocks same cells",h._occupied_cells(h._get_entity(site.id))==occupied and occupied.all(func(c):return h.navigation.is_point_solid(c)))
 h.paused=false
 var elapsed=0
 while not site.built and elapsed<1800:
  ticks(1);h._tick(Rules.TICK);elapsed+=1
 check("normal worker travel and construction completes",site.built and site.hp==250)
 check("construction requires paid work time",site.build_ticks>=int(Rules.BUILD_TIME.wall/Rules.TICK))
 check("finisher resumes previous gathering or delivery",w.state in ["gather","deliver"] and not w.has("construction_return"))
 check("midbuild restored continuation is identical",Codec.capture(g)==Codec.capture(h))
 var complete=Codec.capture(g);check("completed wall capture valid",not complete.is_empty() and Codec.validate(complete))
 check("completed wall restores",Restore.apply(h,complete) and h._get_entity(site.id).built)
 h.free()
 # Controlled damage only; ordinary repair route/work/payment below.
 site.hp-=40;site.last_damage_tick=-1000
 var damaged=site.hp
 g._update_vision();g._publish_faction_views()
 g._submit("order",{"ids":[w.id],"target":site.id,"position":site.pos});ticks(1)
 check("normal contextual wall repair accepted",w.state=="repair" and w.target==site.id)
 for i in 1600:
  if site.hp>=site.max_hp:break
  ticks(1)
 check("normal worker repair restores wall",site.hp>damaged and site.hp==site.max_hp)
 bank=g.economy.bank_milli(0).wood
 g._submit("demolish",{"building":site.id});ticks(1)
 check("ordinary demolition removes completed wall",not site.alive)
 check("demolition gives no wood refund",g.economy.bank_milli(0).wood==bank)
 check("demolition releases footprint",occupied.all(func(c):return not g.navigation.is_point_solid(c)))
 point=site_for(w);bank=g.economy.bank_milli(0).wood
 var canceled=g._place_building("wall",point,w.id,0)
 check("second paid wall placed",not canceled.is_empty())
 if not canceled.is_empty():
  g._submit("cancel_build",{"building":canceled.id});ticks(1)
  var refund_bank=g.economy.bank_milli(0).wood
  check("cancel uses existing floored seventy five percent refund",not canceled.alive and refund_bank==bank-8000)
  g._submit("cancel_build",{"building":canceled.id});ticks(1)
  check("repeat cancellation cannot duplicate refund",g.economy.bank_milli(0).wood==refund_bank)
 check("wall economy conserved",g.economy.audit().ok)
 g.free();await process_frame
 g=fresh();await process_frame
 var old_shape=Codec.capture(g)
 check("fresh existing world without wall retains checkpoint shape",not old_shape.is_empty() and old_shape.entities.all(func(e):return e.kind!="wall") and Codec.validate(old_shape))
 await geometry()
 finish()
func geometry():
 # Explicit controlled wall line, not paid natural construction or fog evidence.
 var walls=[]
 for x in [-8,-6,-4,0,2,4,6,8]:walls.append(g._spawn("wall",0,Vector3(x,0,25),true))
 g._navigation_rebuild()
 for team in 2:g.visible_cells[team].fill(1);g.explored_cells[team].fill(1)
 g._refresh_work_memory()
 for width in [2,3]:
  if width==3:
   # Same controlled wall fixture opens one additional real grid column.
   for wall in walls:
    if wall.pos.x>=0:wall.pos.x+=1;wall.node.position=wall.pos
   g._navigation_rebuild();g._refresh_work_memory()
  for kind in ["spearman","cavalry","siege"]:
   var mover={"id":-999,"kind":kind,"team":0,"radius":Rules.UNIT_RADII[kind]}
   var grid=g._route_grid(mover)
   var start=g._cell(Vector3(-1,0,21));var goal=g._cell(Vector3(-1,0,29))
   # Only remove alternate crossings; never clear actual obstacle cells.
   var added=[]
   for z in [24,25]:
    for x in range(-39,39):
     if x>=-2 and x<width-2:continue
     var cell=g._cell(Vector3(x+.5,0,z+.5))
     if grid.region.has_point(cell) and not grid.is_point_solid(cell):grid.set_point_solid(cell);added.append(cell)
   var route=grid.get_id_path(start,goal)
   var expected=width==3 or kind=="spearman"
   if expected:
    check(kind+" "+str(width)+" cell opening has complete true clearance route",not route.is_empty() and route[0]==start and route[-1]==goal)
    var through=false;var safe=true
    for cell in route:
     var p=g._point(cell)
     if p.z>=24 and p.z<26 and p.x>=-2 and p.x<width-2:through=true
     if grid.is_point_solid(cell):safe=false
    check(kind+" "+str(width)+" cell route crosses actual opening",through and safe)
   else:
    check(kind+" two cell opening correctly rejected by large-unit clearance",route.is_empty())
   check(kind+" "+str(width)+" cell wall body stays blocked",grid.is_point_solid(g._cell(walls[2].pos)))
   for cell in added:grid.set_point_solid(cell,false)
func finish():
 var untouched=true
 for path in histories:
  if FileAccess.file_exists(path):untouched=false
 check("isolated histories untouched",untouched)
 var result={"suite":"wall_construction_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Fresh ordinary paid wall construction repair and cancellation plus controlled real-grid two/three-cell clearance; dynamic in-memory checkpoints only, not natural battle or visual proof"}
 print(JSON.stringify(result));if is_instance_valid(g):g.free()
 quit(0 if result.failed==0 else 1)
