extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var observations=[]

func _initialize():call_deferred("run")
func check(name,ok):
	checks.append({"name":name,"passed":bool(ok)})
	if not ok:push_error(name)
	return bool(ok)
func settle(n=4):
	for i in n:await process_frame
func reach(g,b):
	return is_instance_valid(b) and b.is_visible_in_tree() and b.size.x>=44 and b.size.y>=44 and g.action_scroll.get_global_rect().encloses(b.get_global_rect())
func action(g,k,caption):
	for b in g.actions.get_children():
		if b is Button and b.get_meta("command_icon_kind","")==k and b.text.begins_with(caption):return b
	return null
func pointer(p,index,down):
	var e=InputEventScreenTouch.new();e.index=index;e.position=p;e.pressed=down;root.push_input(e);await process_frame
func tap(b,index=52):
	var p=b.get_global_rect().get_center()
	await pointer(p,index,true);await pointer(p,index,false);await settle()
func refresh(g):
	g._publish_faction_views();g._update_hud();await settle()
func reveal(g,b):
	if is_instance_valid(b):g.action_scroll.ensure_control_visible(b);await settle()
func draw_one(g,begin,end,index):
	await pointer(begin,index,true)
	var last=begin
	for n in range(1,5):
		var now=begin.lerp(end,n/4.0)
		var e=InputEventScreenDrag.new();e.index=index;e.position=now;e.relative=now-last;root.push_input(e);await process_frame
		last=now
	await pointer(end,index,false);await settle()
func production(g,keep,ticks):
	# Exact normal queue operations, accelerated by advancing the ownership
	# ticks only. No eligibility or tech completion is written by the fixture.
	for i in ticks:
		g.tick_count+=1;g._update_production(keep,Rules.TICK,false);g._process_ready_production()
func state(g,keep,label):
	var focus=root.gui_get_focus_owner()
	var train=action(g,"villager","訓練")
	var scout=action(g,"scout","訓練")
	observations.append({"label":label,"size":[root.size.x,root.size.y],"offset":g.action_scroll.scroll_horizontal,
		"train_reachable":reach(g,train),"scout_reachable":reach(g,scout),"return_reachable":reach(g,g.town_research_return),
		"commands":g.commands.size(),"queue":keep.queue.map(func(t):return t.kind),"complete":g.military_tech_completed[0].keys(),
		"focus":str(focus.name) if is_instance_valid(focus) else ""})
