extends SceneTree
## Private transport/shape tests only. Not restore or persistent-save acceptance.
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 var data=Codec.capture(g)
 check("ordinary match produces valid detached data checkpoint",not data.is_empty() and Codec.validate(data))
 if data.is_empty():g.free();finish();return
 var original_hp=g.entities[0].hp
 var detached=Codec.capture(g)
 detached.entities[0].hp-=1;detached.game.commands.append({"test_marker":1})
 check("captured entity and command containers cannot mutate live game",g.entities[0].hp==original_hp and g.commands.is_empty())
 var encoded=Codec.encode(data,g.Rules.BUILD_ID)
 check("valid checkpoint encodes bounded data envelope",encoded.ok and encoded.get("bytes",PackedByteArray()).size()<=Codec.MAX_BYTES)
 if not encoded.ok:g.free();finish();return
 var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID)
 check("data only roundtrip preserves exact snapshot",decoded.ok and decoded.data==data)
 check("wrong runtime build is rejected",not Codec.decode(encoded.bytes,"different-build").ok)
 var envelope=bytes_to_var(encoded.bytes)
 envelope.payload[envelope.payload.size()-1]^=1
 check("changed payload fails checksum",Codec.decode(var_to_bytes(envelope),g.Rules.BUILD_ID).get("reason")=="CHECKSUM")
 check("truncated envelope is rejected",not Codec.decode(encoded.bytes.slice(0,12),g.Rules.BUILD_ID).ok)
 var altered=data.duplicate(true);altered.game.commands.append({"unsafe":g})
 check("object payload cannot be encoded",not Codec.encode(altered,g.Rules.BUILD_ID).ok)
 altered=data.duplicate(true);altered.game.commands.append({"unsafe":func():return 1})
 check("callable payload cannot be encoded",not Codec.encode(altered,g.Rules.BUILD_ID).ok)
 altered=data.duplicate(true);altered.entities.append(altered.entities[0].duplicate(true))
 check("duplicate entity identity is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.entities[0].kind="unknown_unit"
 check("unknown entity kind is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.entities[0].team=7
 check("invalid entity team is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.game.visible_cells[0]=PackedByteArray([0])
 check("wrong sized visibility mask is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.game.explored_cells[1][0]=2
 check("non binary explored mask is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.game.tick_count="150"
 check("string tick cannot replace integer clock",not Codec.validate(altered))
 altered=data.duplicate(true);altered.work_memory[0].grid_region=Rect2i(0,0,81,80)
 check("wrong map region is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.modules.attack_ledger._records="bytes"
 check("attack ledger storage must retain packed byte type",not Codec.validate(altered))
 altered=data.duplicate(true);altered.modules.attack_ledger._records=PackedByteArray([1])
 check("misaligned attack record is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.modules.attack_ledger._settled_through=1
 check("unsettled or impossible attack cursor is rejected",not Codec.validate(altered))
 altered=data.duplicate(true);altered.entities[0].checkpoint_body_rotation="rotation"
 check("invalid saved visual rotation is rejected",not Codec.validate(altered))
 g.free();finish()
func finish():
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"checkpoint_codec_contract","checks":checks,"failed":failed,"scope":"Private data-only snapshot transport and structural rejection; no restore, disk, browser durability or full semantic validation claim"}))
 quit(0 if failed==0 else 1)
