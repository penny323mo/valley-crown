extends SceneTree
const Store=preload('res://scripts/checkpoint_store.gd')
var checks=[]
func check(n,v):
 checks.append({'name':n,'passed':bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred('run')
func run():
 var shell=load('res://main_menu.tscn').instantiate();root.add_child(shell);await process_frame
 shell.history_path='/tmp/camera-routes-history.json';shell.checkpoint_path='/tmp/camera-routes-'+str(Time.get_ticks_usec())+'.bin'
 for size in [Vector2i(760,560),Vector2i(759,560),Vector2i(760,559)]:
  root.size=size;await process_frame;shell._start_match();await process_frame;await process_frame
  var g=shell.match_node;g.set_process(false)
  check('real start boundary '+str(size),g.camera_zoom==(22.0 if size.y<560 else 30.0))
 root.size=Vector2i(640,360);await process_frame
 shell._restart_match();await process_frame;await process_frame
 var g=shell.match_node;g.set_process(false);check('real restart compact fresh',g.camera_zoom==22 and g.camera.size==22)
 for z in [17.0,35.0]:
  g.camera_zoom=z;g._camera_update();g.paused=true
  check('save through actual slot '+str(z),Store.save_slot(g,shell.checkpoint_path).ok)
  shell._restore_checkpoint();g=shell.match_node;g.set_process(false)
  check('menu restore preserves '+str(z),g.camera_zoom==z and g.camera.size==z and g.paused)
 g.process_mode=Node.PROCESS_MODE_INHERIT;g.paused=false;g._test_reset();g.test_mode=false;g.ai_enabled=false
 var a=g._spawn('spearman',0,Vector3.ZERO);g._navigation_rebuild();g._update_vision();g._publish_faction_views()
 for z in [15.0,22.0,30.0]:
  g.camera_zoom=z;g.camera_focus=Vector3.ZERO;g._camera_update();g._update_visuals(0);await process_frame
  var screen=g.camera.unproject_position(a.pos+Vector3(0,.6,0));g._select([]);g._tap(screen,true)
  check('touch world pick '+str(z),a.id in g.selected)
  g._tap(g.camera.unproject_position(Vector3(6,0,-6)),true);g._process(.05)
  print('DIAGNOSTIC '+JSON.stringify({'zoom':z,'state':a.state,'touch_command':g.touch_command,'pos':str(a.pos),'commands':g.commands}))
  check('contextual destination without command '+str(z),a.state=='move' and not g.touch_command)
 var failed=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({'suite':'compact_camera_routes_contract','scope':'menu start restore and contextual tap paths; headless contract, not physical phone','checks':checks,'failed':failed}));shell.free();quit(1 if failed else 0)