func per_view(size,mode):
	root.size=size;await settle()
	var tag=str(size)+" "+mode
	var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
	var stock={"food":3000,"wood":3000,"stone":3000,"iron":3000}
	g._test_reset([stock,stock.duplicate(true)]);g._layout_ui();await settle()
	var keep=g._first(0,"town_center");var id=keep.id;g._select([id]);await settle()
	var cam=g.camera_focus
	var age=action(g,"age2","城防時代")
	if mode=="manual":
		for i in 9:
			if reach(g,age):break
			var r=g.action_scroll.get_global_rect();var y=r.position.y+22
			var wanted=age.get_global_rect()
			if wanted.end.x>r.end.x:
				var travel=clampf(wanted.end.x-r.end.x+6,16,r.size.x-46)
				await draw_one(g,Vector2(r.end.x-23,y),Vector2(r.end.x-23-travel,y),60+i)
			else:
				var travel=clampf(r.position.x-wanted.position.x+6,16,r.size.x-46)
				await draw_one(g,Vector2(r.position.x+23,y),Vector2(r.position.x+23+travel,y),60+i)
		check(tag+" ordinary manual swipes never arm bookmark",g.town_research_visit<0 and g.action_scroll.scroll_horizontal>0)
	else:
		if not check(tag+" initial visible research jump",reach(g,g.town_research_jump)):g.free();return
		await tap(g.town_research_jump)
	if not check(tag+" age research physically reachable",reach(g,age)):g.free();return
	await tap(age,53);g._tick(Rules.TICK);await refresh(g)
	if not check(tag+" original tap actually paid for research",keep.queue.size()==1 and keep.queue[0].kind=="age2" and g.economy.bank_milli(0).food==2650000):g.free();return
	var paid=g.economy.bank_milli(0).duplicate(true)
	var offset=g.action_scroll.scroll_horizontal
	if mode!="manual":
		check(tag+" paid rebuild preserves research position and back focus",reach(g,g.town_research_return) and root.gui_get_focus_owner()==g.town_research_return)
	production(g,keep,Rules.TRAIN_TICKS.age2+2);await refresh(g)
	if not check(tag+" untouched selection finishes actual paid age progression",g._age2(0) and keep.queue.is_empty() and g.selected==[id] and g.economy.bank_milli(0)==paid):g.free();return
	check(tag+" age rebuild retains current offset",g.action_scroll.scroll_horizontal==offset)
	if mode!="manual":
		check(tag+" age completion keeps back visible and focused",reach(g,g.town_research_return) and root.gui_get_focus_owner()==g.town_research_return)
		await tap(g.town_research_return,54)
		check(tag+" new Back actually returns without selecting again",g.action_scroll.scroll_horizontal==0 and reach(g,action(g,"villager","訓練")) and g.selected==[id] and g.commands.is_empty())
		await tap(g.town_research_jump,54)
	state(g,keep,tag+" reached Age II")
	for tech in Rules.RESEARCH_TECHS.slice(0,3):
		if not check(tag+" pays ordinary "+tech,g._enqueue_military_research(id,tech,0)):g.free();return
		production(g,keep,Rules.TRAIN_TICKS[tech]+2);await refresh(g)
	var final=Rules.RESEARCH_TECHS[-1];var last=action(g,final,Rules.NAMES[final]);await reveal(g,last)
	if not check(tag+" final research physically reachable",reach(g,last)):g.free();return
	await tap(last,55);g._tick(Rules.TICK);await refresh(g)
	if not check(tag+" paid queue holds final research with other three complete",keep.queue.size()==1 and keep.queue[0].kind==final and g.military_tech_completed[0].size()==3):g.free();return
	await reveal(g,g.town_research_return)
	var p=g.town_research_return.get_global_rect().get_center()
	offset=g.action_scroll.scroll_horizontal;paid=g.economy.bank_milli(0).duplicate(true)
	if mode=="held" or mode=="manual_during_return":await pointer(p,56,true)
	production(g,keep,Rules.TRAIN_TICKS[final]+2);await refresh(g)
	if mode=="held" or mode=="manual_during_return":
		check(tag+" no auto-return underneath held touch",g.action_scroll.scroll_horizontal==offset and g.all_touch_ids==[56] and not g.town_research_repair.is_empty())
		state(g,keep,tag+" final completed while held")
		if mode=="manual_during_return":
			var q=p+Vector2(110,0)
			var e=InputEventScreenDrag.new();e.index=56;e.position=q;e.relative=q-p;root.push_input(e);await process_frame
			await pointer(q,56,false)
		else:await pointer(p,56,false)
		await settle()
	var train=action(g,"villager","訓練")
	if mode=="manual" or mode=="manual_during_return":
		var wanted=offset-110 if mode=="manual_during_return" else offset
		check(tag+" ordinary manual scroll remains chosen once all techs finish",g.action_scroll.scroll_horizontal==wanted and wanted>0)
	else:
		check(tag+" last completion returns to focused Train",g.action_scroll.scroll_horizontal==0 and reach(g,train) and root.gui_get_focus_owner()==train)
		if size.x>350:check(tag+" Scout still fully visible",reach(g,action(g,"scout","訓練")))
	check(tag+" final completion and cleanup issue no new transaction or camera move",g.military_tech_completed[0].size()==4 and not is_instance_valid(g.town_research_return) and g.town_research_repair.is_empty() and keep.queue.is_empty() and g.selected==[id] and g.commands.is_empty() and g.economy.bank_milli(0)==paid and g.camera_focus==cam)
	state(g,keep,tag+" finished all four")
	g.free();await settle()
func run():
	await per_view(Vector2i(320,568),"held")
	await per_view(Vector2i(390,844),"bookmark")
	await per_view(Vector2i(568,320),"bookmark")
	await per_view(Vector2i(390,844),"manual")
	await per_view(Vector2i(390,844),"manual_during_return")
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"town_research_lifecycle_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"observations":observations,"scope":"Pinned ordinary paid queue operations with accelerated production clocks, real native touches and normal same-selection HUD refresh; no Web/iPhone."}))
	quit(1 if failed else 0)
