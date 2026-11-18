extends SceneTree
const Codec=preload('res://scripts/checkpoint_codec.gd')
const Restore=preload('res://scripts/checkpoint_restore.gd')
const Rules=preload('res://scripts/rules.gd')
var g
var checks=[]
var rows=[]
func c(n,p):checks.append({'name':'%03d '%checks.size()+n,'passed':bool(p)})
func _initialize():call_deferred('run')
func settle():await process_frame;await process_frame;await process_frame
func tap(b):
 var p=b.get_global_rect().get_center();var e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=true;root.push_input(e,true);await process_frame
 e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=false;root.push_input(e,true);await settle()
func alerts():
 g.battle_alerts.reset()
 for p in [Vector3(-25,0,24),Vector3(-8,0,15),Vector3(10,0,10),Vector3(20,0,20)]:
  g.battle_alerts.record_hit({'team':0,'alive':true,'category':'building','pos':p,'kind':'house'},1,g.tick_count)
 g._update_hud();g._layout_ui()
func run():
 var args=OS.get_cmdline_user_args();var output=args[0] if not args.is_empty() else ''
 g=load('res://main.tscn').instantiate();g.history_path='user://topbar-contract-isolated-history.json';root.add_child(g);g.set_process(false);g.test_mode=false
 c('fresh own keep exists',not g._first(0,'town_center').is_empty());if g.paused:g._toggle_pause()
 for sz in [Vector2i(640,360),Vector2i(667,375),Vector2i(740,360),Vector2i(844,390),Vector2i(390,844),Vector2i(430,932)]:
  root.size=sz;await settle()
  for high in [false,true]:
   var bank={'food':999999 if high else 185,'wood':999999 if high else 215,'stone':999999 if high else 100,'iron':999999 if high else 0}
   g.economy=preload('res://scripts/economy_ledger.gd').new(['food','wood','stone','iron']);c('controlled integer bank initialized',g.economy.initialize([bank,bank]).get('ok',false))
   alerts();await settle();g._layout_ui();await settle()
   c('actual four-resource bank exact '+str(sz)+' high='+str(high),g.economy.bank_units_floor(0)==bank)
   if sz.x==640:c('640 actual measured fallback '+str(high),(g.top_resources.get_parent()==g.compact_top_stack)==high)
   var label=str(sz)+' high='+str(high);var controls=[g.top_resources,g.time_label,g.pause_button,g.battle_jump_button,g.compact_menu_button]
   var rects=[]
   for ctrl in controls:
    var role=['resources','clock','pause','alert','menu'][controls.find(ctrl)]
    var rr=ctrl.get_global_rect();rects.append({'text':ctrl.text,'rect':str(rr),'min':str(ctrl.get_combined_minimum_size())})
    c(label+' inside '+role,Rect2(Vector2.ZERO,Vector2(sz)).encloses(rr))
    c(label+' panel encloses '+role,g.hud_top.get_global_rect().encloses(rr))
    c(label+' font readable '+role,ctrl.get_theme_font_size('font_size')>=14)
    if ctrl is Button:c(label+' touch46 '+role,rr.size.x>=46 and rr.size.y>=46)
   for i in controls.size():
    for j in range(i+1,controls.size()):c(label+' disjoint '+str(i)+'/'+str(j),not controls[i].get_global_rect().intersects(controls[j].get_global_rect()))
   rows.append({'size':str(sz),'high':high,'height':g.hud_top.size.y,'controls':rects})
   var n=g.battle_alerts.pending(g.tick_count).size();var selected=g.selected.duplicate();await tap(g.battle_jump_button)
   c(label+' routed alert acknowledges',g.battle_alerts.pending(g.tick_count).size()==n-1 and g.selected==selected)
   await tap(g.pause_button);c(label+' routed pause',g.paused)
   c(label+' paused alert disabled',g.battle_jump_button.disabled)
   var waiting=g.battle_alerts.pending(g.tick_count).size();await tap(g.battle_jump_button);c(label+' paused alert no acknowledgement',g.battle_alerts.pending(g.tick_count).size()==waiting)
   await tap(g.pause_button);c(label+' routed resume',not g.paused)
   await tap(g.compact_menu_button);c(label+' routed menu',g.compact_menu.visible)
   await tap(g.compact_menu_button);c(label+' routed close',not g.compact_menu.visible)
 # Only product deferred relayout for dynamic content/size transitions.
 var transitions=[]
 for spec in [[640,false,4,false],[640,true,4,false],[640,false,4,false],[640,false,0,false],[640,false,4,false],[640,false,0,true],[640,false,0,false],[619,false,4,false],[620,false,4,false],[844,false,4,false],[740,false,4,false]]:
  root.size=Vector2i(spec[0],360)
  var bank={'food':999999 if spec[1] else 185,'wood':999999 if spec[1] else 215,'stone':999999 if spec[1] else 100,'iron':999999 if spec[1] else 0}
  g.economy=preload('res://scripts/economy_ledger.gd').new(['food','wood','stone','iron']);c('dynamic bank init',g.economy.initialize([bank,bank]).ok)
  g.demo_tutorial.skipped=spec[3];g.battle_alerts.reset()
  for i in spec[2]:g.battle_alerts.record_hit({'team':0,'alive':true,'category':'building','pos':Vector3(i*10,0,0),'kind':'house'},1,g.tick_count)
  g._update_hud()
  var frames=[]
  for f in 6:
   await process_frame
   var controls=[g.top_resources,g.time_label,g.pause_button,g.compact_menu_button]
   if g.battle_jump_button.visible:controls.append(g.battle_jump_button)
   var valid=true
   for ctrl in controls:valid=valid and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(ctrl.get_global_rect())
   for i in controls.size():
    for j in range(i+1,controls.size()):valid=valid and not controls[i].get_global_rect().intersects(controls[j].get_global_rect())
   frames.append({'height':g.hud_top.size.y,'valid':valid,'resource':str(g.top_resources.get_global_rect())})
  c('deferred all observed frames valid '+str(spec),frames.all(func(frame):return frame.valid))
  c('deferred final valid '+str(spec),frames[-1].valid)
  c('deferred settled stable '+str(spec),frames[-1]==frames[-2] and frames[-2]==frames[-3])
  transitions.append({'spec':spec,'frames':frames})
 var result={'suite':'measured_battle_topbar_contract','checks':checks,'failed':checks.filter(func(x):return not x.passed).size(),'rows':rows,'transitions':transitions,'scope':'Controlled isolated high-bank and four real alert API records for layout stress, not natural match screenshot.'}
 if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,'\t'))
 print(JSON.stringify(result));g.free();quit(1 if result.failed else 0)
