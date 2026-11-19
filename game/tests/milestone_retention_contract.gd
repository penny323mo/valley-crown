extends SceneTree
const M=preload("res://scripts/match_report.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func _initialize():call_deferred("run")
func ck(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func kinds():
 return {"house":{"id":90,"category":"building","kind":"house","team":0,"built":true,"alive":true},"worker":{"id":91,"category":"unit","kind":"villager","team":0,"alive":true},"pike":{"id":92,"category":"unit","kind":"spearman","team":0,"alive":true},"ram":{"id":93,"category":"unit","kind":"siege","team":0,"alive":true},"enemy":{"id":94,"category":"unit","kind":"archer","team":1,"alive":true}}
func populate(m):
 var k=kinds()
 m.record_training(k.worker,20)
 m.record_completion(k.house,40)
 m.record_training(k.pike,60)
 m.record_visible_contact(k.enemy,4.0,true,80)
 m.record_training(k.ram,100)
 for i in 90:
  var u=k.pike.duplicate();u.id=100+i
  m.record_training(u,i+110)
func run():
 var k=kinds();var m=M.new()
 ck("enemy hidden hit does not become first combat",not m.record_visible_contact(k.enemy,4.0,false,5) and m.events.is_empty())
 ck("zero friendly dead and invalid timestamp never credited",not m.record_visible_contact(k.enemy,0.0,true,20) and not m.record_visible_contact(k.pike,4.0,true,20) and not m.record_visible_contact({"team":1,"alive":false,"kind":"archer"},4.0,true,20) and not m.record_visible_contact(k.enemy,4.0,true,0))
 populate(m)
 ck("exact bounded ring and omissions still reconcile",m.events.size()==64 and m.omitted_events==31 and m.event_serial==95 and m.trained.spearman==91)
 var verify=M._milestone_indices(m.events)
 ck("early build first troop combat and siege survive rollover",verify.size()==4 and m.events[verify.construction].tick==40 and m.events[verify.troop].tick==60 and m.events[verify.combat].tick==80 and m.events[verify.siege].tick==100)
 ck("already settled first contact cannot enter a second time",not m.record_visible_contact(k.enemy,5.0,true,210) and m.event_serial==95)
 var r=m.make_report("victory","castle",400,90,{},{});r.skirmish_mode="standard"
 var text=M.page_text(r,"overview")
 var labels=["00:02 · 首次完工","00:03 · 首次出兵","00:04 · 首次擊中敵方目標","00:04 · 完成研究","00:05 · 首次攻城車出兵","00:20 · 勝利"]
 var at=-1;var ordered=true
 for label in labels:
  var pos=text.find(label)
  if pos<=at:ordered=false
  at=pos
 ck("default overview keeps order through real result",ordered)
 ck("recent twelve retained with original totals",text.contains("較早 84 項未列出") and text.contains("訓練完成　93 個單位"))
 ck("other report pages do not claim progression rows",not M.page_text(r,"units").contains("本局階段紀錄"))
 r.skirmish_mode="breach";r.age_tick=0
 text=M.page_text(r,"overview")
 ck("seeded age is not a fabricated earned milestone",not text.contains("完成研究") and not text.contains("00:00  研究") and text.contains("開局已有"))
 var lone=M.new();lone.record_training(k.ram,80)
 r=lone.make_report("draw","time",100,-1,{},{});text=M.page_text(r,"overview")
 ck("first siege that is also first soldier shows one row",text.contains("00:04 · 首次出兵 · 攻城車") and not text.contains("首次攻城車出兵") and text.contains("00:05 · 和局"))
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 for i in 210:g._tick(g.Rules.TICK)
 # Controlled observer data only, all tick offsets within this real save.
 # Natural construction, attack, and finish are validated by a separate journey.
 populate(g.match_report)
 var packed=Codec.capture_result(g)
 ck("strict codec captures unchanged observer shape",packed.ok and packed.data.modules.match_report.keys().size()==10)
 if packed.ok:
  var staged=packed.data
  var encoded=Codec.encode(staged,g.Rules.BUILD_ID)
  var decoded=Codec.decode(encoded.get("bytes",PackedByteArray()),g.Rules.BUILD_ID)
  ck("same-build checkpoint transport retains exact milestone rows",encoded.ok and decoded.ok and decoded.data.modules.match_report.events==staged.modules.match_report.events)
  var h=load("res://main.tscn").instantiate();h.skirmish_mode="practice";root.add_child(h);h.set_process(false);h.test_mode=true;await process_frame
  var restored=Restore.apply(h,staged)
  ck("same-build restore accepted and state remains identical",restored and Codec.capture(h)==staged)
  ck("restored first combat derives cache without inventing another",restored and not h.match_report.record_visible_contact(k.enemy,4.0,true,h.tick_count) and h.match_report.events==staged.modules.match_report.events)
  h.free()
  var invalid=staged.duplicate(true);invalid.modules.match_report.events[0].tick=999999
  ck("future allegedly factual milestone rejected",not Codec.validate(invalid))
  invalid=staged.duplicate(true);invalid.modules.match_report.events[0].action="invented"
  ck("unsupported action rejected inside same old keys",not Codec.validate(invalid))
  invalid=staged.duplicate(true);invalid.modules.match_report.events[1].sequence=invalid.modules.match_report.events[0].sequence
  ck("duplicate sequence rejected inside same old keys",not Codec.validate(invalid))
 g.free()
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"milestone_retention_contract","scope":"Controlled bounded factual observer and exact same-build checkpoint, not a natural full match or iPhone test.","checks":checks,"failed":failed}))
 quit(0 if failed==0 else 1)
