extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var observations={}
var g
var menu
var tag=""
var serial=0
var began=0
var notice_focus=false

func _initialize():call_deferred("run")
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
func touch_event(i,p,down):
	var e=InputEventScreenTouch.new();e.index=i;e.position=p;e.pressed=down;root.push_input(e)
func pan_pair(delta):
	var a=Vector2.INF;var b=Vector2.INF
	for y in range(118,222,2):
		if a.is_finite():break
		for x in range(12,500,12):
			var first=Vector2(x,y);var second=first+Vector2(62,0)
			if [first,second,first+delta,second+delta].all(g._box_point_in_world):
				a=first;b=second;break
	if not a.is_finite():return false
	serial+=1
	touch_event(0,a,true);touch_event(1,b,true);await process_frame
	var step=delta/ceilf(delta.length()/5.0)
	for i in int(ceilf(delta.length()/5.0)):
		for j in 2:
			var e=InputEventScreenDrag.new();e.index=j;e.position=(a if j==0 else b)+step*(i+1);e.relative=step;root.push_input(e)
		await process_frame
	touch_event(0,a+delta,false);touch_event(1,b+delta,false);await frames()
	return true
func best_visible_plot(kind,worker):
	var plot=Vector3.INF;var distance=INF
	for x in range(-32,-10):
		for z in range(14,37):
			var cell=g._snap_build_position(kind,Vector3(x,0,z))
			var s=g.camera.unproject_position(cell)
			if not g._box_point_in_world(s) or not g._placement_reason(kind,cell,0,worker.id).is_empty():continue
			var d=worker.pos.distance_squared_to(cell)
			if d<distance:distance=d;plot=cell
	return plot
func shape(r):return [r.position.x,r.position.y,r.size.x,r.size.y]
func phone_rect():return Rect2(Vector2.ZERO,root.get_visible_rect().size)
func reachable(button,lane,include_disabled=false):
	if not is_instance_valid(button) or not button.is_visible_in_tree() or (button.disabled and not include_disabled):return false
	var r=button.get_global_rect()
	return r.size.x>=44 and r.size.y>=44 and phone_rect().encloses(r) and lane.get_global_rect().encloses(r)
func menu_reaches(b):
	var r=b.get_global_rect()
	return b.is_visible_in_tree() and not b.disabled and phone_rect().encloses(r) and (not menu.scroll.is_ancestor_of(b) or menu.scroll.get_global_rect().encloses(r))
func menu_click(name):
	var b=menu.find_child(name,true,false)
	if b==null:return false
	for i in 8:
		if menu_reaches(b):break
		var r=menu.scroll.get_global_rect()
		var dir=-1 if b.get_global_rect().position.y>r.position.y else 1
		var segment=minf(r.size.y*.45,180)
		await drag(r.get_center()-Vector2(0,dir*segment*.55),r.get_center()+Vector2(0,dir*segment*.45))
	if not menu_reaches(b):
		note("menu_clip",{"name":name,"button":shape(b.get_global_rect()),"scroll":shape(menu.scroll.get_global_rect()),"visible":b.is_visible_in_tree(),"phone":shape(phone_rect())})
		return ck("menu button clipped: "+name,false)
	if name=="LaunchMatchButton":
		var p=b.get_global_rect().get_center()
		touch_event(0,p,true);await process_frame
		touch_event(0,p,false)
		for i in 120:
			await process_frame
			if is_instance_valid(menu.match_node):
				menu.match_node.set_process(false)
				return ck("match frozen at natural tick zero before any update",menu.match_node.tick_count==0)
		return ck("normal game launches and is present",false)
	await tap(b.get_global_rect().get_center())
	return true
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
func val(ent):
	return [ent.pos.x,ent.pos.z]
func screen_plot(plot):
	return g.camera.unproject_position(plot+Vector3(.25,0,.25))
func cmd0():
	return g.commands.filter(func(c):return c.team==0)
func own_execution():
	return g.processed_command_ids.keys().filter(func(key):return key.begins_with("0:"))
