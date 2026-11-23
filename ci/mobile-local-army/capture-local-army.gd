extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var observations={}
var g
var tag=""
var serial=0
var began=0
var out=""
var boot=0
var metadata_only=false
var source_role=""
var info={}
var captured=[]

func _initialize():
	boot=Time.get_ticks_msec()
	print("VC_CAPTURE_BOOT local_army")
	call_deferred("run")
func ck(n,v):
	checks.append({"name":n,"pass":bool(v)})
	if not v:push_error(n)
	return bool(v)
func note(key,fields):
	observations[key]=fields
	print("JOURNEY_NOTE ",key," ",JSON.stringify(fields))
func frames(n=4):
	for i in n:await process_frame
func sync_ui():
	g._process(0);g._update_hud();g._layout_ui()
	await frames()
func bank():return g.economy.bank_milli(0).duplicate(true)
func cost_exact(before,after,kind):
	for k in before:
		if after[k]!=before[k]-1000*Rules.COSTS[kind].get(k,0):return false
	return true
func tap(p):
	serial+=1
	for down in [true,false]:
		var e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=down;root.push_input(e)
		await process_frame
	await frames()
func drag(p,q):
	serial+=1
	var t=InputEventScreenTouch.new();t.index=0;t.pressed=true;t.position=p;root.push_input(t)
	await process_frame
	var d=InputEventScreenDrag.new();d.index=0;d.position=q;d.relative=q-p;root.push_input(d)
	await process_frame
	t=InputEventScreenTouch.new();t.index=0;t.pressed=false;t.position=q;root.push_input(t)
	await frames()
func shape(r):return [r.position.x,r.position.y,r.size.x,r.size.y]
func phone_rect():return Rect2(Vector2.ZERO,root.get_visible_rect().size)
func reachable(button,lane,include_disabled=false):
	if not is_instance_valid(button) or not button.is_visible_in_tree() or (button.disabled and not include_disabled):return false
	var r=button.get_global_rect()
	return r.size.x>=44 and r.size.y>=44 and phone_rect().encloses(r) and lane.get_global_rect().encloses(r)
func at_target(screen,id):
	var winner=g._pick(screen,true)
	return g._box_point_in_world(screen) and g._friendly_unit_pick(screen,winner)==id
func point_for(ent):
	var world=g.camera.unproject_position(ent.pos+Vector3(0,.60 if ent.category=="unit" else 1.0,0))
	if at_target(world,ent.id):return world
	for radius in [5,10,15,20,25,30]:
		for i in 12:
			var p=world+radius*Vector2.RIGHT.rotated(i*TAU/12)
			if at_target(p,ent.id):return p
	return Vector2.INF
func action(kind,meta="command_icon_kind"):
	for b in g.actions.get_children():
		if b is Button and b.has_meta(meta) and b.get_meta(meta)==kind:return b
	return null
func swipes_for(b):
	var swipes=0
	while swipes<8 and not reachable(b,g.action_scroll):
		var r=g.action_scroll.get_global_rect()
		var dir=-1 if b.get_global_rect().end.x>r.end.x else 1
		var excess=b.get_global_rect().end.x-r.end.x if dir==-1 else r.position.x-b.get_global_rect().position.x
		var length=minf(maxf(18,ceilf(excess)+4),minf(180,r.size.x*.64))
		await drag(r.get_center()-Vector2(dir*length*.5,0),r.get_center()+Vector2(dir*length*.5,0))
		await sync_ui()
		swipes+=1
	return swipes if reachable(b,g.action_scroll) else -1
func ticks_until(predicate,max_steps):
	var i=0
	while i<max_steps and not predicate.call() and not g.game_over and not g.paused:
		g._process(Rules.TICK);i+=1
	if i>0:await sync_ui()
	return i
func pure_action(before,seq,cam):
	return bank()==before and g.command_sequence==seq and g.camera.global_transform==cam and g.all_touch_ids.is_empty()
