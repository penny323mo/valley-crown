extends SceneTree
const Roster=preload("res://scripts/army_roster.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func unit(id,kind,hp=10):
 return {"id":id,"kind":kind,"owned":true,"remembered":false,"alive":true,"team":0,"category":"unit","state":"idle","hp":hp,"max_hp":10,"path":[]}
func run():
 var records={1:unit(1,"spearman"),2:unit(2,"spearman",5),3:unit(3,"villager"),4:unit(4,"archer")}
 records[4].team=1;records[4].owned=false
 records[5]={"id":5,"owned":true,"remembered":false,"alive":true,"team":0,"category":"building","built":true,"queue":[{"kind":"spearman"},{"kind":"armor"},{"kind":"archer"}]}
 var original=records.duplicate(true)
 var status=Roster.snapshot(records,[{"team":0,"ids":[1],"type":"order"}])
 check("roster counts owned current troop kind",status.spearman.ids==[1,2])
 check("wounded membership uses actual missing HP",status.spearman.wounded==[2])
 check("pending command is not counted idle",status.spearman.idle==1)
 check("paid queue counts unit not research",status.spearman.queued==1 and status.archer.queued==1)
 check("enemy and villagers excluded",status.archer.ids.is_empty() and not status.has("villager"))
 check("snapshot does not mutate source",records==original)
 records[2].remembered=true;records[1].alive=false
 check("dead and remembered members excluded",Roster.snapshot(records).spearman.ids.is_empty())
 var game=load("res://main.tscn").instantiate();game.skirmish_mode="fortress";root.add_child(game);game.set_process(false);game.ai_enabled=false;await process_frame
 game.paused=false;game.application_focused=true;game.application_suspended=false
 game._update_vision();game._update_hud()
 var roster=Roster.snapshot(game.faction_views[0].records(),game.commands)
 check("fortress roster exposes all four main military types",roster.spearman.ids.size()==4 and roster.archer.ids.size()==4 and roster.cavalry.ids.size()==2 and roster.siege.ids.size()==2)
 game.compact_menu.show();game._set_shortcut_category("army");game._refresh_army_roster()
 check("army category exposes roster controls",game.army_roster_buttons.cavalry.all.is_visible_in_tree())
 var before=game.commands.duplicate(true)
 game._select_roster("cavalry",false)
 check("troop button selects all and only owned cavalry",game.selected==roster.cavalry.ids)
 check("selection does not issue gameplay orders",game.commands==before)
 var injured=game._get_entity(roster.cavalry.ids[0]);injured.hp-=10;game._update_vision()
 game.compact_menu.show();game._refresh_army_roster();game._select_roster("cavalry",true)
 check("wounded shortcut selects actual injured cavalry",game.selected==[injured.id])
 game.compact_menu.show();game._refresh_army_roster()
 injured.hp=injured.max_hp;game._update_vision();game._select_roster("cavalry",true)
 check("stale wound membership cannot reuse held action",game.selected==[injured.id] and game.compact_menu.visible)
 game.paused=true;game._refresh_army_roster()
 check("paused roster cannot issue selection actions",game.army_roster_buttons.spearman.all.disabled)
 check("roster economy is unchanged",game.economy.audit().ok)
 game.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"army_roster_contract","checks":checks,"failed":failed,"scope":"Native roster observations and actual menu selection callbacks; not physical phone acceptance"}))
 quit(1 if failed else 0)
