extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var views=[]

func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
	return bool(ok)

func _initialize():call_deferred("run")

func settle(count=5):
	for i in count:await process_frame

func send_touch(p,index,down,canceled=false):
	var e=InputEventScreenTouch.new()
	e.position=p;e.index=index;e.pressed=down;e.canceled=canceled
	root.push_input(e)
	await process_frame

func tap(button,index):
	var p=button.get_global_rect().get_center()
	await send_touch(p,index,true);await send_touch(p,index,false)
	await settle()

func available(g,button):
	return is_instance_valid(button) and button.is_visible_in_tree() and button.size.x>=44 and button.size.y>=44 and g.action_scroll.get_global_rect().encloses(button.get_global_rect())

func icon_action(g,kind,caption):
	for b in g.actions.get_children():
		if b is Button and b.get_meta("command_icon_kind","")==kind and b.text.begins_with(caption):return b
	return null

func short_swipe(g,link,index):
	var p=link.get_global_rect().get_center()
	await send_touch(p,index,true)
	var last=p
	for n in 4:
		var q=p-Vector2((n+1)*34,0)
		var e=InputEventScreenDrag.new();e.position=q;e.relative=q-last;e.index=index
		root.push_input(e);await process_frame;last=q
	await send_touch(last,index,false);await settle()

func configure(dims,stock={}):
	root.size=dims;await settle()
	var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g)
	g.set_process(false);g.test_mode=true;g.ai_enabled=false
	if stock.is_empty():g._test_reset()
	else:g._test_reset([stock,stock.duplicate(true)])
	g._layout_ui();await settle()
	return g

func observe(g,keep,expected,caption,tag):
	var link=g.town_research_jump
	var train=icon_action(g,"villager","訓練")
	var scout=icon_action(g,"scout","訓練")
	var action=icon_action(g,expected,caption)
	var start=g.action_scroll.scroll_horizontal
	var camera=g.camera_focus
	var bank=g.economy.bank_milli(0).duplicate(true)
	var initial_queue=keep.queue.duplicate(true)
	var hud_height=g.hud_bottom.size.y
	if not check(tag+": natural start exposes both training actions and same 44px+ research link",available(g,link) and available(g,train) and available(g,scout) and not available(g,action) and link.text=="研究 >"):
		return false
	await tap(link,50)
	var right=g.action_scroll.scroll_horizontal
	var back=g.town_research_return
	var jump_ok=check(tag+": one lone tap reveals first research and 44px+ back control",right>start and available(g,action) and available(g,back) and back.text=="< 訓練")
	check(tag+": forward moves focus to visible return after settling",root.gui_get_focus_owner()==back)
	check(tag+": forward stays in same lane without gameplay change",g.selected==[keep.id] and g.camera_focus==camera and not g.touch_command and g.build_mode.is_empty() and g.commands.is_empty() and g.economy.bank_milli(0)==bank and keep.queue==initial_queue and g.hud_bottom.size.y==hud_height)
	if not jump_ok:return false
	await tap(back,50)
	check(tag+": one lone return tap restores Train and visible focus",g.action_scroll.scroll_horizontal==start and available(g,link) and available(g,train) and available(g,scout) and root.gui_get_focus_owner()==link)
	check(tag+": repeated-ID return neither pans nor charges nor commands",g.selected==[keep.id] and g.camera_focus==camera and g.commands.is_empty() and g.economy.bank_milli(0)==bank and keep.queue==initial_queue)
	views.append({"tag":tag,"scroll_before":start,"scroll_at_research":right,"scroll_after_return":g.action_scroll.scroll_horizontal,"viewport":[root.size.x,root.size.y],"link_size":[link.size.x,link.size.y],"return_size":[back.size.x,back.size.y]})
	return true

