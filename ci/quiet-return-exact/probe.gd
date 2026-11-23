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
var role="unknown"
var marks={}
var captures={}

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
func xyz(p):
	return [p.x,p.y,p.z]
func screen_val(p):
	return [p.x,p.y]
func fits(btn):
	var r=btn.get_global_rect()
	return btn.is_visible_in_tree() and not btn.disabled and root.get_visible_rect().encloses(r) and r.size.x>=44 and r.size.y>=44
func scoped_state():
	var own_pending={}
	for c in g.commands:
		if c.team==0:own_pending[str(c.sequence)]=c.type
	return [g.selected.duplicate(),bank(),own_pending]
func aim_world(center):
	for i in 12:
		var p=g.camera.unproject_position(center)
		if Rect2(Vector2(20,114),Vector2(root.size.x-40,root.size.y-190)).has_point(p) and g._box_point_in_world(p):return true
		var d=Vector2(root.size.x*.5,root.size.y*.51)-p
		var step=Vector2(clampf(d.x,-56,56),clampf(d.y,-20,20))
		if not await pan_pair(step):return false
		await sync_ui()
	return false
func world_alert():
	return g.battle_alerts.peek(g.tick_count)
func hit_cursor():
	return g.combat_veterancy.settled_through
func observed_army():
	var entities=[]
	for rec in g.faction_views[0].records().values():
		if rec.team!=1 or rec.remembered or rec.category!="unit" or not rec.alive:continue
		var p=g.camera.unproject_position(rec.pos+Vector3(0,.6,0))
		entities.append({"id":rec.id,"kind":rec.kind,"screen":screen_val(p),"in_view":root.get_visible_rect().has_point(p),"accepts_world":g._box_point_in_world(p),"pick":g._pick(p)})
	return entities
func map_ui():
	var out={}
	for c in [g.battle_jump_button,g.attack_alert_button,g.pause_button,g.compact_menu_button,g.tutorial_panel,g.hud_bottom,g.hud_top,g.minimap]:
		out[c.name]={"visible":c.is_visible_in_tree(),"rect":shape(c.get_global_rect()),"text":c.text if c is Button else ""}
	return out
func targets():
	var list=[]
	for node in g.end_actions.get_children():
		list.append({"name":node.name,"text":node.text,"rect":shape(node.get_global_rect()),"44px_full":fits(node)})
	return list
func pastown_attacks(cursor):
	var actual=[]
	for id in range(cursor+1,hit_cursor()+1):
		var at=g.attack_ledger.event(id)
		var target=g._get_entity(at.target_id)
		if target.get("team",-1)==0:actual.append({"tick":at.release_tick,"victim":target.kind,"target_id":at.target_id,"damage":at.damage,"site":xyz(at.endpoint)})
	return actual
# Test-only renderer evidence, never changes the camera, entities, banks, or input.
func capture_world():
	var known=g.faction_views[0].records().values().filter(func(r):return r.get("alive",false) and r.get("category","") in ["unit","building"] and (r.get("owned",false) or (r.get("team",-1)==1 and not r.get("remembered",true))))
	known.sort_custom(func(a,b):return a.id<b.id)
	var actors=known.map(func(r):return [r.id,r.kind,xyz(r.pos),r.get("hp",-1),r.get("built",false)])
	return {"tick":g.tick_count,"actors":actors,"bank":bank(),"selected":g.selected.duplicate(),"player_commands":scoped_state()[2],"command_sequence":g.command_sequence,"progress_serial":g.progress_serial,"unread":g.battle_alerts.pending(g.tick_count).size()}

func capture_state():
	return {"world":capture_world(),"camera":str(g.camera.global_transform),"camera_focus":xyz(g.camera_focus),"drawer_open":g.compact_menu.visible,"tutorial_collapsed":g.tutorial_collapsed,"top":shape(g.hud_top.get_global_rect()),"bottom":shape(g.hud_bottom.get_global_rect())}

