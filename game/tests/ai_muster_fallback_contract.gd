extends SceneTree
const Plan=preload('res://scripts/ai_muster_fallback.gd')
const Codec=preload('res://scripts/checkpoint_codec.gd')
const Restore=preload('res://scripts/checkpoint_restore.gd')
var checks=[]
func c(n,v):checks.append({'name':n,'passed':bool(v)})
func records():
 var result=[]
 for pair in [[1,'spearman'],[2,'archer']]:result.append({'id':pair[0],'kind':pair[1],'category':'unit','owned':true,'alive':true,'team':1,'remembered':false,'state':'idle'})
 for pair in [[10,'barracks'],[11,'range'],[12,'stable'],[13,'workshop']]:result.append({'id':pair[0],'kind':pair[1],'category':'building','owned':true,'alive':true,'built':true,'team':1,'remembered':false,'queue':[]})
 return result
func _initialize():call_deferred('run')
func fresh():
 var g=load('res://main.tscn').instantiate();g.skirmish_mode='standard';root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;return g
func run():
 var rs=records();var budget={'food':309270,'wood':56880,'iron':43720,'stone':15420};var before=rs.duplicate(true);var saved_budget=budget.duplicate()
 var p=Plan.plan(rs,budget,true,20,8,5)
 c('full affordable gap uses existing composition and exact prices',not p.is_empty() and p.sequence==['cavalry','spearman','spearman'] and p.remaining=={'food':119270,'wood':16880,'iron':8720,'stone':15420})
 c('pure forecast preserves observations queues and budget',rs==before and budget==saved_budget)
 c('empty legal producer set never defaults to free spearman',Plan.plan(rs.slice(0,2),budget,true,20,8,5).is_empty())
 c('full gap population reserves every future birth',Plan.plan(rs,budget,true,10,8,5).is_empty())
 var poor=budget.duplicate();poor.food=200000
 c('affordable first unit but unaffordable full gap refuses',Plan.plan(rs,poor,true,20,8,5).is_empty())
 var exact=budget.duplicate();exact.food=290000
 c('exact two villager food reserve is accepted',not Plan.plan(rs,exact,true,20,8,5).is_empty())
 exact.food-=1
 c('one milli below full gap food reserve refuses',Plan.plan(rs,exact,true,20,8,5).is_empty())
 var four=rs.duplicate(true)
 four.append({'id':3,'kind':'scout','category':'unit','owned':true,'alive':true,'team':1,'remembered':false,'state':'move'})
 four.append({'id':4,'kind':'spearman','category':'unit','owned':true,'alive':true,'team':1,'remembered':false,'state':'attack'})
 c('moving scout and attacking soldier count toward army cap',Plan.plan(four,budget,true,20,10,5).get('gap',0)==1)
 four.append({'id':5,'kind':'archer','category':'unit','owned':true,'alive':true,'team':1,'remembered':false})
 c('five living troops prevent further fallback',Plan.plan(four,budget,true,20,11,5).is_empty())
 var queued=rs.duplicate(true);queued[2].queue.append({'kind':'spearman'})
 c('already paid military queue is not purchased again',Plan.plan(queued,budget,true,20,9,5).is_empty())
 queued=rs.duplicate(true);queued[2].queue.append({'kind':'villager'})
 c('existing worker birth retains priority',Plan.plan(queued,budget,true,20,9,5).is_empty())
 for flag in ['alive','built','owned']:
  var bad=rs.duplicate(true)
  for r in bad:
   if r.category=='building':r[flag]=false
  c('producer '+flag+' required',Plan.plan(bad,budget,true,20,8,5).is_empty())
 var locked=rs.slice(0,2)+[rs[4].duplicate(true)]
 c('locked cavalry cannot pass age gate',Plan.plan(locked,budget,false,20,8,5).is_empty())
 var full=rs.duplicate(true)
 for r in full:
  if r.category=='building':r.queue=[{'kind':'age2'},{'kind':'age2'},{'kind':'age2'},{'kind':'age2'},{'kind':'age2'}]
 c('full producer queues forbid virtual training',Plan.plan(full,budget,true,20,8,5).is_empty())
 var hidden=rs.duplicate(true);hidden.append({'id':500,'team':0,'owned':false,'alive':true,'remembered':true,'category':'unit','kind':'siege'})
 c('remembered enemy cannot alter composition forecast',Plan.plan(hidden,budget,true,20,8,5)==p)
 # Explicit initial fixture, not a natural match: normal initial ledger stocks,
 # completed structures/three troops, then real farm assignments and paid birth.
 var g=fresh();await process_frame
 g._test_reset([{'food':150,'wood':200,'stone':100,'iron':0},{'food':200,'wood':56,'stone':100,'iron':0}]);g.ai_enabled=false
 var farm1=g._spawn('farm',1,Vector3(29,0,-13));var farm2=g._spawn('farm',1,Vector3(34,0,-13))
 g._spawn('barracks',1,Vector3(31,0,-20));g._spawn('house',1,Vector3(25,0,-32));g._spawn('house',1,Vector3(30,0,-32))
 for i in 3:g._spawn('spearman',1,Vector3(24+i,0,-28))
 var workers=[]
 for e in g.entities:
  if e.alive and e.team==1 and e.kind=='villager':workers.append(e)
 g._order(workers[0],'gather',farm1.id);g._order(workers[1],'gather',farm2.id)
 g._update_vision();g.ai_enabled=true;g.ai_budget=g.economy.bank_milli(1).duplicate();g.ai_status={}
 var view=g._ai_records();view.append({'id':9999,'team':0,'kind':'town_center','category':'building','owned':false,'alive':true,'remembered':true})
 var bank=g.economy.bank_milli(1).duplicate();var reserve=g.ai_budget.duplicate();var count=g._count(1,'spearman')
 c('controlled fixture has four troops and farm assignments',count==3 and g._count(1,'scout')==1 and workers[0].farm_id==farm1.id and workers[1].farm_id==farm2.id)
 c('other primary goal never diverted',not g._ai_optional_farm_muster('house',view,20,10))
 g.ai_budget.wood=60000;c('affordable farm always retains priority',not g._ai_optional_farm_muster('farm',view,20,10));g.ai_budget=reserve.duplicate()
 g.ai_enabled=false;c('disabled AI cannot use fallback',not g._ai_optional_farm_muster('farm',view,20,10));g.ai_enabled=true
 g.paused=true;c('paused game cannot use fallback',not g._ai_optional_farm_muster('farm',view,20,10));g.paused=false
 g.skirmish_mode='practice';c('practice does not buy offensive muster',not g._ai_optional_farm_muster('farm',view,20,10));g.skirmish_mode='standard'
 workers[0].path_status='NO_PATH';c('terminal food worker is not operating floor',not g._ai_optional_farm_muster('farm',view,20,10));workers[0].path_status='IDLE'
 g.commands.append({'team':1,'type':'build','builder':workers[2].id});c('pending own economic commitment blocks fallback',not g._ai_optional_farm_muster('farm',view,20,10));g.commands.clear()
 g.commands.append({'team':1,'type':'military_research','building':0,'kind':'forged_blades'});c('pending military research cannot spend forecast reserve twice',not g._ai_optional_farm_muster('farm',view,20,10));g.commands.clear()
 c('negative guards neither pay nor reserve',g.commands.is_empty() and g.economy.bank_milli(1)==bank and g.ai_budget==reserve)
 c('eligible fallback submits one ordinary train',g._ai_optional_farm_muster('farm',view,20,10) and g.commands.size()==1 and g.commands[0].type=='train' and g.commands[0].kind=='spearman')
 c('forecast did not debit bank before execution',g.economy.bank_milli(1)==bank and g.ai_budget.food==reserve.food-50000 and g.ai_budget.wood==reserve.wood-20000)
 c('pending same birth is not double counted or duplicated',not g._ai_optional_farm_muster('farm',view,20,10) and g.commands.size()==1)
 var capture=Codec.capture_result(g);var encoded=Codec.encode(capture.data,g.Rules.BUILD_ID) if capture.ok else {'ok':false};var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID) if encoded.ok else {'ok':false}
 c('ordinary pending train strict same build transport',capture.ok and encoded.ok and decoded.ok)
 if not decoded.ok:print('CAPTURE_FAILURE '+str(capture));finish(g);return
 var clone=fresh();var restored=Restore.apply(clone,decoded.data);c('pending train restores without custom schema',restored and clone.commands==g.commands)
 if not restored:clone.free();finish(g);return
 clone._toggle_pause();g.ai_enabled=false;clone.ai_enabled=false
 var paid_before=g.economy.stats_view(1).purchased.duplicate()
 for i in 100:g._tick(g.Rules.TICK);clone._tick(clone.Rules.TICK)
 var a=Codec.capture_result(g);var b=Codec.capture_result(clone)
 c('restored normal execution preserves full authority',a.ok and b.ok and a.data==b.data)
 var paid=g.economy.stats_view(1).purchased
 c('real queue paid exact normal spear cost once',paid.food-paid_before.food==50000 and paid.wood-paid_before.wood==20000)
 for i in 500:
  g._tick(g.Rules.TICK)
  if g._count(1,'spearman')>count:break
 c('ordinary training ticks produce exactly one real troop',g._count(1,'spearman')==count+1)
 c('normal payment and farm ledgers remain conserved',g.economy.audit().ok)
 clone.free();finish(g)
func finish(g):
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({'suite':'ai_muster_fallback_contract','checks':checks,'failed':failed,'scope':'Pure full-gap planning negatives; controlled initial farm/army fixture with ordinary paid training and strict restore, not natural military or economy success'}));g.free();quit(1 if failed else 0)
