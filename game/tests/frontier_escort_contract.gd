extends SceneTree
const Mission=preload("res://scripts/frontier_escort.gd")
const Store=preload("res://scripts/checkpoint_store.gd")
const Expedition=preload("res://scripts/expedition_checkpoint_store.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func run():
 var m=Mission.new();m.villagers=[1,2,3]
 var people=[]
 for id in [1,2,3]:people.append({"id":id,"alive":true,"kind":"villager","team":0,"pos":Vector3(-20,0,20)})
 check("outside party does not advance",not m.update(1,people) and m.stage==0)
 people[0].pos=Mission.TARGET
 check("one living party member arrives",m.update(2,people) and m.stage==1)
 var sites=[]
 for pair in [["storehouse",4],["tower",5]]:sites.append({"id":pair[1],"alive":true,"kind":pair[0],"team":0,"pos":Mission.TARGET,"built":true,"cost_receipt_id":""})
 check("free scripted buildings do not qualify",not m.update(3,people+sites))
 for b in sites:b.cost_receipt_id="paid"
 sites[1].built=false
 check("unfinished tower cannot advance",not m.update(4,people+sites))
 sites[1].built=true
 check("two paid completed sites begin countdown",m.update(5,people+sites) and m.due==605)
 check("countdown HUD is explicit",m.progress_text(585)=="反攻 1 秒後出發" and m.progress_text(605)=="集結區受阻 · 等候出發")
 check("countdown requires full thirty seconds",not m.ready(604) and m.ready(605))
 check("short roster rejected",not m.launch([10]))
 check("duplicate counter IDs rejected",not m.launch([10,10,11,12,13,14]))
 check("six counter IDs launch once",m.launch([10,11,12,13,14,15]) and not m.launch([20,21,22,23,24,25]))
 var enemy={"id":10,"alive":true,"kind":"spearman","team":1,"pos":Mission.TARGET}
 check("living counter prevents victory",not m.update(606,people+sites+[enemy]))
 sites[1].alive=false
 check("destroyed site prevents victory after counter cleared",not m.update(607,people+sites))
 sites[1].alive=true
 check("rebuilding allows mission completion",m.update(608,people+sites) and m.stage==3)
 check("completed stage cannot repeat",not m.update(609,people+sites))
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="escort";g.history_path="/tmp/escort-contract-history.json"
 root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 check("three original mission villagers selected",g.frontier_escort.villagers.size()==3)
 check("opening resource stock preserved",g.economy.bank_milli(0).wood==200000 and g.economy.bank_milli(0).stone==100000)
 check("ordinary slot refuses before creating file",not Store.save_slot(g,"/tmp/escort-contract-never-write.bin").ok and not FileAccess.file_exists("/tmp/escort-contract-never-write.bin"))
 check("expedition slot refuses before creating file",not Expedition.save_slot(g,"/tmp/escort-contract-never-write2.bin").ok and not FileAccess.file_exists("/tmp/escort-contract-never-write2.bin"))
 g._select_escort_party()
 check("party shortcut selects precisely living mission workers",g.selected==g.frontier_escort.villagers)
 check("party shortcut does not issue commands",g.commands.is_empty())
 check("mission HUD appears",g.objective_button.visible and g.objective_button.text.contains("護送"))
 var fog=g.explored_cells[0].duplicate()
 g._focus_control_point()
 check("objective focus does not reveal fog",g.camera_focus==Mission.TARGET and g.explored_cells[0]==fog)
 for id in g.frontier_escort.villagers:g._kill(g._get_entity(id))
 g._tick(g.Rules.TICK)
 check("all party deaths lose without keep destruction",g.game_over and g.outcome=="defeat" and g.end_reason=="escort_villagers_lost")
 g.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"frontier_escort_contract","checks":checks,"failed":failed}));quit(0 if failed==0 else 1)