func save_view(name):
	var state=capture_state()
	var dir=OS.get_environment("VC_QUIET_NATIVE_OUTPUT")
	if not dir.is_empty():
		if not ck(name+" genuine Linux Compatibility framebuffer",DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and "llvmpipe" in RenderingServer.get_video_adapter_name().to_lower()):return false
		var draws=[0]
		var marker=func():draws[0]+=1
		RenderingServer.frame_post_draw.connect(marker);RenderingServer.render_loop_enabled=true
		var start=Time.get_ticks_msec()
		while draws[0]<3 and Time.get_ticks_msec()-start<30000:await process_frame
		RenderingServer.render_loop_enabled=false;RenderingServer.frame_post_draw.disconnect(marker)
		if not ck(name+" three true draws and unchanged authority/viewport",draws[0]>=3 and capture_state()==state):return false
		var im=root.get_texture().get_image()
		if not ck(name+" original viewport",im!=null and not im.is_empty() and im.get_size()==root.size):return false
		var unique={}
		for ix in range(0,root.size.x,17):
			for iy in range(0,root.size.y,17):unique[im.get_pixel(ix,iy).to_rgba32()]=true
		var img=dir+"/"+name+".png"
		if not ck(name+" unaltered rendered pixels",unique.size()>60 and not FileAccess.file_exists(img) and im.save_png(img)==OK):return false
		state.png_sha256=FileAccess.get_sha256(img)
	captures[name]=state
	return true