func grab_some_wood():
	var workers=g.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager")
	var trees=g.faction_views[0].records().values().filter(func(e):return e.alive and e.kind in ["pine","oak"] and not e.remembered and point_for(e).is_finite())
	if not ck("opening contains visible tap-resolvable owned workers and trees",workers.size()==5 and trees.size()>0):return []
	var assigned=[]
	for worker in workers:
		if assigned.size()>=3:break
		var p=point_for(worker)
		if not p.is_finite():continue
		var closest=trees.duplicate()
		closest.sort_custom(func(a,b):return a.pos.distance_squared_to(worker.pos)<b.pos.distance_squared_to(worker.pos))
		if assigned.size()>=closest.size():break
		var tree=closest[assigned.size()]
		var t=point_for(tree)
		if not t.is_finite():continue
		await tap(p);await sync_ui()
		if not ck("real world touch selected working villager "+str(worker.id),g.selected==[worker.id]):return []
		await tap(t)
		if not ck("real tree touch queued one ordinary gather order for "+str(worker.id),g.commands.size()==1 and g.commands[0].type=="order" and g.commands[0].target==tree.id and g.commands[0].ids==[worker.id]):return []
		g._process(Rules.TICK)
		if not ck("ordinary work authority accepted gather "+str(worker.id),worker.state=="gather" and worker.target==tree.id):return []
		assigned.append(worker.id)
	return assigned