func aim(plot):
	for i in 28:
		var p=screen_plot(plot)
		if Rect2(Vector2(16,0),Vector2(root.size.x-32,root.size.y)).has_point(p) and g._box_point_in_world(p):return p
		var desired=Vector2(root.size.x*.50,root.size.y*.50)
		var d=desired-p
		var step=Vector2(clampf(d.x,-54,54),clampf(d.y*1.32,-31,31))
		var ok=await pan_pair(step)
		if not ok:
			step=Vector2(clampf(d.x,-34,34),clampf(d.y,-14,14))
			ok=await pan_pair(step)
		if not ok or step.length()<.4:return Vector2.INF
		await sync_ui()
	return Vector2.INF
func build_open(kind):
	var b=action(kind)
	if not is_instance_valid(b):return ck("actual visible build action missing: "+kind,false)
	if await swipes_for(b)<0:return ck("actual build strip could not expose "+kind,false)
	var before=bank()
	await tap(b.get_global_rect().get_center());await sync_ui()
	return ck("actual "+kind+" action opens unpaid preview",g.build_mode==kind and bank()==before and cmd0().is_empty())
func cancel():
	var options=g.actions.get_children().filter(func(c):return c is Button and c.text=="取消建造")
	if options.size()!=1:return ck("actual Cancel button exists",false)
	if await swipes_for(options[0])<0:return ck("actual Cancel button reachable",false)
	var initial=bank()
	await tap(options[0].get_global_rect().get_center());await sync_ui()
	return ck("actual Cancel leaves bank and pending orders unchanged",g.build_mode.is_empty() and bank()==initial and cmd0().is_empty())
func tap_build(kind,plot,label):
	var initial=bank()
	var p=screen_plot(plot)
	if not ck(label+" direct world tap on correct projected plot",g._box_point_in_world(p) and g._snap_build_position(kind,g._point(g._cell(g._world_at(p))))==plot):return {}
	await tap(p);await sync_ui()
	var shown=g.queue_label.text
	var summary=g.selection_summary.text
	var reason=g._build_preview_reason()
	var physical=g._build_preview_reason(false)
	var color=g.ghost.get_child(0).material_override.albedo_color.to_html(false)
	var row={"plot":[plot.x,plot.z],"pixel":[p.x,p.y],"wood":initial.wood,"reason":reason,"reason_ignoring_funds":physical,"color":color,
										"summary":summary,"queue_text":shown,"enabled":not g.build_confirm.disabled,"worker":g._selected_builder(),"camera":str(g.camera_focus),
										"footprint":[int(Rules.FOOTPRINT[kind]),g._occupied_cells({"pos":plot,"kind":kind}).size()]}
	note(label,row)
	if not ck(label+" preview does not debit or dispatch and is actually held",bank()==initial and cmd0().is_empty() and g.build_preview_held):return {}
	return row
func finish_build(kind,plot,label):
	var initial=bank()
	if not ck(label+" confirm usable inside HUD",reachable(g.build_confirm,g.action_scroll)):return {}
	await tap(g.build_confirm.get_global_rect().get_center())
	if not ck(label+" exactly one actual Confirm command waiting so far unpaid",cmd0().size()==1 and cmd0()[0].type=="build" and cmd0()[0].kind==kind and bank()==initial):return {}
	g._process(Rules.TICK);await sync_ui()
	var sites=g.entities.filter(func(e):return e.alive and e.team==0 and e.kind==kind and e.pos==plot)
	if not ck(label+" actual placed site and exact debit",sites.size()==1 and cost_exact(initial,bank(),kind)):return {}
	var site=sites[0]
	var walked=await ticks_until(func():return site.built,Rules.BUILD_TIME[kind]*20+1800)
	if not ck(label+" acquired construction and finished normally",site.built and g.economy.audit().ok):return {}
	note(label+"_complete",{"tick":g.tick_count,"walk_and_build_ticks":walked,"site_id":site.id,"pos":val(site),"bank":bank()})
	await ticks_until(func():return g.toast_time<=0,140)
	return site
func initial_build(kind,crew):
	if not await build_open(kind):return {}
	var plot=best_visible_plot(kind,crew)
	if not ck(kind+" ordinary near-open plot",plot.is_finite()):return {}
	var q=await tap_build(kind,plot,kind+"_near")
	if not ck(kind+" valid green appointment",q.get("reason","test")==""):return {}
	return await finish_build(kind,plot,kind+"_near")
