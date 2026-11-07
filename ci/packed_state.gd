# Native packed-resource state comparison. Not browser or physical-phone evidence.
extends SceneTree
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.set_process(false)
 for i in 4:await process_frame
 if g.Rules.BUILD_ID!="vc-8fcc302051f0":push_error("Packed build mismatch");quit(1);return
 var font_hash=HashingContext.new();font_hash.start(HashingContext.HASH_SHA256);font_hash.update(g.body_font.data);var font_sha=font_hash.finish().hex_encode()
 if font_sha!="d8dc3f7d8ba62fb1172a6bdd867f8a09e503d3ac5cb349e726491736b5008790":push_error("Packed font bytes mismatch");quit(1);return
 var glyphs=true
 for char in "容拆減量除框選單位取消指令確認建造預覽漿果樹木工人繼續暫停":glyphs=glyphs and g.body_font.has_char(char.unicode_at(0))
 if not glyphs:push_error("Missing packed feature glyph");quit(1);return
 for i in 1200:g._tick(g.Rules.TICK)
 var entities=[]
 for ent in g.entities:
  var item={}
  for key in ent:
   if key not in ["node","body","ring","bar","bar_fill"]:item[key]=ent[key]
  entities.append(item)
 var state={"build":g.Rules.BUILD_ID,"tick":g.tick_count,"stocks":g.stocks.duplicate(true),"delivered":g.delivered_total,"trained":g.trained_total,"completed_builds":g.completed_builds,"population":[g._population(0),g._population(1)],"outcome":g.outcome,"ledger":g.economy.snapshot(),"entities":entities,"processed_ids":g.processed_command_ids,"commands":g.commands,"command_sequence":g.command_sequence,"next_queue_id":g.next_queue_id,"next_id":g.next_id,"audit":g.economy.audit(),"font_sha256":font_sha,"font_glyphs":glyphs}
 if not state.audit.ok or state.tick!=1200:push_error("Packed state failed");quit(1);return
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(state,"  "));print("PACKED_STATE ",g.Rules.BUILD_ID," tick=",g.tick_count," entities=",g.entities.size()," font=",font_sha);g.queue_free();await process_frame;await process_frame;quit()
