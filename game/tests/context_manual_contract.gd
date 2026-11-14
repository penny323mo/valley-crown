extends SceneTree
const Context=preload("res://scripts/context_manual.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func record(kind,category="unit"):return {"kind":kind,"category":category,"owned":true,"alive":true,"team":0}
func _initialize():call_deferred("run")
func settle():
	for i in 4:await process_frame
func run():
	var records={1:record("archer"),2:record("archer"),3:record("spearman"),4:record("barracks","building")}
	check("same type group gets matching manual",Context.selected_entry(records,[1,2]).kind=="archer")
	check("mixed group not mislabelled",Context.selected_entry(records,[1,3]).is_empty())
	check("building entry resolved",Context.selected_entry(records,[4]).kind=="barracks")
	for patch in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"category":"resource"}]:
		var r=record("archer");r.merge(patch,true);check("excluded "+str(patch),Context.selected_entry({1:r},[1]).is_empty())
	check("actual range from rules",Context.selected_entry(records,[1]).body.contains("射程 %.1f" % Rules.RANGE.archer))
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await settle()
	var scout=g._first(0,"scout");g._select([scout.id]);g._update_hud()
	var before=g.commands.duplicate(true);var selected=g.selected.duplicate();var bank=g.economy.bank_milli(0).duplicate()
	for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		root.size=size;g._layout_ui();await settle();g._show_context_manual();await settle()
		var dialog=g.ui.get_node_or_null("ContextManualDialog")
		check("dialog opens "+str(size),is_instance_valid(dialog) and dialog.visible)
		if not is_instance_valid(dialog):continue
		var body=dialog.get_node("ManualBody")
		check("scrollable truthful text "+str(size),body.scroll_active and body.text.contains("戰役繼續") and body.text.contains("斥候") == false and body.text.contains("移速 3.2"))
		check("dialog fits viewport "+str(size),dialog.size.x<=size.x and dialog.size.y<=size.y)
		g._show_context_manual();var count=0
		for child in g.ui.get_children():
			if child is Window and child.visible:count+=1
		check("no stacked info windows "+str(size),count==1)
		dialog.confirmed.emit();await settle()
		check("dismiss removes info window "+str(size),not is_instance_valid(g.ui.get_node_or_null("ContextManualDialog")))
	check("info never changes selection orders or bank",g.selected==selected and g.commands==before and g.economy.bank_milli(0)==bank)
	var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({"suite":"context_manual_contract","checks":checks,"failed":failed,"scope":"Actual logical HUD/modal geometry; not physical phone acceptance"}));g.queue_free();quit(1 if failed else 0)