func select_actor(actor,label):
	var p=point_for(actor)
	if not ck(label+" ordinary actor screen selection exposed",p.is_finite()):return false
	await tap(p);await sync_ui()
	return ck(label+" selects intended real actor",g.selected==[actor.id] and cmd0().is_empty())
func clear_physical(plot,kind):
	var hint={"kind":kind,"pos":plot,"category":"building"}
	for c in g._occupied_cells(hint):
		if g.navigation.is_point_solid(c):return false
	return not g._perimeter_cells(hint).all(func(c):return g.navigation.is_point_solid(c))
func find_far(home):
	var preferred=Vector3(2,0,14)
	var best=Vector3.INF
	var score=INF
	for x in range(-3,10):
		for z in range(10,30):
			var p=Vector3(x,0,z)
			var d=home.pos.distance_to(p)
			if d<=30 or d>=38 or not clear_physical(p,"house"):continue
			if g._placement_reason("wall",p,0,g._selected_builder())!="先派村民探索建築範圍":continue
			var gap=p.distance_squared_to(preferred)
			if gap<score:score=gap;best=p
	return best
func reveal_far(scout,far):
	var p=Vector2.INF
	var target=Vector3.INF
	for d in [Vector3(-3,0,0),Vector3(0,0,-3),Vector3(-4,0,-1),Vector3(1,0,4),Vector3(-2,0,4),Vector3(3,0,2),Vector3(-5,0,0)]:
		var candidate=far+d
		var c=screen_plot(candidate)
		if not g._box_point_in_world(c) or g._pick(c)>=0 or not clear_physical(candidate,"house"):continue
		p=c;target=candidate;break
	if not ck("scout ordinary open ground point on same far camera",p.is_finite()):return false
	await tap(p)
	if not ck("actual scout move queues exactly one ordinary move",cmd0().size()==1 and cmd0()[0].ids==[scout.id] and cmd0()[0].target<0):return false
	var ticks=await ticks_until(func():
		return scout.state=="idle" and scout.pos.distance_to(target)<2,2400)
	note("scout_reveal",{"pos":val(scout),"target":[target.x,target.z],"ticks":ticks,"far":str(far),"distance":scout.pos.distance_to(far)})
	return ck("scout walks there normally and freshly reveals the whole equal footprint",scout.pos.distance_to(target)<2 and
		g._occupied_cells({"kind":"wall","pos":far}).all(func(c):return g.visible_cells[0][c.y*Rules.MAP_SIZE+c.x]!=0))
func footprint_sight(plot):
	var cells=g._occupied_cells({"kind":"wall","pos":plot})
	var rows=[]
	for c in cells:
		var i=c.y*Rules.MAP_SIZE+c.x
		rows.append({"cell":[c.x,c.y],"visible":g.visible_cells[0][i],"explored":g.explored_cells[0][i]})
	return rows
func routed_walk(actor,target,label):
	var p=await aim(target)
	if not ck(label+" normal camera has physically open empty touch point",p.is_finite() and g._pick(p)<0):return false
	var before=bank()
	await tap(p)
	if not ck(label+" actual map tap issues only one ordinary move",cmd0().size()==1 and cmd0()[0].ids==[actor.id] and cmd0()[0].target<0 and bank()==before):return false
	var ticks=await ticks_until(func():return actor.state=="idle" and actor.pos.distance_to(target)<2,2300)
	note(label+"_arrival",{"pos":val(actor),"desired":[target.x,target.z],"ticks":ticks,"bank":bank()})
	return ck(label+" ordinary movement reaches physical destination without payment",actor.pos.distance_to(target)<2 and bank()==before)
func withdraw_scout(scout,far):
	for delta in [Vector3(-13,0,6),Vector3(-14,0,6),Vector3(-15,0,3),Vector3(-14,0,4),Vector3(-15,0,2),Vector3(-16,0,1)]:
		var target=far+delta
		if not clear_physical(target,"wall"):continue
		var p=await aim(target)
		if not p.is_finite() or g._pick(p)>=0:continue
		return await routed_walk(scout,target,"scout_withdrawal")
	return ck("actual withdrew scout beyond site visibility",false)
