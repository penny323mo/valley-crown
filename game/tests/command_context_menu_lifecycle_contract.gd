extends SceneTree
const Store=preload("res://scripts/checkpoint_store.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func settle():
 await process_frame;await process_frame;await process_frame
func arm(g):
 g.set_process(false)
 var id=g._first(0,"town_center").id
 g._select([id]);g._reveal_context_primary([id])
func run():
 root.size=Vector2i(390,844)
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
 shell.history_path="/tmp/context-life-history.json";shell.checkpoint_path="/tmp/context-life-"+str(Time.get_ticks_usec())+".bin"
 shell._start_match();await settle();var g=shell.match_node;g.set_process(false)
 arm(g);shell._open_menu();await settle()
 check("normal leave-to-menu retains paused same game",shell.match_node==g and g.paused and shell.menu_layer.visible)
 shell._resume_match();await settle();g.set_process(false)
 check("normal resume retains game without stale deferred failure",shell.match_node==g and not g.paused and not shell.menu_layer.visible)
 arm(g);var old=weakref(g);shell._restart_match();await settle();g=shell.match_node;g.set_process(false)
 check("normal restart releases armed previous game",old.get_ref()==null and is_instance_valid(g))
 g.paused=true;var saved=Store.save_slot(g,shell.checkpoint_path)
 check("real isolated checkpoint save valid",saved.ok)
 if not saved.ok: shell.free();quit(1);return
 shell._open_menu();shell._show_page("checkpoint");arm(g);old=weakref(g);shell._load_checkpoint();await settle();g=shell.match_node;g.set_process(false)
 print("DIAGNOSTIC "+JSON.stringify({"old_gone":old.get_ref()==null,"paused":g.paused,"menu":shell.menu_layer.visible,"status":shell.checkpoint_status,"busy":shell.transition_busy}))
 check("normal load releases armed prior game and restores paused",old.get_ref()==null and g.paused and shell.menu_layer.visible)
 arm(g);old=weakref(g);shell.free();await settle()
 check("whole menu teardown cancels child pending reveal",old.get_ref()==null)
 var failed=checks.filter(func(x):return not x.passed).size();print(JSON.stringify({"suite":"command_context_menu_lifecycle_contract","checks":checks,"failed":failed,"scope":"Normal menu open/resume/restart/checkpoint replacement and shell free with pending owned receiver; controlled API integration, no physical phone"}));quit(1 if failed else 0)
