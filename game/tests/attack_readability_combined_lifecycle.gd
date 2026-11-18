extends SceneTree
const Rules=preload('res://scripts/rules.gd')
const Codec=preload('res://scripts/checkpoint_codec.gd')
var checks=[]
var prefix=''
var baseline={}
var events=[]
func _initialize():call_deferred('run')
func check(n,p):
 checks.append({'name':prefix+n,'passed':bool(p)})
 if not p:push_error(prefix+n)
func fresh(a,b):
 var g=load('res://main.tscn').instantiate();g.skirmish_mode='practice';g.history_path='/tmp/readability-owned-'+str(Time.get_ticks_usec())+'.json';root.add_child(g);g.set_process(false);g._test_reset();g.test_mode=false;g.ai_enabled=false
 return g
func publish(g):g._navigation_rebuild();g._update_vision();g._publish_faction_views();g._update_visuals(0)
func site_clear(g,kind,pos):
 var mock={'kind':kind,'pos':g._snap_build_position(kind,pos)}
 for cell in g._occupied_cells(mock):
  if g.navigation.is_point_solid(cell):return false
 return true
func finish(g,key,mode):
 var before=Codec.capture_result(g);g._update_visuals(0);var after=Codec.capture_result(g)
 if not before.ok or not after.ok:print('LIFECYCLE_CAPTURE_FAILURE ',prefix,key,' ',JSON.stringify(before),' ',JSON.stringify(after))
 check(key+' nonempty strict authority',before.ok and after.ok and not before.data.is_empty())
 check(key+' presentation authority unchanged',before.ok and after.ok and before.data==after.data)
 if mode=='reference':baseline[key]=after.data
 else:check(key+' full authority equals identical combined repeat',baseline.has(key) and after.ok and after.data==baseline[key])
func target_loss(mode,a,b):
 var g=fresh(a,b);await process_frame
 # Explicit controlled initial actors only; no subsequent teleport, mask, HP or stocks writes.
 var clear=not g.navigation.is_point_solid(g._cell(Vector3(8,0,-3))) and not g.navigation.is_point_solid(g._cell(Vector3(11.8,0,-3)))
 check('target-loss initial unit cells statically legal',clear)
 if not clear:g.free();await process_frame;return
 var archer=g._spawn('archer',0,Vector3(8,0,-3));var enemy=g._spawn('cavalry',1,Vector3(11.8,0,-3));publish(g)
 check('target initially current visible',g._visible_to(enemy,0))
 g._submit('order',{'ids':[archer.id],'target':enemy.id,'position':enemy.pos},0)
 var released=false
 for i in 50:
  g._process(Rules.TICK)
  if archer.get("last_attack_tick",-1)>=1:released=true;break
 var controller=g.character_presenter.controllers.get(archer.id)
 events.append({'mode':mode,'case':'target loss','phase':'release','tick':g.tick_count,'attack_tick':archer.get('last_attack_tick',-1),'target_hp':enemy.hp})
 check('ordinary explicit attack really releases',released and controller!=null and controller.clip=='attack')
 check('release protection follows B flag',controller!=null and (controller.protected_release_tick>=0)==b)
 var initial=enemy.pos
 g._submit('order',{'ids':[enemy.id],'target':-1,'position':Vector3(30,0,-3)},1)
 var hidden=false;var lost=false;var hidden_tick=-1
 for i in 500:
  g._process(Rules.TICK)
  if not g._visible_to(enemy,0) and not hidden:
   hidden=true;hidden_tick=g.tick_count
   var own=g.faction_views[0].get_record(archer.id)
   check('actual hidden target removes current ready cue',not own.is_empty() and not own.get('visual_attack_ready',false))
   check('hidden target has no active release-age protection',controller!=null and (controller.protected_release_tick<0 or g.tick_count-controller.protected_release_tick>=3))
  if hidden and (archer.target!=enemy.id or archer.state!='attack'):lost=true;break
 events.append({'mode':mode,'case':'target loss','phase':'retired','tick':g.tick_count,'hidden_tick':hidden_tick,'enemy_position':str(enemy.pos),'own_position':str(archer.pos),'own_target':archer.target,'own_state':archer.state,'enemy_hp':enemy.hp})
 check('enemy ordinary move actually travels',enemy.pos.distance_to(initial)>6.0)
 check('target naturally exits player vision',hidden and hidden_tick>0)
 check('game itself retires lost attack target',lost)
 var record=g.faction_views[0].get_record(archer.id)
 check('own record remains current without ready',not record.is_empty() and not record.get('remembered',true) and not record.get('visual_attack_ready',false))
 check('lost target leaves no active protection',controller!=null and controller.protected_release_tick==-1 and controller.preparation_started_tick==-1 and controller.clip!='attack')
 finish(g,'target loss',mode);g.free();await process_frame
