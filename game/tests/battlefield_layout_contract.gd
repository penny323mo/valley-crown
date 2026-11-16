extends SceneTree
const Layout=preload("res://scripts/battlefield_layout.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var proofs=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func signature(r):return r.kind+":"+str(r.pos)
func counts(resources):
 var out={}
 for r in resources:out[r.kind]=out.get(r.kind,0)+1
 return out
func run():
 check("unknown layout defaults to valley",Layout.valid("unknown")=="valley")
 check("woodland identity retained",Layout.valid("woodland")=="woodland")
 for mode in ["practice","standard","pressure"]:check(mode+" conquest supports choice",Layout.supported(mode,"conquest"))
 for mode in ["battle","fortress","survival","expedition","escort","unknown"]:check(mode+" does not silently change map",not Layout.supported(mode,"conquest"))
 for victory in ["control","supply","unknown"]:check(victory+" remains unchanged",not Layout.supported("standard",victory))
 var expected=[]
 for team in 2:
  var sign_team=1.0 if team==0 else -1.0
  for i in 6:expected.append({"kind":"pine" if i%3 else "oak","pos":Vector3(floorf(-13+(i%3)*1.5)+.5,0,floorf(8+floor(i/3.0)*1.5)+.5)*sign_team})
  for i in 3:expected.append({"kind":"berry","pos":Vector3(floorf(-9+i*1.5)+.5,0,11.5)*sign_team})
 for p in [Vector3(-3.5,0,-1.5),Vector3(-.5,0,-1.5),Vector3(2.5,0,-1.5)]:expected.append({"kind":"berry","pos":p});expected.append({"kind":"berry","pos":-p})
 check("valley exact old expansion ordering",Layout.expansion_resources("valley")==expected)
 expected=[]
 for team in 2:
  for kind in ["stone","iron"]:
   for p in Rules.MINERAL_POINTS[kind]:expected.append({"kind":kind,"pos":Vector3(p[0],0,p[1])*(1 if team==0 else -1)})
 check("valley exact old mineral ordering",Layout.mineral_resources("valley")==expected)
 check("expansion per-kind totals unchanged",counts(Layout.expansion_resources("valley"))==counts(Layout.expansion_resources("woodland")))
 check("mineral per-kind totals unchanged",counts(Layout.mineral_resources("valley"))==counts(Layout.mineral_resources("woodland")))
 for layout in ["valley","woodland"]:
  var resources=Layout.expansion_resources(layout)+Layout.mineral_resources(layout)
  var keys={};var unique=true;var symmetric=true;var centered=true
  for r in resources:
   var key=signature(r)
   if keys.has(key):unique=false
   keys[key]=true
   if absf(r.pos.x)>35 or absf(r.pos.z)>35 or not is_equal_approx(absf(r.pos.x-floorf(r.pos.x)),.5) or not is_equal_approx(absf(r.pos.z-floorf(r.pos.z)),.5):centered=false
  for r in resources:
   if not keys.has(signature({"kind":r.kind,"pos":-r.pos})):symmetric=false
  check(layout+" exact antipodal kind symmetry",symmetric)
  check(layout+" unique resource positions",unique)
  check(layout+" all resource centers on in-bounds cells",centered)
  var near=true
  var minerals=Layout.mineral_resources(layout)
  for i in minerals.size():
   if i%6<4 and minerals[i]!=expected[i]:near=false
  check(layout+" first four home deposits unchanged",near)
  await full_map(layout)
 check("all six layout and unit route proofs executed",proofs.size()==6)
 var result={"suite":"battlefield_layout_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Complete fixed resource geometry with actual game navigation and large-unit clearance, controlled full knowledge; not natural match balance or fog evidence"}
 var diagnostic=FileAccess.open("/tmp/battlefield-layout-route-proof.json",FileAccess.WRITE)
 diagnostic.store_string(JSON.stringify(proofs,"  "));diagnostic.close()
 print(JSON.stringify(result));quit(0 if result.failed==0 else 1)
func full_map(layout):
 var g=load("res://main.tscn").instantiate();g.history_path="/tmp/layout-contract-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 await process_frame
 var original=Layout.expansion_resources("valley")+Layout.mineral_resources("valley")
 var replacement=Layout.expansion_resources(layout)+Layout.mineral_resources(layout)
 var changed={}
 for i in original.size():
  var match=g.entities.filter(func(e):return e.category=="resource" and e.kind==original[i].kind and e.pos==original[i].pos and not changed.has(e.id))
  if match.size()!=1:check(layout+" old resource mapping "+str(i),false);continue
  var e=match[0];changed[e.id]=true;e.pos=replacement[i].pos;e.node.position=e.pos
 check(layout+" replaces precisely original movable resources",changed.size()==original.size())
 var occupied={};var clear=true
 for e in g.entities:
  if not e.alive or e.category=="unit":continue
  for c in g._occupied_cells(e):
   if occupied.has(c):clear=false
   occupied[c]=e.id
 check(layout+" no static overlap against complete starting map",clear)
 g._navigation_rebuild()
 for team in 2:g.visible_cells[team].fill(1);g.explored_cells[team].fill(1)
 g._refresh_work_memory()
 for kind in ["spearman","cavalry","siege"]:
  var mover={"id":-99,"kind":kind,"team":0,"radius":Rules.UNIT_RADII[kind]}
  var grid=g._route_grid(mover)
  var start=g._cell(g._nearest_free(Vector3(-20.5,0,24.5),8,0,mover))
  var finish=g._cell(g._nearest_free(Vector3(20.5,0,-24.5),8,0,mover))
  var entries=[]
  for wing in [-1,1]:
   var via=g._cell(Vector3(10.5*wing,0,.5*wing))
   # Prove each flank independently: disallow the middle/opposite flank
   # in the midfield crossing band. This only removes options, never clears
   # actual obstacles or invents a traversable tile.
   var restricted=[]
   for x in Rules.MAP_SIZE:
    for z in range(38,43):
     var cell=Vector2i(x,z);var wx=g._point(cell).x
     var allowed=(wx>=-18 and wx<=-9) if wing==-1 else (wx>=9 and wx<=18)
     if not allowed and not grid.is_point_solid(cell):grid.set_point_solid(cell);restricted.append(cell)
   var a=grid.get_id_path(start,via);var b=grid.get_id_path(via,finish)
   var connected=not a.is_empty() and not b.is_empty() and a[0]==start and a[-1]==via and b[0]==via and b[-1]==finish
   check(layout+" "+kind+" wing "+str(wing)+" complete route",connected)
   var safe=true
   for c in a:
    if grid.is_point_solid(c):safe=false
   for c in b:
    if grid.is_point_solid(c):safe=false
   check(layout+" "+kind+" wing "+str(wing)+" respects actual clearance",safe and connected)
   entries.append({"wing":wing,"via":via,"first":a.size(),"second":b.size()})
   for cell in restricted:grid.set_point_solid(cell,false)
  if layout=="woodland":
   var center=g._cell(Vector3(.5,0,.5))
   check(kind+" middle gap remains traversable",not grid.get_id_path(start,center).is_empty() and not grid.get_id_path(center,finish).is_empty())
  proofs.append({"layout":layout,"kind":kind,"start":start,"finish":finish,"wings":entries})
 if layout=="woodland":
  var tree=g.entities.filter(func(e):return e.category=="resource" and e.pos==Vector3(-4.5,0,-1.5))[0]
  check("central forest is actual resource navigation obstruction",tree.kind in ["pine","oak"] and g.navigation.is_point_solid(g._cell(tree.pos)))
 check(layout+" history untouched",not FileAccess.file_exists(g.history_path))
 g.free();await process_frame
