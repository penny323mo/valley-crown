extends SceneTree
const L=preload("res://scripts/battlefield_layout.gd")
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var c=[];var routes=[]
func _initialize():call_deferred("run")
func ck(n,v):
 c.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func counts(rs):
 var a={}
 for r in rs:a[r.kind]=a.get(r.kind,0)+1
 return a
func endpoints(g,mover,team):
 var side=1.0 if team==0 else -1.0
 return [g._cell(g._nearest_free(Vector3(-20.5,0,24.5)*side,8,team,mover)),g._cell(g._nearest_free(Vector3(20.5,0,-24.5)*side,8,team,mover))]
func run():
 var v=L.expansion_resources("valley")+L.mineral_resources("valley")
 var forest=L.expansion_resources("woodland")+L.mineral_resources("woodland")
 var map=L.expansion_resources("iron_crossroads")+L.mineral_resources("iron_crossroads")
 ck("distinct from both existing layouts and same resource totals",map!=v and map!=forest and counts(map)==counts(v) and counts(map)==counts(forest))
 var keys={}
 for r in map:keys[r.pos]=r.kind
 ck("all resource cells unique and antipodally paired",keys.size()==map.size() and map.all(func(r):return keys.get(-r.pos)==r.kind and fposmod(r.pos.x,1.0)==.5 and fposmod(r.pos.z,1.0)==.5))
 ck("four near-home stone and iron deposits per side exact", range(24).all(func(i):return i%6>=4 or map[map.size()-24+i]==v[v.size()-24+i]))
 var g=load("res://main.tscn").instantiate();g.layout_id="iron_crossroads";g.skirmish_mode="standard";g.victory_mode="conquest";g.history_path="/tmp/iron-crossroads-geometry-only"
 root.add_child(g);g.set_process(false);await process_frame
 ck("real standard match seeded with crossroads identity",g.layout_id=="iron_crossroads" and g.skirmish_mode=="standard" and g.ai_enabled and g.economy.bank_milli(0)=={"food":150000,"wood":200000,"stone":100000,"iron":0})
 var static_cells={};var conflicts=[]
 var found=0;var center=0
 for r in g.entities:
  if not r.alive or r.category=="unit":continue
  for cell in g._occupied_cells(r):
   if static_cells.has(cell):conflicts.append([r.kind,r.pos,static_cells[cell]])
   static_cells[cell]=r.pos
  if keys.get(r.pos)==r.kind:found+=1
  if r.kind=="iron" and maxf(absf(r.pos.x),absf(r.pos.z))<5:
   if g.navigation.is_point_solid(g._cell(r.pos)):center+=1
 ck("actual initial map contains all map resources, no collision overlap",found==map.size() and conflicts.is_empty())
 ck("four forward iron deposits are actual navigation obstacles",center==4)
 var living=g.entities.filter(func(e):return e.alive and e.team in [0,1] and e.category=="unit")
 ck("both spawn teams share ordinary five villagers and one scout; none on new obstruction",living.size()==12 and living.all(func(e):return not g.navigation.is_point_solid(g._cell(e.pos))))
 var restored=Codec.capture_result(g)
 ck("initial map exact checkpoint captured",restored.ok and restored.data.game.layout_id=="iron_crossroads" and Codec.validate(restored.data))
 # Full-known route measurement is geometry only. Real fog and AI proven separately.
 for team in 2:g.visible_cells[team].fill(1);g.explored_cells[team].fill(1)
 g._refresh_work_memory()
 for team in 2:
  for kind in ["spearman","siege"]:
   var mover={"id":-99,"kind":kind,"team":team,"radius":Rules.UNIT_RADII[kind]}
   var grid=g._route_grid(mover);var ends=endpoints(g,mover,team)
   var legs={}
   for lane in [-1,0,1]:
    var edits=[]
    for x in Rules.MAP_SIZE:
     for z in range(38,43):
      var cell=Vector2i(x,z);var wx=g._point(cell).x
      var okay=absf(wx)<=5.5 if lane==0 else (wx*lane>=10 and wx*lane<=20)
      if not okay and not grid.is_point_solid(cell):grid.set_point_solid(cell);edits.append(cell)
    var path=grid.get_id_path(ends[0],ends[1])
    var label="team %d %s lane %d"%[team,kind,lane]
    ck(label+" traversable through actual map",not path.is_empty() and path[0]==ends[0] and path[-1]==ends[1])
    legs[str(lane)]=path.size()
    for cell in edits:grid.set_point_solid(cell,false)
   routes.append({"team":team,"unit":kind,"legs":legs})
   ck("central direct route shorter than both flanks for team %d %s"%[team,kind],legs["0"]>0 and legs["-1"]>legs["0"] and legs["1"]>legs["0"])
 var ok=c.all(func(row):return row.passed)
 print("CROSSROADS_GEOMETRY_EVIDENCE "+JSON.stringify({"conflicts":str(conflicts),"routes":routes}))
 print(JSON.stringify({"suite":"iron_crossroads_geometry","scope":"Real initial authored map; controlled full-known navigation only, not natural AI or battle balance.","checks":c,"failed":c.filter(func(x):return not x.passed).size()}))
 g.free();await process_frame;quit(0 if ok else 1)