func finish():
	var failed=checks.filter(func(x):return not x.pass).size()
	print("ACTUAL_QUIET_RETURN "+JSON.stringify({"role":role,"source_basis":"e9f3305743ae4e36a25362de87cf0437e7556da9","runtime_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"alert_sha256":FileAccess.get_sha256("res://scripts/battle_alerts.gd"),"marks":marks,"capture":captures,"build":Rules.BUILD_ID,"engine_hex":Engine.get_version_info().hex,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"rules_sha256":FileAccess.get_sha256("res://scripts/rules.gd"),"manifest_sha256":FileAccess.get_sha256("res://reports/build-manifest.json"),"size":[root.size.x,root.size.y],"checks":checks,"failed":failed,"observations":observations,"gestures":serial,"scope":"Fresh ordinary Standard; no player combat/placement commands, current AI authentic damage, controls routed through native Godot touches; frame advancement manually deterministic, no spawned actors/geometry/HP/fog. Native layout not a device or browser report."}))
	quit(1 if failed else 0)
func run():
	var args=OS.get_cmdline_user_args()
	root.size=Vector2i(int(args[0]),int(args[1]))
	role=args[2]
	menu=load("res://main_menu.tscn").instantiate();root.add_child(menu);await frames()
	for name in ["StartMatchButton","BattleGroup0","ChooseBattle_standard","LaunchMatchButton"]:
		if not ck("authentic Standard menu touch "+name,await menu_click(name)):finish();return
		if is_instance_valid(menu.match_node):menu.match_node.set_process(false)
	g=menu.match_node
	await sync_ui()
	var initial=g.camera_focus
	var keep=g._first(0,"town_center")
	if not ck("fresh normal authority and original keep selected",g.skirmish_mode=="standard" and not g.test_mode and g.ai_enabled and g.selected==[keep.id] and g.tick_count<15):finish();return
	var deposit=bank()
	var visual_pre=[]
	for i in 14:
		var p=g.camera.unproject_position(keep.pos)
		if not root.get_visible_rect().has_point(p):break
		if not await pan_pair(Vector2(-52,0)):break
		await sync_ui()
	var home_pixel=g.camera.unproject_position(keep.pos)
	note("off_home_before_damage",{"focus":xyz(g.camera_focus),"keep_pixel":screen_val(home_pixel),"visible":root.get_visible_rect().has_point(home_pixel),"initial":xyz(initial),"bank":bank()})
	if not ck("camera moved to an ordinary fully offscreen home state using only two-finger pans",not root.get_visible_rect().has_point(home_pixel) and bank()==deposit and g.commands.is_empty()):finish();return
	var attack_wait=await ticks_until(func():return not world_alert().is_empty(),5100)
	var first=world_alert()
	if not ck("normal enemy attack creates first genuine settled own-damage alert",not first.is_empty() and attack_wait>0 and g.ai_raids>0 and hit_cursor()>0):finish();return
	var first_ui=map_ui()
	var exact=g.camera.unproject_position(first.position)
	note("first_damage_alert",{"tick":g.tick_count,"alert":{"position":xyz(first.position),"sequence":first.sequence,"victim":first.kind},"point_before_jump":screen_val(exact),"outside":not root.get_visible_rect().has_point(exact),"settled_through":hit_cursor(),"real_input":fits(g.battle_jump_button),"tooltip":g.battle_jump_button.tooltip_text,"ui":first_ui})
	if not ck("live first reply affordance fully touchable 44px and not overlapping Pause/Menu",fits(g.battle_jump_button) and not g.battle_jump_button.get_global_rect().intersects(g.pause_button.get_global_rect()) and not g.battle_jump_button.get_global_rect().intersects(g.compact_menu_button.get_global_rect())):finish();return
	var before=scoped_state()
	var jump_rect=g.battle_jump_button.get_global_rect()
	await tap(jump_rect.get_center());await sync_ui()
	var after_target=g.camera.unproject_position(first.position)
	note("first_touch_destination",{"tick":g.tick_count,"camera_focus":xyz(g.camera_focus),"desired":xyz(first.position),"target_on_screen":screen_val(after_target),"target_world_roi":g._box_point_in_world(after_target),"seen_enemy":observed_army(),"pending_after_ack":g.battle_alerts.pending(g.tick_count).size(),"hud":map_ui()})
	if not ck("one real alert tap centers own victim without opening menu/spending/command",g.camera_focus==first.position and not g.compact_menu.visible and scoped_state()==before):finish();return
	var post_ack_hit=hit_cursor()
	var depart_rect={}
	for i in 14:
		var p=g.camera.unproject_position(first.position)
		if not root.get_visible_rect().has_point(p):break
		if not await pan_pair(Vector2(-52,0)):break
		await sync_ui()
	var attack_spot=g.camera.unproject_position(first.position)
	if not ck("same real attack site leaves the full viewport again with camera only",not root.get_visible_rect().has_point(attack_spot) and scoped_state()==before):finish();return
	var dwell=[]
	for i in 20:
		await ticks_until(func():return false,20)
		var b=g.battle_alerts.entries.filter(func(e):return e.sequence==first.sequence)
		var now_hit=hit_cursor()
		dwell.append({"tick":g.tick_count,"new_contacts":now_hit-post_ack_hit,"ongoing_own_hits":pastown_attacks(post_ack_hit).size(),"same_entry":not b.is_empty(),"expiry":b[0].expires if not b.is_empty() else -1,"acknowledged":b[0].acknowledged if not b.is_empty() else false,"pending":g.battle_alerts.pending(g.tick_count).size(),"button_visible":g.battle_jump_button.is_visible_in_tree(),"keep_hp":keep.hp,"source":"actual normal enemy attack ledger"})
		if g.game_over:break
	note("offscreen_fight_after_ack",{"spot":screen_val(attack_spot),"focus":xyz(g.camera_focus),"samples":dwell,"seen_enemy_on_screen":observed_army().filter(func(x):return x.in_view),"settlings_after":hit_cursor()-post_ack_hit,"own_attack_log":pastown_attacks(post_ack_hit),"navigation_hud":map_ui()})
	var attack_log=pastown_attacks(post_ack_hit)
	var kept=attack_log.filter(func(x):return x.victim=="town_center")
	if not ck("same natural offscreen exchange continues across 20 seconds after acknowledged Scout dies",g.tick_count==4092 and attack_log.size()==25 and kept.size()==14 and keep.hp==1150 and g.battle_alerts.pending(g.tick_count).is_empty() and dwell.all(func(x):return x.acknowledged and not x.button_visible and x.pending==0)):finish();return
	var offscreen_keep=g.camera.unproject_position(keep.pos)
	var old_camera=g.camera_focus
	var old_view=g.visible_cells[0].duplicate()
	var old_progress=g.progress_serial
	var old_command_sequence=g.command_sequence
	var previous_stamp=g._first(0,"town_center").last_damage_tick
	var toast_before=[g.toast_label.text,g.toast_time]
	if not ck("keep late hit truly off screen before Menu",not root.get_visible_rect().has_point(offscreen_keep) and kept[-1].tick>=4090 and previous_stamp>=4090):finish();return
	if not ck("ordinary Menu fully reachable and shows the drawer",fits(g.compact_menu_button)):finish();return
	await tap(g.compact_menu_button.get_global_rect().get_center());await sync_ui()
	var button=g.find_child("ReturnToBattleSite",true,false)
	if not ck("exact matched pre-return gameplay state in opened Menu",g.compact_menu.visible and old_camera==g.camera_focus and scoped_state()==before and not g.battle_jump_button.visible and not g.attack_alert_button.visible and g.tick_count==4092):finish();return
	marks["menu_offscreen"]={"tick":g.tick_count,"focus":xyz(old_camera),"keep_projected":screen_val(offscreen_keep),"hp":keep.hp,"bank":bank(),"selected":g.selected.duplicate(),"unread":g.battle_alerts.pending(g.tick_count).size(),"keep_last_damage_tick":previous_stamp,"button":shape(button.get_global_rect()) if is_instance_valid(button) else [],"menu_rect":shape(g.compact_menu.get_global_rect())}
	if not await save_view("offscreen-drawer"):finish();return
	if role=="candidate":
		if not ck("quiet return is pinned 44+px with original top alert absent",is_instance_valid(button) and fits(button) and button.text=="回看" and not g.shortcut_scroll.is_ancestor_of(button) and not button.get_global_rect().intersects(g.pause_button.get_global_rect()) and not button.get_global_rect().intersects(g.compact_menu_button.get_global_rect())):finish();return
		await tap(button.get_global_rect().get_center());await sync_ui()
		var center=g.camera.unproject_position(keep.pos)
		var footprint=[]
		for a in [-1.5,1.5]:
			for b in [-1.5,1.5]:
				var p=g.camera.unproject_position(keep.pos+Vector3(a,0,b))
				footprint.append({"pixel":screen_val(p),"world_roi":g._box_point_in_world(p)})
		var nearby_enemy=observed_army().filter(func(a):return a.in_view and a.accepts_world)
		marks["return"]={"tick":g.tick_count,"focus":xyz(g.camera_focus),"keep_center":screen_val(center),"footprint":footprint,"opposing_force":nearby_enemy,"keep_hp":keep.hp,"bank":bank(),"selected":g.selected.duplicate(),"unread":g.battle_alerts.pending(g.tick_count).size(),"drawer":g.compact_menu.visible}
		if not ck("genuine quiet native tap frames ongoing keep engagement at latest settled friendly hit",g.camera_focus==keep.pos and not g.compact_menu.visible and g._box_point_in_world(center) and footprint.all(func(f):return f.world_roi) and not nearby_enemy.is_empty()):finish();return
		if not ck("camera return is presentation-only and never reopens unread alert, message, or ping",scoped_state()==before and g.visible_cells[0]==old_view and g.progress_serial==old_progress and g.command_sequence==old_command_sequence and g.tick_count==4092 and keep.hp==1150 and g.battle_alerts.pending(g.tick_count).is_empty() and not g.battle_jump_button.visible and [g.toast_label.text,g.toast_time]==toast_before):finish();return
		if not await save_view("fight-returned"):finish();return
	else:
		if not ck("original drawer lacks return to active fight at the exact matched state",not is_instance_valid(button) and g.camera_focus==old_camera):finish();return
		await tap(g.compact_menu_button.get_global_rect().get_center());await sync_ui()
	await ticks_until(func():return g.game_over,6700)
	if not ck("actual normal enemy damage brings settled keep-loss defeat without surrender or test overrides",g.tick_count==6558 and g.game_over and g.outcome=="defeat" and g.end_reason=="keep_destroyed" and keep.hp<=0 and g.end_panel.visible):finish();return
	if not ck("quiet return is unavailable once genuine match ends",not is_instance_valid(button) or not button.is_visible_in_tree()):finish();return
	var body=g.end_body.get_global_rect()
	var content=g.end_report_label.get_global_rect()
	var line=g.end_report_label.get_theme_font("font").get_height(g.end_report_label.get_theme_font_size("font_size"))+g.end_report_label.get_theme_constant("line_spacing")
	note("natural_defeat",{"tick":g.tick_count,"title":g.end_title.text,"title_full":root.get_visible_rect().encloses(g.end_title.get_global_rect()),"body":g.end_body.text,"body_visible":g.end_body.is_visible_in_tree(),"body_fully_in_scroll":g.end_scroll.get_global_rect().encloses(body),"title_rect":shape(g.end_title.get_global_rect()),"report_scroll":shape(g.end_scroll.get_global_rect()),"report_first_visible_px":content.intersection(g.end_scroll.get_global_rect()).size.y,"line_height_px":line,"row_names":g.end_report_label.text.split("\n").slice(0,5),"actions":targets(),"attack_report":g.last_match_report})
	var battlefield=g.end_actions.get_children().filter(func(c):return c.text=="查看戰場")
	if not ck("natural defeat includes actual battlefield review action",battlefield.size()==1 and fits(battlefield[0])):finish();return
	var end_before=scoped_state()
	await tap(battlefield[0].get_global_rect().get_center());await sync_ui()
	var resume=g.find_child("ReturnMatchReportButton",true,false)
	note("review_after_natural_defeat",{"after_view":g.aftermath_view,"end_panel":g.end_panel.visible,"terminal_unchanged":g.last_match_report.outcome,"search_button_exists":is_instance_valid(resume)})
	ck("real Review Battlefield does not change outcome or game state",g.aftermath_view and not g.end_panel.visible and scoped_state()==end_before and g.game_over)
	finish()