func walk_worker_back_into_sight(worker,far):
	for delta in [Vector3(-3,0,0),Vector3(-4,0,0),Vector3(-4,0,1),Vector3(-3,0,3),Vector3(-3,0,-1)]:
		var target=far+delta
		if not clear_physical(target,"wall"):continue
		var p=await aim(target)
		if not p.is_finite() or g._pick(p)>=0:continue
		return await routed_walk(worker,target,"selected_villager_manual_approach")
	return ck("actual ordinary villager approach possible",false)
# Test-only evidence. No input path or saved/runtime scene modifications.
func render_state():
	var own=g.faction_views[0].records().values().filter(func(r):return r.get("owned",false) and r.get("alive",false))
	own.sort_custom(func(a,b):return a.id<b.id)
	var actors=own.map(func(r):return [r.id,r.kind,str(r.pos),r.get("hp",-1),r.get("built",false)])
	return {"bank":bank(),"actors":actors,"camera":str(g.camera.global_transform),"selected":g.selected.duplicate(),"tick":g.tick_count,
		"position":str(g.pointer_world),"held":g.build_preview_held,"wall_sight":footprint_sight(g._snap_build_position("wall",g.pointer_world)),
		"pending_player_orders":cmd0().size(),"completed":g.completed_builds[0],"build_mode":g.build_mode}
func save_view(stage):
	var state=render_state()
	var dir=OS.get_environment("VC_RECON_NATIVE_OUTPUT")
	var stage_record={"state":state,"summary":g.selection_summary.text,"help":g.help_label.text,
		"placement_ok":g.placement_ok,"confirm_enabled":not g.build_confirm.disabled,
		"ghost_color":g.ghost.get_child(0).material_override.albedo_color.to_html(false)}
	if g.has_method("_refresh_build_recon"):
		var btn=g.build_recon_button
		stage_record.recon={"text":btn.text,"visible":btn.is_visible_in_tree(),"disabled":btn.disabled,"rect":shape(btn.get_global_rect())}
	else:
		stage_record.recon={}
	if not dir.is_empty():
		if not ck(stage+" genuine Linux Compatibility framebuffer",DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and "llvmpipe" in RenderingServer.get_video_adapter_name().to_lower()):return false
		var draws=[0]
		var marker=func():draws[0]+=1
		RenderingServer.frame_post_draw.connect(marker);RenderingServer.render_loop_enabled=true
		var start=Time.get_ticks_msec()
		while draws[0]<3 and Time.get_ticks_msec()-start<30000:await process_frame
		RenderingServer.render_loop_enabled=false;RenderingServer.frame_post_draw.disconnect(marker)
		if not ck(stage+" three true draws and unchanged state",draws[0]>=3 and render_state()==state):return false
		var im=root.get_texture().get_image()
		if not ck(stage+" original viewport",im!=null and not im.is_empty() and im.get_size()==Vector2i(568,320)):return false
		var unique={}
		for ix in range(0,568,17):
			for iy in range(0,320,17):unique[im.get_pixel(ix,iy).to_rgba32()]=true
		var img=dir+"/"+stage+".png"
		if not ck(stage+" unaltered rendered pixels",unique.size()>40 and not FileAccess.file_exists(img) and im.save_png(img)==OK):return false
		stage_record.png_sha256=FileAccess.get_sha256(img)
	note(stage,stage_record)
	return true