func build_and_train(kind,product=""):
	var worker={}
	for w in g.entities:
		if w.alive and w.team==0 and w.kind=="villager" and w.state=="idle" and point_for(w).is_finite():worker=w;break
	if worker.is_empty():
		for w in g.entities:
			if w.alive and w.team==0 and w.kind=="villager" and point_for(w).is_finite():worker=w;break
	if not ck(kind+" visible builder tappable in unchanged opening camera",not worker.is_empty()):return {}
	await tap(point_for(worker));await sync_ui()
	if not ck(kind+" actual world selection of builder",g.selected==[worker.id]):return {}
	var b=action(kind)
	if not ck(kind+" build action exists, no direct authority API",is_instance_valid(b)):return {}
	var row=[]
	for child in g.actions.get_children():
		if child is Button and child.visible:
			var r=child.get_global_rect().intersection(g.action_scroll.get_global_rect()).intersection(phone_rect())
			row.append({"label":child.text,"button":shape(child.get_global_rect()),"visible_width":r.size.x})
	var lane=g.action_scroll.get_global_rect()
	var initial=bank();var seq=g.command_sequence;var cam=g.camera.global_transform
	var motions=await swipes_for(b)
	note(kind+"_build_discovery",{"lane":shape(lane),"visible_before":row,"swipes_at_most_180px":motions,"scroll_after":g.action_scroll.scroll_horizontal})
	if not ck(kind+" reached by actual strip swipe without world order, movement or debit",motions>=0 and pure_action(initial,seq,cam)):return {}
	await tap(b.get_global_rect().get_center());await sync_ui()
	if not ck(kind+" build touch opens unpaid placement mode",g.build_mode==kind and pure_action(initial,seq,cam) and reachable(g.build_confirm,g.action_scroll,true)):return {}
	var plot=Vector3.INF;var distance=INF
	for x in range(-28,-6):
		for z in range(14,35):
			var cell=g._snap_build_position(kind,Vector3(x,0,z))
			var s=g.camera.unproject_position(cell)
			if not g._box_point_in_world(s) or not g._placement_reason(kind,cell,0,worker.id).is_empty():continue
			var d=worker.pos.distance_squared_to(cell)
			if d<distance:distance=d;plot=cell

	if not ck(kind+" legal on-screen plot available by ordinary input",plot.is_finite()):return {}
	cam=g.camera.global_transform
	await tap(g.camera.unproject_position(plot));await sync_ui()
	if not ck(kind+" actual world preview is unpaid, held and legal",g.build_preview_held and not g.build_confirm.disabled and pure_action(initial,seq,cam)):return {}
	await tap(g.build_confirm.get_global_rect().get_center())
	if not ck(kind+" actual confirm commits only one matching build command",g.commands.size()==1 and g.commands[0].type=="build" and g.commands[0].kind==kind and g.command_sequence==seq+1):return {}
	g._process(Rules.TICK);await sync_ui()
	var site=g._first(0,kind)
	if not ck(kind+" single real paid construction exists with exact changed bank",not site.is_empty() and not site.built and cost_exact(initial,bank(),kind)):return {}
	var before_complete=g.tick_count
	var construction_steps=await ticks_until(func():return site.built,1600)
	if not ck(kind+" completed through ordinary worker movement and construction",site.built and construction_steps>=int(Rules.BUILD_TIME[kind]/Rules.TICK)-1):return {}
	if product.is_empty():return site
	var anchor=g.camera.unproject_position(site.pos+Vector3.UP)
	var p=point_for(site)
	var focus_before=g.selected.duplicate()
	note(kind+"_completion_handoff",{"placement_world":str(plot),"construct_tick":before_complete,"complete_tick":g.tick_count,"selected_ids_on_completion":focus_before,"builder_id":worker.id,"building_id":site.id,"anchor":str(anchor),"anchor_world":g._box_point_in_world(anchor),"anchor_picks_site":at_target(anchor,site.id),"point":str(p),"toast":g.toast_label.text if g.toast_time>0 else "","toast_panel":g.tutorial_panel.visible,"toast_panel_rect":shape(g.tutorial_panel.get_global_rect()),"tick":g.tick_count})
	if not g._box_point_in_world(anchor):
		var anchor_seq=g.command_sequence;var anchor_bank=bank()
		await tap(anchor);await sync_ui()
		note(kind+"_blocked_center_touch",{"anchor":str(anchor),"stored_input_world":g._box_point_in_world(anchor),"same_builder_still_selected":g.selected==focus_before,"same_sequence":g.command_sequence==anchor_seq,"no_payment":bank()==anchor_bank})
	if not ck(kind+" completed building selectable by actual world touch",p.is_finite()):return {}
	var select_seq=g.command_sequence;var select_bank=bank()
	var controls_camera=g.camera.global_transform
	var feedback=g.tutorial_panel.get_global_rect()
	var feedback_body=Vector2(feedback.position.x+16,feedback.get_center().y)
	await tap(feedback_body);await sync_ui()
	if not ck(kind+" passive notice background still shields ground with builder selected",g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	var detail=g.guidance_detail_button
	if not ck(kind+" active notice Details target remains 44+ and within its panel",reachable(detail,g.tutorial_panel)):return {}
	await tap(detail.get_global_rect().get_center());await sync_ui()
	if not ck(kind+" active detail opens as GUI, never as a world order",g.context_details.is_visible_in_tree() and g.context_detail_kind=="guidance" and g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	var modal=g.context_details.get_global_rect()
	var under_detail=modal.get_center()
	await tap(under_detail);await sync_ui()
	if not ck(kind+" modal content continues to shield the world",g.context_details.is_visible_in_tree() and g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	var close=g.find_child("CloseBattleDetails",true,false)
	await tap(close.get_global_rect().get_center());await sync_ui()
	if not ck(kind+" closing actual modal leaves builder and world unchanged",not g.context_details.visible and g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	await tap(p);await sync_ui()
	note(kind+"_reselected",{"selected":g.selected,"expected":site.id,"command_delta":g.command_sequence-select_seq,"bank_equal":bank()==select_bank})
	if not ck(kind+" completed target genuinely selected without orders",g.selected==[site.id] and g.command_sequence==select_seq and bank()==select_bank):return {}

	var train=action(true,"primary_train")
	var action_visible=reachable(train,g.action_scroll)
	note(kind+"_first_training",{"lane":shape(g.action_scroll.get_global_rect()),"train_button":shape(train.get_global_rect()) if is_instance_valid(train) else [],"initial_full_44":action_visible,"initial_scroll":g.action_scroll.scroll_horizontal,"label":train.text if is_instance_valid(train) else ""})
	if not ck(kind+" first train exists and reached through actual UI",is_instance_valid(train) and await swipes_for(train)>=0):return {}
	var prior=bank();var pop=g._population(0);var n=g._count(0,product);var start=g.tick_count
	await tap(train.get_global_rect().get_center())
	if not ck(product+" actual train click sends only one ordinary order",g.commands.size()==1 and g.commands[0].type=="train" and g.commands[0].kind==product and g.commands[0].building==site.id):return {}
	g._process(Rules.TICK);await sync_ui()
	if not ck(product+" exact real price debited once and slot reserved",cost_exact(prior,bank(),product) and site.queue.size()==1 and site.queue[0].kind==product and g._population(0)==pop+1):return {}
	await ticks_until(func():return g._count(0,product)==n+1,Rules.TRAIN_TICKS[product]+140)
	if not ck(product+" natural real training time and exactly one newborn",g._count(0,product)==n+1 and g.tick_count-start>=Rules.TRAIN_TICKS[product] and site.queue.is_empty()):return {}
	var unit=g._first(0,product)
	var newborn_anchor=g.camera.unproject_position(unit.pos+Vector3(0,.60,0))
	var infant_point=point_for(unit)
	note(product+"_first_birth",{"tick":g.tick_count,"selected_producer_kept":g.selected==[site.id],"screen":str(newborn_anchor),"anchor_world":g._box_point_in_world(newborn_anchor),"anchor_picks_unit":at_target(newborn_anchor,unit.id),"tap_target":str(infant_point),"toast":g.toast_label.text if g.toast_time>0 else "","hud_summary":g.selection_summary.text,"queue_summary":g.queue_label.text,"builder_state":worker.state})
	return site
func checkpoint(stage,details={}):
	var line=JSON.stringify({"stage":stage,"ms":Time.get_ticks_msec()-boot,"details":details})
	print("VC_CAPTURE_PROGRESS "+line)
	if out.is_empty() or not DirAccess.dir_exists_absolute(out):return
	var path=out+"/progress.jsonl"
	var f=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f!=null:f.seek_end();f.store_line(line);f.flush();f.close()
func real_frame(name,fields):
	var state=fields.duplicate(true);state.name=name
	checkpoint("state_ready",{"state":name,"band":fields.get("world_rows",-1)})
	if not metadata_only:
		var draws=[0]
		var observer=func():draws[0]+=1
		RenderingServer.frame_post_draw.connect(observer)
		var start=Time.get_ticks_msec()
		checkpoint("draw_begin",{"state":name,"needed":2,"deadline_ms":45000})
		RenderingServer.render_loop_enabled=true
		while draws[0]<2 and Time.get_ticks_msec()-start<45000:await process_frame
		RenderingServer.render_loop_enabled=false
		RenderingServer.frame_post_draw.disconnect(observer)
		checkpoint("draw_end",{"state":name,"draws":draws[0],"ms":Time.get_ticks_msec()-start})
		if not ck(name+" two actual renderer frame completions",draws[0]>=2):return false
		checkpoint("readback_begin",{"state":name})
		var img=root.get_texture().get_image()
		checkpoint("readback_end",{"state":name,"valid":img!=null})
		if not ck(name+" actual native image dimensions",img!=null and not img.is_empty() and img.get_size()==Vector2i(568,320)):return false
		var palette={}
		for y in range(0,320,13):
			for x in range(0,568,13):palette[img.get_pixel(x,y).to_rgba32()]=true
		if not ck(name+" real native unmodified view is nonblank",palette.size()>24):return false
		state.file=name+".png"
		var path=out+"/"+state.file
		if not ck(name+" native PNG saved",img.save_png(path)==OK):return false
		state.sha256=FileAccess.get_sha256(path)
		checkpoint("png_saved",{"state":name,"sha256":state.sha256})
	captured.append(state)
	return true
func selected_columns():
	var result=[]
	for b in g.actions.get_children():
		if b is Button:
			var r=b.get_global_rect()
			var visible=r.intersection(g.action_scroll.get_global_rect())
			if visible.has_area():result.append({"caption":b.text,"rect":shape(r),"visible":shape(visible)})
	return result
func finish():
	info.failed=checks.filter(func(x):return not x.pass).size()
	info.checks=checks;info.frames=captured
	info.result="FAIL" if info.failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
	info.png_count=captured.filter(func(x):return x.has("sha256")).size()
	checkpoint("finish",{"states":captured.size(),"failed":info.failed,"png_count":info.png_count})
	var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
	if f==null:quit(2);return
	f.store_string(JSON.stringify(info,"  "));f.close()
	if is_instance_valid(g):g.free()
	quit(1 if info.failed else 0)

func run():
	RenderingServer.render_loop_enabled=false
	var a=OS.get_cmdline_user_args()
	if a.size() not in [5,6] or a[1] not in ["baseline","candidate"] or (a.size()==6 and a[5]!="--metadata-only"):quit(2);return
	out=a[0];source_role=a[1];metadata_only=a.size()==6
	if not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out) or DirAccess.make_dir_recursive_absolute(out)!=OK:quit(2);return
	var target_size=Vector2i(568,320)
	root.size=target_size;await frames()
	info={"scope":"Actual native fresh Practice; same ordinary paid opening, untouched original assets, ordinary box, same camera/figures/point. Candidate then taps local-only military action. Native viewport synthetic touches; not iPhone/browser.","build":Rules.BUILD_ID,"role":source_role,"size":[568,320],"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"metadata_only":metadata_only}
	checkpoint("initialize",{"build":info.build,"role":source_role,"display":info.display})
	if not ck("identity and viewport are pinned",info.build==a[2] and info.game_sha==a[3] and info.rules_sha==a[4] and root.size==target_size and (metadata_only or info.display!="headless")):finish();return
	g=load("res://main.tscn").instantiate()
	g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.camera_zoom=22 # Fresh landscape menu equivalent.
	await sync_ui()
	if not ck("fresh ordinary stock, deterministic tick zero and original AI active",g.tick_count==0 and g.ai_enabled and bank()=={"food":150000,"wood":200000,"stone":100000,"iron":0}):finish();return
	var workers=await grab_some_wood()
	if not ck("ordinary input started three lumber workers",workers.size()==3):finish();return
	await ticks_until(func():return g.economy.stats_view(0).delivered.wood>=10000,1200)
	if not ck("real earned lumber delivered",g.economy.stats_view(0).delivered.wood>=10000):finish();return
	checkpoint("paid_opening_begin")
	if (await build_and_train("house")).is_empty():finish();return
	if (await build_and_train("barracks","spearman")).is_empty():finish();return
	await ticks_until(func():return bank().wood>=165000,2500)
	if not ck("second producer can be paid with ordinary lumber",bank().wood>=165000):finish();return
	if (await build_and_train("range","archer")).is_empty():finish();return
	checkpoint("paid_opening_complete",{"tick":g.tick_count,"bank":bank()})
	var spear=g._first(0,"spearman");var archer=g._first(0,"archer");var worker=g._get_entity(4);var scout=g._first(0,"scout")
	if not ck("only one actual paid Spearman and Archer and their near worker exist",g._count(0,"spearman")==1 and g._count(0,"archer")==1 and worker.kind=="villager"):finish();return
	var a1=g.camera.unproject_position(spear.pos+Vector3(0,.6,0));var a2=g.camera.unproject_position(archer.pos+Vector3(0,.6,0))
	var lo=Vector2(minf(a1.x,a2.x),minf(a1.y,a2.y))-Vector2(6,5)
	var hi=Vector2(maxf(a1.x,a2.x),maxf(a1.y,a2.y))+Vector2(7,6)
	var prebank=bank();var cam=g.camera.global_transform;var seq=g.command_sequence
	await drag(lo,hi);await sync_ui()
	var group=g.selected.duplicate();group.sort()
	if not ck("same civilian-inclusive box genuinely selects the local worker and two born troops only",group==[worker.id,spear.id,archer.id] and pure_action(prebank,seq,cam)):finish();return
	var filter=g.actions.get_node_or_null("FilterSelectedMilitary")
	var has_filter=reachable(filter,g.action_scroll)
	if not ck("source-specific matched box shows expected first-page filter state",not is_instance_valid(filter) if source_role=="baseline" else has_filter and g.actions.get_child(0)==filter and g.action_scroll.scroll_horizontal==0):finish();return
	if not ck("pure mixed Advance is not prematurely exposed during worker-inclusive selection",not is_instance_valid(g.actions.get_node_or_null("PrimaryTacticalAdvance"))):finish();return
	var actor_world={}
	for ent in [worker,spear,archer,scout]:actor_world[str(ent.id)]=[ent.pos.x,ent.pos.y,ent.pos.z]
	var fields={"camera":str(cam),"zoom":g.camera_zoom,"map":g.layout_id,"tick":g.tick_count,"bank":prebank,"selection":group,"actor_world":actor_world,"rectangle":[lo.x,lo.y,hi.x,hi.y],"worker_screen":str(g.camera.unproject_position(worker.pos+Vector3(0,.6,0))),"paid_event_counts":g.match_report.trained.duplicate(true)}
	if not await real_frame("same-ordinary-box",fields.merged({"controls":selected_columns(),"local_filter":has_filter})):finish();return
	if source_role=="baseline":finish();return
	var held_worker=[worker.state,worker.work_epoch,worker.dest,worker.target,worker.pos,g._cargo_amount(worker)]
	await tap(filter.get_global_rect().get_center())
	var advance=g.actions.get_node_or_null("PrimaryTacticalAdvance")
	if not ck("actual filtered touch only selects those two troops, no scout, map order, movement or debit",g.selected==[spear.id,archer.id] and scout.id not in g.selected and pure_action(prebank,seq,cam) and held_worker==[worker.state,worker.work_epoch,worker.dest,worker.target,worker.pos,g._cargo_amount(worker)]):finish();return
	if not ck("existing Advance is now full first-page app control",reachable(advance,g.action_scroll) and g.actions.get_child(0)==advance and advance.text=="警戒前進" and g.action_scroll.scroll_horizontal==0):finish();return
	fields.selection=g.selected.duplicate()
	fields.controls=selected_columns()
	fields.advance_rect=shape(advance.get_global_rect())
	fields.local_filter=false
	await real_frame("filtered-army-advance",fields)
	finish()
