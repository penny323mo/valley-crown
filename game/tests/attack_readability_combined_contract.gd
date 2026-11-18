extends SceneTree
const C=preload('res://scripts/action_character.gd')
var checks=[]
var test_kind="spearman"
func _initialize():call_deferred('run')
func check(n,p):checks.append({'name':test_kind+' '+n,'passed':bool(p)});if not p:push_error(n)
func rec(t,atk=-1,hit=-1,ready=false):
 return {'id':97,'kind':test_kind,'owned':true,'alive':true,'remembered':false,'last_seen_tick':t,'pos':Vector3.ZERO,'visual_action':'idle','visual_moving':false,'visual_attack_tick':atk,'visual_hit_tick':hit,'visual_attack_ready':ready,'visual_anticipation':.5,'state':'attack','mode':'ATTACK','target':101,'work_epoch':3}
func make():
 var body=Node3D.new();root.add_child(body);var c=C.new()
 check('bind '+str(checks.size()),c.bind(body,test_kind,Color.WHITE));c.observe(rec(0),0,true);return c
func free_c(c):var body=c.body;c.release();body.free()
func cases():
 for mode in ['AB']:
  var a=mode in ['A','AB'];var b=mode in ['B','AB'];var c=make()
  c.observe(rec(1,-1,1),.05,true);c.observe(rec(2,-1,2,true),.05,true);c.observe(rec(3,-1,3,true),.05,true)
  check(mode+' first two preparation ticks still hit',c.clip=='hit')
  c.observe(rec(4,-1,4,true),.05,true)
  check(mode+' dense hit preparation cap',c.clip==('attack' if a else 'hit'))
  c.observe(rec(5,5,5),0,true)
  check(mode+' same tick release always wins',c.clip=='attack' and c.last_attack_tick==5 and c.last_hit_tick==5)
  c.observe(rec(6,5,6),.05,true)
  check(mode+' next tick release window',c.clip==('attack' if b else 'hit') and c.last_hit_tick==6)
  c.observe(rec(7,5,7),.05,true)
  check(mode+' second tick release window',c.clip==('attack' if b else 'hit'))
  c.observe(rec(8,5,8),.05,true)
  check(mode+' age three hit interrupts',c.clip=='hit' and c.last_hit_tick==8)
  free_c(c)
 for change in ['target','epoch','STOP','MOVE','lost','moving','garrison','pause_STOP','pause_MOVE','pause_same','reset']:
  var c=make();c.observe(rec(1,1,1),.05,true);var r=rec(2,1,1)
  if change.begins_with('pause'):c.observe(rec(1,1,1),.05,false)
  if change=='target':r.target=102
  if change=='epoch':r.work_epoch=4
  if change in ['STOP','pause_STOP']:r.mode='STOP';r.state='idle';r.target=-1
  if change in ['MOVE','pause_MOVE']:r.mode='MOVE';r.state='move';r.target=-1
  if change=='lost':r.target=-1
  if change=='moving':r.visual_moving=true
  if change=='garrison':r.garrison_pending=2
  if change=='reset':r.last_seen_tick=20
  var original=r.duplicate(true);c.observe(r,.05,true)
  check(change+' protected release cleared',c.protected_release_tick==-1)
  check(change+' old attack not retained',c.clip!='attack')
  check(change+' observation unchanged',r==original)
  free_c(c)
 for mode in ['AB']:
  var c=make();c.observe(rec(1,1,1),0,true);var t=c.playhead
  c.observe(rec(1,1,1),0,true)
  check(mode+' same tick no replay',c.playhead==t and c.protected_release_tick==(1 if mode in ['B','AB'] else -1))
  c.start_death();c.observe(rec(2,2,2),.05,true)
  check(mode+' death wins',c.dead and c.clip=='death');free_c(c)
 var c=make();var enemy=rec(1,1,1);enemy.owned=false;c.observe(enemy,0,true);enemy=rec(2,1,2);enemy.owned=false;c.observe(enemy,.05,true)
 check('enemy remains original hit priority',c.clip=='hit' and c.protected_release_tick==-1);free_c(c)
 c=make();var adv=rec(1,1,1);adv.mode='ADVANCE';c.observe(adv,0,true);adv=rec(2,1,2);adv.mode='ADVANCE';c.observe(adv,.05,true)
 check('nonexplicit attack remains baseline',c.clip=='hit');free_c(c)
 c=make();c.observe(rec(1,1,1),.05,true);c.observe(rec(2,1,2),.05,true);c.observe(rec(4,1,2),.05,true)
 check('expired protection never replays consumed hit',c.clip=='attack' and c.last_hit_tick==2);free_c(c)
 c=make();c.observe(rec(1,-1,1),.05,true);c.observe(rec(2,-1,1,true),.05,true);c.observe(rec(3,-1,1,true),.05,true);c.observe(rec(4,-1,4,false),.05,true)
 check('cancelled ready restores new hit priority',c.clip=='hit' and c.preparation_started_tick==-1);free_c(c)
func run():
 for kind in ['spearman','archer']:
  test_kind=kind;cases()
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({'suite':'attack_readability_combined_contract','total':checks.size(),'failed':failed,'checks':checks,'scope':'Combined owned explicit attack controller fixtures. Not natural gameplay or phone proof.'}))
 quit(1 if failed else 0)