func finish():
	var actual={"source_base":"8602a3e19fc0d2563cf408e30270097c2656a624","build":Rules.BUILD_ID,"role":"candidate","game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"manifest_sha":FileAccess.get_sha256("res://reports/build-manifest.json"),"engine_hex":Engine.get_version_info().hex,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"size":[root.size.x,root.size.y],"checks":checks,"observations":observations,"gestures":serial,"tick":g.tick_count if is_instance_valid(g) else -1,"failed":checks.filter(func(q):return not q.pass).size(),"scope":"Native routed touch Practice opening, actual stock resources, ordinary player commands and scout movement. Hidden terrain inspected read-only only to choose a controlled physically clear site; no state mutation or camera injection. Not browser or physical phone."}
	print("FAR_OPEN_BUILD "+JSON.stringify(actual))
	quit(1 if actual.failed else 0)
func run():
	var args=OS.get_cmdline_user_args()
	root.size=Vector2i(int(args[0]),int(args[1]))
	menu=load("res://main_menu.tscn").instantiate();root.add_child(menu);await frames()
	for name in ["StartMatchButton","BattleGroup0","ChooseBattle_practice","LaunchMatchButton"]:
		if not ck("routed original mobile menu "+name,await menu_click(name)):finish();return
		if is_instance_valid(menu.match_node):menu.match_node.set_process(false)
	g=menu.match_node;await sync_ui()
	var home=g._first(0,"town_center");var scout=g._first(0,"scout")
	var worker={}
	for v in g.entities:
		if v.kind=="villager" and v.team==0 and v.alive and point_for(v).is_finite():worker=v;break
	if not ck("ordinary unmodified opening exact build and banks",not g.test_mode and g.ai_enabled and g.skirmish_mode=="practice" and bank().wood==200000 and not worker.is_empty()):finish();return
	if not await select_actor(worker,"stock worker"):finish();return
	var house=await initial_build("house",worker)
	if house.is_empty():finish();return
	var barracks=await initial_build("barracks",worker)
	if barracks.is_empty():finish();return
	if not ck("at least two actual completed paid builds and 30 wood left",g.completed_builds[0]==2 and bank().wood==30000):finish();return
	if not await build_open("wall"):finish();return
	var overlap=await tap_build("wall",house.pos,"near_occupied")
	if not ck("near own same footprint is legitimate physical overlap",overlap.get("reason")=="與建築或資源重疊" and not overlap.enabled and overlap.color=="d97c65"):finish();return
	if not await cancel():finish();return
	var far=find_far(home)
	if not ck("chosen withheld site is physically clear and more than 30m from keep",far.is_finite()):finish();return
	var old_pos=worker.pos
	var start_seq=g.command_sequence
	var s=await aim(far)
	if not ck("real two-finger pan reaches far terrain without world dispatch",s.is_finite() and bank().wood==30000 and g.command_sequence==start_seq and worker.pos==old_pos and g.selected==[worker.id]):finish();return
	if not await build_open("wall"):finish();return
	var fog=await tap_build("wall",far,"far_clear_but_unseen")
	if not ck("far exact clear tile with wood rejects only present sight",fog.get("reason")=="先派村民探索建築範圍" and not fog.enabled and fog.color=="d97c65"):finish();return
	if not ck("never-explored copy distinct with no Recon",fog.summary.contains("未探索") and not g.build_recon_button.is_visible_in_tree()):finish();return
	if not await cancel():finish();return
	if not ck("actual two-finger pan back to base exposing scout", (await aim(scout.pos)).is_finite()):finish();return
	if not await select_actor(scout,"actual nearby scouting unit"):finish();return
	if not ck("routed camera returns to the same far plot", (await aim(far)).is_finite()):finish();return
	var before_any=footprint_sight(far)
	note("never_explored_cells",before_any)
	if not ck("original red exact plot had four never-explored footprint cells",before_any.all(func(c):return c.explored==0 and c.visible==0)):finish();return
	if not await reveal_far(scout,far):finish();return
	var after_scout=footprint_sight(far)
	note("scout_lit_cells",after_scout)
	if not ck("scout alone observed both complete historical and current footprints",after_scout.all(func(c):return c.explored!=0 and c.visible!=0)):finish();return
	if not await withdraw_scout(scout,far):finish();return
	var remembered=footprint_sight(far)
	note("known_fogged_cells_after_scout_leaves",remembered)
	if not ck("same physically unchanged site is fully remembered but fully out of current sight",remembered.all(func(c):return c.explored!=0 and c.visible==0) and clear_physical(far,"wall")):finish();return
	if not ck("camera back to original builder", (await aim(worker.pos)).is_finite()):finish();return
	if not await select_actor(worker,"original builder still home"):finish();return
	if not ck("plot camera returned and builder is genuinely distant", (await aim(far)).is_finite() and worker.pos.distance_to(far)>22):finish();return
	note("remembered_same_site_distance",{"keep":home.pos.distance_to(far),"worker":worker.pos.distance_to(far),"physically_clear":clear_physical(far,"wall")})
	if not await build_open("wall"):finish();return
	var remembered_preview=await tap_build("wall",far,"remembered_same_plot_currently_fogged")
	if not ck("previously explored but currently fogged site goes red again with identical wording and no debit",remembered_preview.get("reason")==fog.get("reason") and remembered_preview.color==fog.color and not remembered_preview.enabled and bank().wood==30000):finish();return
	if not await save_view("remembered-site"):finish();return

	if not ck("remembered UI explicitly offers free recon while original red authority remains",remembered_preview.summary.contains("查看不扣資源") and g.help_label.text.contains("不扣資源") and g.build_confirm.disabled):finish();return
	var recon=g.build_recon_button
	var region=g.action_scroll.get_global_rect()
	if not ck("actual Recon and Confirm buttons are at least 44 and visible in viewport, affordable Confirm still disabled",reachable(recon,g.action_scroll) and reachable(g.build_confirm,g.action_scroll,true) and g.build_confirm.disabled):finish();return
	var cancel_b=g.actions.get_children().filter(func(c):return c is Button and c.text=="取消建造")[0]
	if not ck("actual Cancel remains immediately reachable, safe independent clamp",reachable(cancel_b,g.action_scroll) and not recon.get_global_rect().intersects(cancel_b.get_global_rect()) and not recon.get_global_rect().intersects(g.build_confirm.get_global_rect())):finish();return
	var recon_center=recon.get_global_rect().get_center()
	var plan=g._known_build_recon_plan("remembered")
	var balance=bank()
	var executed=own_execution()
	var seq=g.command_sequence
	var pos=g.pointer_world
	var cam=g.camera.global_transform
	var blocked=OS.get_cmdline_user_args().size()>2
	note("recon_enabled",{"pos":str(pos),"rect":shape(recon.get_global_rect()),"confirm":shape(g.build_confirm.get_global_rect()),"cancel":shape(cancel_b.get_global_rect()),"camera":str(cam),"lane":shape(region),"move_approach":str(plan.get("position",Vector3.INF)),"detail":g.selection_detail.text})
	if not ck("known staging is outside whole footprint with vision, no pending orders",not plan.is_empty() and
		not g._occupied_cells({"kind":"wall","pos":far}).has(g._cell(plan.position)) and
		g.explored_cells[0][g._cell_index(plan.position)]!=0 and
		g._occupied_cells({"kind":"wall","pos":far}).all(func(c):return (c-g._cell(plan.position)).length_squared()<=Rules.SIGHT.villager**2) and cmd0().is_empty()):finish();return
	if blocked:
		var hidden=g._spawn("house",1,far,false)
		g._navigation_rebuild();g._publish_faction_views();await sync_ui()
		if not ck("paired controlled enemy obstruction fully hidden and its 4 cells now solid",not g._visible_to(hidden,0) and g.faction_views[0].get_record(hidden.id).is_empty() and not clear_physical(far,"wall")):finish();return
		if not ck("hidden occupancy never changes summary, placement reason, Recon or approach",g._build_preview_reason()==fog.reason and g._known_build_recon_plan("remembered")==plan and g.selection_summary.text==remembered_preview.summary and g.build_confirm.disabled):finish();return
	else:
		# GUI drag away, input cancellation, and a real second contact must not
		# issue orders. The interrupted touch may clear old site intent.
		await drag(recon_center,recon_center+Vector2(0,-40));await sync_ui()
		if not ck("GUI drag cannot dispatch",cmd0().is_empty() and g.command_sequence==seq and bank()==balance):finish();return
		touch_event(0,recon_center,true);await process_frame
		var c=InputEventScreenTouch.new();c.index=0;c.pressed=false;c.canceled=true;c.position=recon_center;root.push_input(c);await sync_ui()
		if not ck("canceled GUI release cannot dispatch",cmd0().is_empty() and g.command_sequence==seq and bank()==balance):finish();return
		# Match ordinary interrupted pointer handling: fresh tap re-holds.
		await tap(screen_plot(far));await sync_ui()
		if not ck("fresh re-tap restores the remembered preview and exact Recon",g.build_preview_held and g.pointer_world==pos and reachable(recon,g.action_scroll) and recon.get_global_rect().get_center()==recon_center):finish();return
		touch_event(0,recon_center,true);touch_event(1,screen_plot(far),true);await process_frame
		touch_event(1,screen_plot(far),false);touch_event(0,recon_center,false);await sync_ui()
		if not ck("second finger invalidates held Recon without any order",cmd0().is_empty() and g.command_sequence==seq and bank()==balance and g.pointer_world==pos):finish();return
		if not ck("ordinary Recon recovers after multi-touch",reachable(recon,g.action_scroll)):finish();return
	await tap(recon_center)
	var orders=cmd0()
	if not ck("Recon queues one unadorned ordinary Move for sole selected worker, exact destination, no resource/order side effects",orders.size()==1 and orders[0].type=="order" and orders[0].ids==[worker.id] and orders[0].target==-1 and orders[0].position==plan.position and
		orders[0].keys().size()==8 and g.command_sequence==seq+1 and g.selected==[worker.id] and g.pointer_world==pos and g.build_preview_held and g.camera.global_transform==cam and bank()==balance and g.completed_builds[0]==2):finish();return
	note("recon_ordinary_order",{ "order":orders[0],"bank":bank(),"summary":g.selection_summary.text,"disabled":recon.disabled,"selected":g.selected})
	if not await save_view("recon-accepted"):finish();return
	await tap(recon_center)
	if not ck("rapid same-position second tap before simulation tick reaches disabled slot and queues nothing",cmd0()==orders and g.command_sequence==seq+1 and bank()==balance and recon.disabled and recon.is_visible_in_tree() and recon.get_global_rect().get_center()==recon_center and g.pointer_world==pos and g.selection_summary.text.contains("正前往查看")):finish();return
	var arrived=await ticks_until(func():return worker.state=="idle" and worker.pos.distance_to(plan.position)<.75,2400)
	note("recon_arrival",{"pos":val(worker),"cmdseq":g.command_sequence,"own_execution":own_execution(),"ticks":arrived,"bank":bank(),"site_state":footprint_sight(far),"reason":g._build_preview_reason(),"summary":g.selection_summary.text})
	if not ck("ordinary movement completes and genuinely re-lights full footprint, with identical held site and no re-tap, queue or resource effects",worker.pos.distance_to(plan.position)<.75 and
		footprint_sight(far).all(func(c):return c.visible!=0) and
		g.pointer_world==pos and g.build_preview_held and g.build_mode=="wall" and bank()==balance and cmd0().is_empty() and own_execution()==executed+["0:"+orders[0].command_id] and g.camera.global_transform==cam and not recon.is_visible_in_tree()):finish();return
	if blocked:
		ck("only after natural visibility does real occult blocker surface and Confirm never activates",g.build_confirm.disabled and g._build_preview_reason()=="與建築或資源重疊" and g.completed_builds[0]==2 and bank()==balance)
		finish();return
	if not ck("retained exact site automatically turns green but still unpaid awaiting explicit Confirm",g._build_preview_reason().is_empty() and not g.build_confirm.disabled and
		g.ghost.get_child(0).material_override.albedo_color.to_html(false)=="92d389" and g.completed_builds[0]==2 and bank()==balance):finish();return
	if not await save_view("ready-to-confirm"):finish();return
	var wall=await finish_build("wall",far,"far_wall_recon_no_repick")
	if wall.is_empty():finish();return
	if not ck("third building paid exactly once and finished beyond keep",g.completed_builds[0]==3 and home.pos.distance_to(wall.pos)>30 and bank().wood==0 and own_execution().size()==executed.size()+2):finish();return
	# A clear visible but unaffordable house must remain amber (never recon).
	var p=Vector3.INF
	for z in range(11,20):
		for x in range(-2,9):
			var c=Vector3(x,0,z)
			if not g._box_point_in_world(screen_plot(c)) or g._placement_reason("house",c,0,worker.id,false)!="":continue
			p=c;break
		if p.is_finite():break
	if not ck("ordinary cleared visible control plot",p.is_finite()):finish();return
	if not await build_open("house"):finish();return
	var poor=await tap_build("house",p,"visible_unaffordable_control")
	ck("visible shortage preserves amber and cost-only guidance, no Recon",poor.get("reason")=="資源不足" and poor.reason_ignoring_funds=="" and not poor.enabled and poor.color=="e4bc68" and not g.build_recon_button.is_visible_in_tree())
	finish()
