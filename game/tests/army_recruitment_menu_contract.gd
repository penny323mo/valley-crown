extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="fortress";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 g._test_reset([{"food":2000,"wood":2000,"stone":1000,"iron":1000},{"food":150,"wood":200,"stone":100,"iron":0}]);g.set_process(false);await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var first=g._first(0,"barracks");var second=g._spawn("barracks",0,Vector3(-3.5,0,24.5));g._update_vision();g._update_hud()
 g.compact_menu.show();g._set_shortcut_category("army");g._refresh_army_roster()
 var plan=g._army_recruitment_plan("spearman");var button=g.army_roster_buttons.spearman.recruit
 check("roster recruitment is visible without building selection",button.is_visible_in_tree() and not button.disabled and g.selected.is_empty())
 check("three replacements split two available barracks",plan.count==3 and plan.orders[0].building==first.id and plan.orders[1].building==second.id and plan.orders[2].building==first.id)
 var bank=g.economy.bank_milli(0).duplicate();var pop=g._population(0);var selected=g.selected.duplicate();var center=g.camera_focus
 g._recruit_from_roster("spearman")
 check("actual menu callback queues three ordinary training orders",g.commands.size()==3 and g.commands.all(func(c):return c.type=="train" and c.kind=="spearman" and c.team==0))
 check("orders do not teleport camera or replace selection",g.selected==selected and g.camera_focus==center)
 check("pending requests do not claim paid queue yet",first.queue.is_empty() and second.queue.is_empty() and g.economy.bank_milli(0)==bank)
 g._recruit_from_roster("spearman");check("double tap cannot duplicate pending recruitment",g.commands.size()==3)
 while not g.commands.is_empty():g._execute(g.commands.pop_front())
 check("ordinary queue authorities accept two plus one",first.queue.size()==2 and second.queue.size()==1)
 check("ordinary cost debited exactly three times",g.economy.bank_milli(0).food==bank.food-150000 and g.economy.bank_milli(0).wood==bank.wood-60000)
 check("ordinary population reserved for each replacement",g._population(0)==pop+3)
 check("reinforcement does not enable repeating production",first.get("repeat_kind","").is_empty() and second.get("repeat_kind","").is_empty())
 g._update_vision();g._refresh_army_roster();button.set_meta("squad_ids",[]);g._recruit_from_roster("spearman")
 check("stale displayed plan is rejected not silently repriced",g.commands.is_empty())
 g.paused=true;g._refresh_army_roster();g._recruit_from_roster("archer")
 check("paused match cannot recruit",g.commands.is_empty() and g.army_roster_buttons.archer.recruit.disabled)
 g.paused=false;g._refresh_army_roster();g.compact_menu.hide();g._recruit_from_roster("archer")
 check("hidden menu callback cannot recruit",g.commands.is_empty())
 g.compact_menu.show();g._set_shortcut_category("economy");g._recruit_from_roster("archer")
 check("nonarmy hidden category cannot recruit",g.commands.is_empty())
 g._set_shortcut_category("all");g._refresh_army_roster();g._recruit_from_roster("archer")
 check("all category uses same real recruitment control",g.commands.size()==3)
 while not g.commands.is_empty():g._execute(g.commands.pop_front())
 var spears=g._count(0,"spearman")
 for tick in 360:g._tick(.05)
 check("parallel barracks produce two actual replacements after normal duration",g._count(0,"spearman")==spears+2)
 check("third paid replacement remains in ordinary sequential queue",first.queue.size()==1 and second.queue.is_empty())
 check("economic receipts remain balanced",g.economy.audit().ok)
 g.queue_free();await process_frame
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"army_recruitment_menu_contract","checks":checks,"failed":failed,"scope":"Controlled fortress plus second barracks, real menu and ordinary paid training authority; not phone or natural match acceptance"}));quit(1 if failed else 0)
