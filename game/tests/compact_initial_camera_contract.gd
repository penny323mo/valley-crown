extends SceneTree
const Codec=preload('res://scripts/checkpoint_codec.gd')
const Restore=preload('res://scripts/checkpoint_restore.gd')
var checks=[]
func check(n,v):
 checks.append({'name':n,'passed':bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred('run')
func run():
 var shell=load('res://main_menu.tscn').instantiate();root.add_child(shell);await process_frame
 shell.history_path='/tmp/camera-contract-history.json'
 for size in [Vector2i(640,360),Vector2i(390,844),Vector2i(844,390),Vector2i(1280,720)]:
  root.size=size;await process_frame
  shell._replace_match();var g=shell.match_node;g.set_process(false)
  var expected=22.0 if size.y<560 else 30.0
  check('fresh '+str(size),g.camera_zoom==expected and g.camera.size==expected)
  g.camera_zoom=35;g._camera_update();g._layout_ui()
  check('layout preserves manual '+str(size),g.camera_zoom==35)
  root.size=Vector2i(800,600);await process_frame;g._layout_ui()
  check('resize preserves manual '+str(size),g.camera_zoom==35)
  shell._open_menu();shell._finish_resume();g.set_process(false)
  check('resume preserves manual '+str(size),g.camera_zoom==35)
  var focus=g.camera_focus;g._pan_camera(Vector2(10,0));g._camera_update()
  check('pan changes focus not zoom '+str(size),g.camera_focus!=focus and g.camera_zoom==35)
  g.touch_pinch_active=true;g.touch_previous_distance=100;g._update_touch_pinch(1000)
  check('pinch min unchanged '+str(size),g.camera_zoom==15)
  g.touch_previous_distance=1000;g._update_touch_pinch(1)
  check('pinch max unchanged '+str(size),g.camera_zoom==46)
  g.touch_pinch_active=false
  for z in [17.0,35.0]:
   g.camera_zoom=z;g._camera_update();var saved=Codec.capture_result(g)
   check('snapshot valid '+str(z),saved.ok)
   check('restore exact manual camera '+str(z),Restore.apply(g,saved.data) and g.camera_zoom==z and g.camera.size==z and g.paused)
  # Explicit override remains unchanged even if helper is called at fresh setup.
  g.camera_zoom=27;shell._configure_new_match_camera(g);check('explicit override preserved',g.camera_zoom==27)
  shell.remove_child(g);g.free();shell.match_node=null;await process_frame
 for mode in ['battle','fortress','breach']:
  root.size=Vector2i(640,360);shell.selected_mode=mode;shell._replace_match();var g=shell.match_node;g.set_process(false)
  check(mode+' preset focus preserved',g.camera_focus==(Vector3(-4,0,6) if mode=='breach' else Vector3(-25,0,11)) and g.camera_zoom==22)
  shell.remove_child(g)
  g.free();shell.match_node=null;await process_frame
 var fail=checks.filter(func(c):return not c.passed).size();print(JSON.stringify({'suite':'compact_initial_camera_contract','scope':'new match short viewport camera; headless contract, not physical phone','checks':checks,'failed':fail}));shell.free();quit(1 if fail else 0)
