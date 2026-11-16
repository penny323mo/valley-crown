extends SceneTree
## Component semantics + bounded publication benchmark, NOT normal-match proof.
const Candidate=preload("res://scripts/faction_view.gd")
const Reference=preload("res://tests/faction_publish_reference.gd")
const Rules=preload("res://scripts/rules.gd")
const REFERENCE_SHA="5862071a65d1d3a0bf513c8ff48258664013a84ef19f63936c2a891e576a5ab5"
const ITERATIONS=30
const TRIALS=6
const WALL_LIMIT_MS=95000
var checks: Array=[]
var benchmarks: Array=[]
var started=0
var destination=""
var expected_build=""
var timed_out=false
func _initialize(): call_deferred("run")
func check(label: String,ok: bool): checks.append({"name":label,"passed":ok})
func remaining() -> bool:
	if Time.get_ticks_msec()-started<WALL_LIMIT_MS: return true
	timed_out=true
	return false
func visible_map(value: int) -> PackedByteArray:
	var cells=PackedByteArray(); cells.resize(Rules.MAP_SIZE*Rules.MAP_SIZE); cells.fill(value)
	return cells
func record(id: int,owned: bool,category: String="unit") -> Dictionary:
	return {"id":id,"owned":owned,"team":0 if owned else 1,"category":category,
		"kind":"villager" if category=="unit" else "house","pos":Vector3(0,0,0),"hp":35,
		"nested":{"queue":[{"kind":"age2","research":true,"cost":{"food":350}}],"tags":["a",[1,2]]},
		"path":PackedVector3Array([Vector3(1,0,1),Vector3(2,0,2)]),"mask":PackedByteArray([1,0,1])}
func deeply_frozen(value) -> bool:
	if value is Dictionary:
		if not value.is_read_only(): return false
		for v in value.values():
			if not deeply_frozen(v): return false
	elif value is Array:
		if not value.is_read_only(): return false
		for v in value:
			if not deeply_frozen(v): return false
	elif value is Object: return false
	elif value is PackedVector3Array or value is PackedByteArray: return false
	return true
func semantics():
	var candidate=Candidate.new(); var reference=Reference.new()
	var source={1:record(1,true),2:record(2,false,"building"),3:record(3,false)}
	var cells=visible_map(1)
	candidate.publish(source,cells,10); reference.publish(source,cells,10)
	var old=candidate.records(); var old_reference=reference.records()
	check("initial public values equal exact reference",old==old_reference)
	check("outer map read only",old.is_read_only())
	check("every nested dictionary and array read only and object free",deeply_frozen(old))
	check("packed vector path becomes immutable value array",old[1].path is Array and old[1].path.is_read_only())
	check("packed bytes become immutable value array",old[1].mask is Array and old[1].mask.is_read_only())
	source[1].nested.queue[0].cost.food=999
	source[1].nested.tags[1].append(3)
	source[1].path[0]=Vector3(99,0,99)
	source[1].mask[0]=9
	source[2].hp=1
	source[1].hp=4
	check("observed nested dictionary mutation isolated",old[1].nested.queue[0].cost.food==350)
	check("observed nested array append isolated",old[1].nested.tags[1]==[1,2])
	check("observed packed path write isolated",old[1].path[0]==Vector3(1,0,1))
	check("observed packed bytes write isolated",old[1].mask==[1,0,1])
	check("observed scalars isolated",old[1].hp==35 and old[2].hp==35)
	check("memory record cannot be mutated through an exposed alias",deeply_frozen(candidate.memory[2]))
	# Hidden building keeps observed data; hidden unit disappears.
	cells.fill(0)
	var owned_only={1:source[1]}
	candidate.publish(owned_only,cells,11); reference.publish(owned_only,cells,11)
	var hidden=candidate.records()
	check("hidden publication equals exact reference",hidden==reference.records())
	check("building remembered with old observed HP",hidden[2].remembered and hidden[2].hp==35 and hidden[2].last_seen_tick==10)
	check("unseen mobile entity not remembered",not hidden.has(3))
	check("current own values update",hidden[1].hp==4 and hidden[1].nested.queue[0].cost.food==999)
	check("retained initial snapshot unchanged",old==old_reference and old[1].hp==35 and not old[2].remembered)
	check("remembered publication deeply immutable",deeply_frozen(hidden))
	# Reacquire with new public data; retained hidden snapshot must remain frozen.
	cells.fill(1)
	var reacquired={1:source[1],2:source[2]}
	candidate.publish(reacquired,cells,12); reference.publish(reacquired,cells,12)
	check("reacquired publication equals exact reference",candidate.records()==reference.records())
	check("reacquired building current and updated",not candidate.records()[2].remembered and candidate.records()[2].hp==1 and candidate.records()[2].last_seen_tick==12)
	check("retained hidden snapshot unchanged",hidden[2].remembered and hidden[2].hp==35)
	candidate.publish(owned_only,cells,13); reference.publish(owned_only,cells,13)
	check("currently visible absence retires static memory",not candidate.records().has(2) and not candidate.memory.has(2))
	check("retirement equals exact reference",candidate.records()==reference.records())
	check("old snapshots survive memory retirement",old.has(2) and hidden.has(2) and deeply_frozen(old) and deeply_frozen(hidden))
	var copy=old.duplicate(true); copy[1].hp=999
	check("mutable duplicate does not mutate prior publication",old[1].hp==35)
	check("publication tick advances normally",candidate.tick==13)
	candidate.publish({},visible_map(1),14); reference.publish({},visible_map(1),14)
	check("empty publication immutable and reference equal",candidate.records().is_empty() and candidate.records().is_read_only() and candidate.records()==reference.records())