func shelter_return(mode,a,b):
 var g=fresh(a,b);await process_frame
 var host_pos=g._snap_build_position('town_center',Vector3(8,0,-3));var wall_pos=g._snap_build_position('house',Vector3(14,0,-3))
 var clear=site_clear(g,'town_center',host_pos) and site_clear(g,'house',wall_pos) and not g.navigation.is_point_solid(g._cell(Vector3(12,0,-3)))
 var host_cells=g._occupied_cells({'kind':'town_center','pos':host_pos});var wall_cells=g._occupied_cells({'kind':'house','pos':wall_pos})
 for cell in wall_cells:
  if cell in host_cells:clear=false
 check('garrison snapped footprints legal against seeded world',clear)
 if not clear:g.free();await process_frame;return
 var host=g._spawn('town_center',0,host_pos);var worker=g._spawn('villager',0,Vector3(12,0,-3));var wall=g._spawn('house',1,wall_pos);publish(g)
 check('garrison exact snapped positions',host.pos==host_pos and wall.pos==wall_pos)
 var worker_clear=not g.navigation.is_point_solid(g._cell(worker.pos))
 check('worker outside all static footprints',worker_clear)
 if not worker_clear:g.free();await process_frame;return
 g._submit('order',{'ids':[worker.id],'target':wall.id,'position':wall.pos},0)
 var released=false
 for i in 60:
  g._process(Rules.TICK)
  if worker.get("last_attack_tick",-1)>=1:released=true;break
 var old=g.character_presenter.controllers.get(worker.id)
 events.append({'mode':mode,'case':'shelter return','phase':'release','tick':g.tick_count,'attack_tick':worker.get('last_attack_tick',-1),'target_hp':wall.hp})
 check('villager ordinary attack really releases',released and old!=null and old.clip=='attack')
 g._submit('garrison',{'ids':[worker.id],'building':host.id},0)
 var inside=false
 for i in 500:
  g._process(Rules.TICK)
  if i==0:
   check('real queued garrison starts pending or enters',worker.has('garrison_pending') or worker.has('garrison_host'))
   check('real pending cancels protected release immediately',old!=null and old.protected_release_tick==-1)
   check('real queued garrison cancels combined protected recovery',old!=null and (old.clip!='attack' if b else old.clip=='attack'))
   events.append({'mode':mode,'case':'shelter return','phase':'pending','tick':g.tick_count,'protected_release_tick':old.protected_release_tick if old!=null else -999,'clip':old.clip if old!=null else 'missing'})
  if worker.has('garrison_host'):inside=true;break
 events.append({'mode':mode,'case':'shelter return','phase':'inside','tick':g.tick_count,'garrison_host':worker.get('garrison_host',-1)})
 check('ordinary garrison enters host',inside and worker.get('garrison_host',-1)==host.id)
 check('garrison removes own current record',g.faction_views[0].get_record(worker.id).is_empty())
 check('garrison reconciles controller away',not g.character_presenter.controllers.has(worker.id))
 check('released old controller clears anchors',old!=null and old.protected_release_tick==-1 and old.preparation_started_tick==-1)
 g._submit('ungarrison',{'building':host.id,'count':1},0);g._process(Rules.TICK)
 events.append({'mode':mode,'case':'shelter return','phase':'exited','tick':g.tick_count,'worker_pos':str(worker.pos),'worker_hp':worker.hp})
 check('ordinary exit restores resident alive',worker.alive and not worker.has('garrison_host'))
 var current=g.character_presenter.controllers.get(worker.id);var record=g.faction_views[0].get_record(worker.id)
 check('new current controller after actual garrison',current!=null and current!=old and not record.is_empty() and not record.get('remembered',true))
 check('replacement binds requested flags',current!=null and current.readable_preparation==a and current.readable_followthrough==b)
 check('no stale attack or hit replay after exit',current!=null and current.protected_release_tick==-1 and current.preparation_started_tick==-1 and current.clip!='attack')
 finish(g,'shelter return',mode);g.free();await process_frame
func run():
 for mode in ['reference','repeat']:
  prefix=mode+' ';await target_loss(mode,true,true);await shelter_return(mode,true,true)
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({'suite':'attack_readability_combined_lifecycle','build':Rules.BUILD_ID,'total':checks.size(),'failed':failed,'checks':checks,'events':events,'scope':'Controlled initial actors and AI disabled; subsequent ordinary attack/move/garrison commands and real ticks. No post-setup HP, resource, terrain, fog, teleport or target-field writes. Not a natural economic match.'}))
 quit(1 if failed else 0)
