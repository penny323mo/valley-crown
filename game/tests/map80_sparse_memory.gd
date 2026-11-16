extends SceneTree
## Isolated overlap/move/death/owned-overlay contract for the sparse grid.
const Memory=preload("res://scripts/faction_work_memory.gd")
var checks=[]
func _initialize(): call_deferred("run")
func check(label,ok,detail={}):
	checks.append({"name":label,"pass":bool(ok),"detail":detail})
	print(("PASS " if ok else "FAIL ")+label+" "+JSON.stringify(detail))
func record(id,cells,alive=true): return {"id":id,"category":"resource","alive":alive,"cells":cells}
func same_cells(actual,expected):
	if actual.size()!=expected.size(): return false
	for cell in expected:
		if not actual.has(cell): return false
	return true
func run():
	var memory=Memory.new()
	var a=Vector2i(70,70); var b=Vector2i(71,70); var c=Vector2i(72,70)
	var d=Vector2i(74,70); var e=Vector2i(75,70)
	var observed={7:record(7,[a,b]),8:record(8,[b,c])}
	var change=memory.observe(observed,{}, {},1)
	check("overlap-adds-union-once",same_cells(change.cells,[a,b,c]) and memory.revision==1 and memory.grid.is_point_solid(b))
	var revision=memory.revision
	change=memory.observe(observed,{}, {},2)
	check("identical-observation-no-revision-or-cell-churn",change.cells.is_empty() and not change.records_changed and memory.revision==revision)
	change=memory.observe({}, {}, {},3)
	check("unseen-overlap-remains-frozen",change.cells.is_empty() and not change.records_changed and memory.revision==revision and memory.grid.is_point_solid(a) and memory.grid.is_point_solid(b) and memory.grid.is_point_solid(c))
	change=memory.observe({7:record(7,[a,b],false)}, {}, {},4)
	check("one-overlap-owner-dies-shared-cell-remains",same_cells(change.cells,[a]) and memory.revision==revision+1 and not memory.grid.is_point_solid(a) and memory.grid.is_point_solid(b) and memory.grid.is_point_solid(c))
	revision=memory.revision
	change=memory.observe({8:record(8,[d,e])}, {}, {},5)
	check("observed-move-releases-old-and-adds-new-union",same_cells(change.cells,[b,c,d,e]) and memory.revision==revision+1 and not memory.grid.is_point_solid(b) and not memory.grid.is_point_solid(c) and memory.grid.is_point_solid(d) and memory.grid.is_point_solid(e))
	revision=memory.revision
	change=memory.observe({}, {9:{"id":9}}, {d:true},6)
	check("owned-overlay-changes-record-not-already-solid-cell",change.cells.is_empty() and change.records_changed and memory.revision==revision+1 and memory.grid.is_point_solid(d))
	revision=memory.revision
	change=memory.observe({8:record(8,[d,e],false)}, {9:{"id":9}}, {d:true},7)
	check("observed-death-keeps-owned-overlap",same_cells(change.cells,[e]) and memory.revision==revision+1 and memory.grid.is_point_solid(d) and not memory.grid.is_point_solid(e))
	revision=memory.revision
	change=memory.observe({}, {}, {},8)
	check("owned-removal-releases-last-overlap",same_cells(change.cells,[d]) and memory.revision==revision+1 and not memory.grid.is_point_solid(d))
	revision=memory.revision
	change=memory.observe({}, {}, {},9)
	check("empty-repeat-does-not-invalidate-path-revision",change.cells.is_empty() and not change.records_changed and memory.revision==revision)
	var boundaries=true
	for p in [Vector2i(0,0),Vector2i(1,40),Vector2i(78,40),Vector2i(79,79)]: boundaries=boundaries and memory.grid.is_point_solid(p)
	check("fixed-new-map-boundaries-survive-sparse-updates",boundaries and memory.grid.region.size==Vector2i(80,80))
	var failed=checks.filter(func(row): return not row.pass).size()
	var report={"passed":checks.size()-failed,"failed":failed,"checks":checks,"scope":"Isolated real FactionWorkMemory sparse updates; not game/phone/visual acceptance."}
	print("MAP80_SPARSE_MEMORY "+JSON.stringify(report))
	if not OS.get_cmdline_user_args().is_empty(): FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(1 if failed else 0)