func dataset(unit_count: int,static_count: int,path_length: int) -> Dictionary:
	var result={}
	for id in unit_count+static_count:
		var r=record(id,id<unit_count,"unit" if id<unit_count else "resource")
		r.kind="spearman" if id<unit_count else "pine"
		r.pos=Vector3(float(id%16)-8,0,float(id/16)-4)
		if id<unit_count:
			r.path=PackedVector3Array()
			for step in path_length: r.path.append(Vector3(step%32,0,step/32))
		else:
			r.erase("path"); r.erase("nested"); r.erase("mask")
		result[id]=r
	return result
func graph_count(value) -> Dictionary:
	var result={"calls":1,"dictionaries":0,"arrays":0,"scalars":0}
	if value is Dictionary or value is Array:
		result["dictionaries" if value is Dictionary else "arrays"]+=1
		for v in (value.values() if value is Dictionary else value):
			var child=graph_count(v)
			for key in result: result[key]+=child[key]
	else: result.scalars+=1
	return result
func measure(view,first: Dictionary,second: Dictionary,cells: PackedByteArray) -> Dictionary:
	var start=Time.get_ticks_usec(); var completed=0
	for index in ITERATIONS:
		if not remaining(): break
		view.publish(first if index%2==0 else second,cells,100+index); completed+=1
	return {"microseconds":Time.get_ticks_usec()-start,"publications":completed}
func median(values: Array) -> float:
	var copy=values.duplicate(); copy.sort()
	return (float(copy[2])+float(copy[3]))/2.0
func benchmark(label: String,units: int,statics: int,path_length: int):
	var first=dataset(units,statics,path_length); var second=first.duplicate(true)
	for r in second.values(): r.hp-=1
	var cells=visible_map(1); var old=Reference.new(); var newer=Candidate.new()
	for i in 5: old.publish(first,cells,i); newer.publish(first,cells,i)
	var old_times=[]; var new_times=[]; var timings=[]; var publications=0
	for trial in TRIALS:
		if not remaining(): break
		var a={}; var b={}
		if trial%2==0: a=measure(old,first,second,cells); b=measure(newer,first,second,cells)
		else: b=measure(newer,first,second,cells); a=measure(old,first,second,cells)
		old_times.append(a.microseconds); new_times.append(b.microseconds)
		publications+=a.publications+b.publications
		timings.append({"trial":trial,"order":"reference_first" if trial%2==0 else "candidate_first","reference":a,"candidate":b})
		check(label+" equal after paired trial "+str(trial),old.records()==newer.records() and deeply_frozen(newer.records()))
	var counted=graph_count(newer.records())
	benchmarks.append({"label":label,"units":units,"static_records":statics,"path_points_per_unit":path_length,
		"input_serialized_bytes":var_to_bytes(first).size(),"output_serialized_bytes":var_to_bytes(newer.records()).size(),
		"trials":timings,"warmup_publications":10,"measured_publications":publications,
		"reference_median_batch_usec":median(old_times) if old_times.size()==6 else null,
		"candidate_median_batch_usec":median(new_times) if new_times.size()==6 else null,
		"removed_final_freeze_recursive_calls_per_publication":counted.calls,
		"removed_final_freeze_dictionary_creations_per_publication":counted.dictionaries,
		"removed_final_freeze_array_creations_per_publication":counted.arrays,
		"count_basis":"Structural count of the removed final recursive freeze only; excludes engine allocation internals, duplicate(true), retained per-record freeze and fresh next map",
		"actual_allocator_calls":null,"allocated_memory_bytes":null})
func run():
	started=Time.get_ticks_msec()
	var args=OS.get_cmdline_user_args()
	if args.size()!=2: quit(2); return
	destination=args[0]; expected_build=args[1]
	if FileAccess.file_exists(destination) or expected_build!=Rules.BUILD_ID: quit(2); return
	check("reference bytes exactly frozen original",FileAccess.get_sha256("res://tests/faction_publish_reference.gd")==REFERENCE_SHA)
	semantics()
	if remaining(): benchmark("opening",12,24,32)
	if remaining(): benchmark("developed",50,40,64)
	check("bounded component fixture completes",not timed_out)
	var failed=0
	for entry in checks:
		if not entry.passed: failed+=1
	var report={"schema":"vc-faction-publication-v1","build":Rules.BUILD_ID,"scope":"Actual Godot component semantics and microbenchmark; synthetic data, not normal gameplay, rendering, mobile or whole-game speedup",
		"checks":checks,"failed":failed,"passed":failed==0,"elapsed_ms":Time.get_ticks_msec()-started,
		"engine":Engine.get_version_info(),"reference_sha256":FileAccess.get_sha256("res://tests/faction_publish_reference.gd"),"candidate_sha256":FileAccess.get_sha256("res://scripts/faction_view.gd"),"benchmarks":benchmarks,
		"not_run":["intentional read-only write errors","intentional Object assertion failure","whole-game timing","normal match","browser","mobile"]}
	var file=FileAccess.open(destination,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("FACTION_PUBLICATION checks=",checks.size()," failed=",failed," elapsed_ms=",report.elapsed_ms)
	quit(0 if failed==0 else 1)
