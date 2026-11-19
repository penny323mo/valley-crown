extends RefCounted
## Separate exact-build local slot. Never replaces the manual slot.
const Store=preload("res://scripts/checkpoint_store.gd")
const PATH="user://battle_auto_checkpoint_v1.bin"
static func supported(game:Node)->bool:
 if not is_instance_valid(game):return false
 var chapter=game.get("campaign_chapter")
 return (not chapter is int or chapter<0) and game.skirmish_mode not in ["escort","expedition","breach","depot"] and not game.game_over
static func read_slot(build:String,path:String=PATH)->Dictionary:
 var result=Store.read_slot(build,path)
 if result.ok and result.data.game.skirmish_mode in ["escort","expedition","breach","depot"]:return {"ok":false,"reason":"WRONG_SLOT"}
 return result
static func save_slot(game:Node,path:String=PATH)->Dictionary:
 if not supported(game):return {"ok":false,"reason":"UNSUPPORTED_MATCH"}
 return Store.save_slot(game,path)