func test_dims(dims):
	var g=await configure(dims)
	var keep=g._first(0,"town_center")
	var worker=g._first(0,"villager")
	g._select([keep.id]);await settle()
	var tag=str(dims)
	var age_start=await observe(g,keep,"age2","城防時代",tag+" age I")
	if not age_start:g.free();await settle();return
	var link=g.town_research_jump
	var old_cam=g.camera_focus
	await short_swipe(g,link,51)
	var shift=g.action_scroll.scroll_horizontal
	check(tag+": short swipe beginning on research link scrolls independently",shift>=132 and shift<=138 and not available(g,icon_action(g,"age2","城防時代")) and g.commands.is_empty() and g.camera_focus==old_cam)
	var rally=null
	for b in g.actions.get_children():
		if b is Button and b.text=="集合點":rally=b
	check(tag+": existing Rally remains reachable after that same short swipe",available(g,rally))
	g._select([]);g._select([keep.id]);await settle()
	link=g.town_research_jump
	var point=link.get_global_rect().get_center()
	await send_touch(point,52,true)
	await send_touch(point+Vector2(35,0),53,true)
	await send_touch(point+Vector2(35,0),53,false)
	await send_touch(point,52,false);await settle()
	check(tag+": two-finger input cannot click link or leak into world",g.action_scroll.scroll_horizontal==0 and g.commands.is_empty() and g.camera_focus==old_cam and g.selected==[keep.id])
	await send_touch(point,54,true);await send_touch(point,54,false,true);await settle()
	check(tag+": canceled release does not jump",g.action_scroll.scroll_horizontal==0 and g.commands.is_empty())
	await tap(link,54)
	check(tag+": next fresh touch after cancellation still jumps",g.action_scroll.scroll_horizontal>0 and g.commands.is_empty())
	await tap(g.town_research_return,54)
	await send_touch(point,55,true);g._select([worker.id]);await settle();await send_touch(point,55,false);await settle()
	check(tag+": stale held link after selecting worker cannot jump/order/pan",g.town_research_jump==null and g.town_research_return==null and g.action_scroll.scroll_horizontal==0 and g.commands.is_empty() and g.camera_focus==old_cam and g.selected==[worker.id])
	# Set a real existing rally via the normal command, then reselect using
	# the ordinary reveal. Train and adjacent link must both remain visible.
	g._select([keep.id]);await settle()
	var rally_point=Vector3.INF
	for z in range(-6,7):
		for x in range(-6,7):
			var pos=keep.pos+Vector3(x,0,z)
			if g.visible_cells[0][g._cell_index(pos)]!=0 and not g.navigation.is_point_solid(g._cell(pos)):
				rally_point=pos;break
		if rally_point.is_finite():break
	if rally_point.is_finite():
		g._submit("rally",{"building":keep.id,"position":rally_point})
		g._tick(Rules.TICK)
	await settle()
	g._select([]);g._select([keep.id]);await settle()
	check(tag+": valid saved rally really adds the existing extra action",keep.get("rally_point",Vector3.INF).is_finite() and g.actions.get_children().any(func(button):return button is Button and button.text=="取消集合點設定"))
	check(tag+": after actual rally row train and research still fit on initial reveal",available(g,icon_action(g,"villager","訓練")) and available(g,g.town_research_jump))
	# Actual paid queue fixture, no rule/economy bypass by the bookmark itself.
	g.free();await settle()
	var stock={"food":3000,"wood":3000,"stone":3000,"iron":3000}
	g=await configure(dims,stock);keep=g._first(0,"town_center")
	g._select([keep.id]);await settle()
	await tap(g.town_research_jump,56)
	var age=icon_action(g,"age2","城防時代")
	await tap(age,57)
	g._tick(Rules.TICK);g._publish_faction_views();g._update_hud();await settle()
	var original_paid=g.economy.bank_milli(0).duplicate(true)
	var paid_item=keep.queue[0] if not keep.queue.is_empty() else {}
	g._select([]);g._select([keep.id]);await settle()
	await tap(g.town_research_jump,58)
	check(tag+": pending age stays discoverable as truly disabled without new cost",available(g,icon_action(g,"age2","城防時代")) and icon_action(g,"age2","城防時代").disabled and not paid_item.is_empty() and paid_item.kind=="age2" and g.economy.bank_milli(0)==original_paid and g.commands.is_empty())
	g.age_completed_tick[0]=g.tick_count-1
	g._select([]);g._select([keep.id]);await settle()
	var age2_start=await observe(g,keep,"forged_blades","鍛鋼",tag+" age II")
	if age2_start:
		await tap(g.town_research_jump,58)
		var tech=icon_action(g,"forged_blades","鍛鋼")
		await tap(tech,59)
		g._tick(Rules.TICK);g._publish_faction_views();g._update_hud();await settle()
		g._select([]);g._select([keep.id]);await settle()
		await tap(g.town_research_jump,58)
		var paid_tech=icon_action(g,"forged_blades","鍛鋼")
		check(tag+": genuine queued technology remains visible as disabled",available(g,paid_tech) and paid_tech.disabled and paid_tech.text.contains("研究中") and keep.queue.any(func(item):return item.kind=="forged_blades"))
	for tech in Rules.RESEARCH_TECHS:g.military_tech_completed[0][tech]=g.tick_count-1
	g._select([]);g._select([keep.id]);await settle()
	check(tag+": no navigation pair once all technologies are completed",g.town_research_jump==null and g.town_research_return==null)
	g.free();await settle()

func run():
	for dims in [Vector2i(568,320),Vector2i(390,844),Vector2i(844,390)]:
		await test_dims(dims)
	var desktop=await configure(Vector2i(1280,720))
	var keep=desktop._first(0,"town_center");desktop._select([keep.id]);await settle()
	check("wide desktop keeps original lane with no added research bookmark",not desktop.compact_ui and desktop.town_research_jump==null and desktop.town_research_return==null)
	desktop.free()
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"town_research_bookmarks_contract","checks":checks,"failed":failed,"measurements":views,"scope":"Real native viewport synthetic touches; seeded age-II eligibility only, existing UI and real production queue."}))
	quit(1 if failed else 0)
