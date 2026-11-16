extends RefCounted
## Exact-build local checkpoint transport; never deserializes executable Objects.
## Decoding never enables Godot Object deserialization. Integrity is accidental-
## corruption detection, not authentication or protection from a local cheater.
const TacticalRoute=preload("res://scripts/tactical_route.gd")
const Rules=preload("res://scripts/rules.gd")
const Layout=preload("res://scripts/battlefield_layout.gd")
const MAGIC="VALLEY_CROWN_CHECKPOINT"
const SCHEMA=1
const MAX_BYTES=16*1024*1024
const MAX_DEPTH=32
const MAX_NODES=1000000
const MAX_CONTAINER=100000
const GAME_FIELDS=[
 "age_completed_tick","military_tech_completed","worker_safety_enabled","worker_evacuations","worker_manual_until","worker_safety_hits",
 "next_id","economy_sequence","tick_count","game_time","command_sequence","commands","processed_command_ids",
 "completed_builds","trained_total","next_queue_id","ready_cursor","spawn_commit_order","repeat_train_cursor",
 "path_requests","path_budget_tick","path_expansion_budget","last_path_queries","last_path_expansions","navigation_version",
 "recovery_ticks","no_progress_ticks","progress_serial","future_recovery_events","_surrender_intent",
 "ai_enabled","ai_clock","raid_clock","ai_raids","ai_opening_assigned","ai_last_raid_tick","ai_raid_members",
 "ai_home_defense_targets","ai_raid_departure_count","ai_raid_keep","ai_raid_retreating","ai_scout_attempts","ai_scout_moves",
 "ai_claimed_workers","ai_build_submitted","ai_budget","ai_status","ai_site_recovery","ai_control_targets",
 "layout_id","skirmish_mode","victory_mode","battle_speed","visible_cells","explored_cells","unit_action_cues",
 "selected","groups","camera_focus","camera_zoom","idle_worker_cursor","vacant_farm_cursor","production_cursor","building_attention_cursor",
 "spawn_availability_polls","spawn_candidate_checks","owned_motion_witness_tick"]
const MODULE_FIELDS={
 "economy":["_resource_types","_configuration_valid","_banks","_initial","_stats","_nodes","_workers","_receipts","_transactions","_farms","_worker_farms","_wheelbarrow_completed"],
 "attack_ledger":["_records","_settled_through"],
 "combat_veterancy":["kills","settled_through"],
 "squad_selection":["groups"],
 "battle_alerts":["entries","serial"],
 "match_report":["events","event_serial","omitted_events","trained","completed","unit_losses","building_losses","seen_training","seen_building","seen_loss"],
 "demo_tutorial":["achieved","skipped"],
 "siege_challenge":["wave","active","next_tick","complete"],
 "control_point":["scores","owner","contested","last_tick"]}
const EXPEDITION_FIELDS=["stage","stage_ticks","outpost_id","counter_ids","counter_launched","counter_due","trained","supplied"]
static func module_fields(mode:String)->Dictionary:
 var fields=MODULE_FIELDS.duplicate()
 if mode=="expedition":fields["frontier_expedition"]=EXPEDITION_FIELDS
 return fields

const WORK_FIELDS=["revision","resources","structures","known_obstacles","observed_solids","own_solids","resource_observed_at","obstacle_observed_at","cell_observed_at"]
const FACTION_FIELDS=["memory","current","tick"]
const ENTITY_NODE_FIELDS=["node","body","ring","bar","bar_fill"]
const DATA_KEYS=["build","game","modules","entities","work_memory","faction_views","rng"]

static func failure(reason:String)->Dictionary:return {"ok":false,"reason":reason}
static func copy_fields(object:Object,fields:Array)->Dictionary:
 var result={}
 for key in fields:result[key]=object.get(key)
 return result

static func capture(game:Node)->Dictionary:
 var result=capture_result(game)
 return result.get("data",{})

static func capture_result(game:Node)->Dictionary:
 if game.game_over:return failure("TERMINAL_MATCH")
 # Caller must invoke between _tick calls on the main thread, not from a ledger callback.
 var data={"build":game.Rules.BUILD_ID,"game":copy_fields(game,GAME_FIELDS),"modules":{},"entities":[],"work_memory":[],"faction_views":[],"rng":{"seed":game.rng.seed,"state":game.rng.state}}
 for name in module_fields(game.skirmish_mode):data.modules[name]=copy_fields(game.get(name),module_fields(game.skirmish_mode)[name])
 for entity in game.entities:
  var clean={}
  for key in entity:
   if key not in ENTITY_NODE_FIELDS:clean[key]=entity[key]
  clean.checkpoint_body_rotation=entity.body.rotation
  data.entities.append(clean)
 for memory in game.work_memory:
  var record=copy_fields(memory,WORK_FIELDS)
  var solids:Array[Vector2i]=[]
  var region:Rect2i=memory.grid.region
  if region.size.x<0 or region.size.y<0 or region.size.x>256 or region.size.y>256:return failure("GRID_BOUNDS")
  for y in range(region.position.y,region.end.y):
   for x in range(region.position.x,region.end.x):
    var cell=Vector2i(x,y)
    if memory.grid.is_point_solid(cell):solids.append(cell)
  record.grid_region=region;record.grid_solids=solids
  data.work_memory.append(record)
 for view in game.faction_views:data.faction_views.append(copy_fields(view,FACTION_FIELDS))
 var result=validation_result(data)
 if not result.ok:return result
 # Roundtrip makes a detached value-only copy, including originally read-only views.
 return {"ok":true,"data":bytes_to_var(var_to_bytes(data))}

static func exact_keys(value,keys:Array)->bool:
 if not value is Dictionary or value.size()!=keys.size():return false
 for key in keys:
  if not value.has(key):return false
 return true

static func safe_value(value,depth:int,budget:Array)->bool:
 budget[0]+=1
 if depth>MAX_DEPTH or budget[0]>MAX_NODES:return false
 match typeof(value):
  TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_VECTOR2I,TYPE_VECTOR3I,TYPE_RECT2I:return true
  TYPE_FLOAT:return not is_nan(value) # Infinity is an existing path sentinel.
  TYPE_STRING,TYPE_STRING_NAME:return str(value).length()<=MAX_BYTES
  TYPE_VECTOR2:return not is_nan(value.x) and not is_nan(value.y)
  TYPE_VECTOR3:return not is_nan(value.x) and not is_nan(value.y) and not is_nan(value.z)
  TYPE_COLOR:return not is_nan(value.r) and not is_nan(value.g) and not is_nan(value.b) and not is_nan(value.a)
  TYPE_ARRAY:
   if value.size()>MAX_CONTAINER:return false
   for item in value:
    if not safe_value(item,depth+1,budget):return false
   return true
  TYPE_DICTIONARY:
   if value.size()>MAX_CONTAINER:return false
   for key in value:
    if typeof(key) not in [TYPE_STRING,TYPE_STRING_NAME,TYPE_INT,TYPE_VECTOR2I]:return false
    if not safe_value(key,depth+1,budget) or not safe_value(value[key],depth+1,budget):return false
   return true
  TYPE_PACKED_BYTE_ARRAY:return value.size()<=MAX_BYTES
  TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_STRING_ARRAY,TYPE_PACKED_VECTOR2_ARRAY,TYPE_PACKED_VECTOR3_ARRAY,TYPE_PACKED_COLOR_ARRAY:
   if value.size()>MAX_CONTAINER:return false
   for item in value:
    if not safe_value(item,depth+1,budget):return false
   return true
  _:return false # In particular Object, Callable, Signal, RID and NodePath.

static func finite_position(point:Vector3)->bool:
 return is_finite(point.x) and is_finite(point.y) and is_finite(point.z) and absf(point.x)<=Rules.MAP_HALF and absf(point.z)<=Rules.MAP_HALF and absf(point.y)<=100.0

static func module_types(name:String,record:Dictionary)->bool:
 if name=="frontier_expedition":
  for key in EXPEDITION_FIELDS:
   if key in ["stage_ticks","counter_ids"]:
    if not record[key] is Array:return false
   elif key=="counter_launched":
    if not record[key] is bool:return false
   elif not record[key] is int:return false
  return true
 var arrays={"economy":["_resource_types","_banks","_initial","_stats"],"squad_selection":["groups"],"battle_alerts":["entries"],"match_report":["events"],"siege_challenge":["active"],"control_point":["scores"]}
 var ints={"attack_ledger":["_settled_through"],"combat_veterancy":["settled_through"],"battle_alerts":["serial"],"match_report":["event_serial","omitted_events"],"siege_challenge":["wave","next_tick"],"control_point":["owner","last_tick"]}
 var booleans={"economy":["_configuration_valid"],"demo_tutorial":["skipped"],"siege_challenge":["complete"],"control_point":["contested"]}
 for key in record:
  if name=="attack_ledger" and key=="_records":
   if not record[key] is PackedByteArray:return false
  elif key in arrays.get(name,[]):
   if not record[key] is Array:return false
  elif key in ints.get(name,[]):
   if not record[key] is int:return false
  elif key in booleans.get(name,[]):
   if not record[key] is bool:return false
  elif not record[key] is Dictionary:return false
 return true

static func game_types(record:Dictionary)->bool:
 var integers=["next_id","economy_sequence","tick_count","command_sequence","next_queue_id","ready_cursor","path_budget_tick","path_expansion_budget","last_path_queries","last_path_expansions","navigation_version","no_progress_ticks","progress_serial","ai_raids","ai_last_raid_tick","ai_raid_departure_count","idle_worker_cursor","vacant_farm_cursor","spawn_availability_polls","spawn_candidate_checks","owned_motion_witness_tick"]
 var numbers=["game_time","ai_clock","raid_clock","battle_speed","camera_zoom"]
 var booleans=["worker_safety_enabled","ai_enabled","ai_opening_assigned","ai_raid_retreating","ai_build_submitted"]
 var arrays=["age_completed_tick","military_tech_completed","commands","completed_builds","trained_total","spawn_commit_order","repeat_train_cursor","path_requests","recovery_ticks","future_recovery_events","ai_raid_members","visible_cells","explored_cells","selected","unit_action_cues"]
 for key in record:
  if key in integers:
   if not record[key] is int or absi(record[key])>1000000000:return false
  elif key in numbers:
   if typeof(record[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(record[key])):return false
  elif key in booleans:
   if not record[key] is bool:return false
  elif key in arrays:
   if not record[key] is Array:return false
  elif key in ["layout_id","skirmish_mode","victory_mode"]:
   if not record[key] is String:return false
  elif key=="camera_focus":
   if not record[key] is Vector3 or not finite_position(record[key]):return false
  elif not record[key] is Dictionary:return false
 if record.skirmish_mode not in ["practice","standard","pressure","battle","fortress","survival","expedition"] or record.victory_mode not in ["conquest","control","supply"]:return false
 # Unlike a new-game menu default, a saved unknown layout must never silently
 # fall back to valley. World identity is part of the exact-build authority.
 if Layout.valid(record.layout_id)!=record.layout_id:return false
 if record.layout_id!="valley" and not Layout.supported(record.skirmish_mode,record.victory_mode):return false
 if record.battle_speed not in [0.5,1.0,2.0]:return false
 for key in ["age_completed_tick","military_tech_completed","completed_builds","trained_total","repeat_train_cursor","recovery_ticks"]:
  if record[key].size()!=2:return false
 for item in record.military_tech_completed:
  if not item is Dictionary:return false
 return true

static func validate(data)->bool:
 return validation_result(data).ok

static func validation_result(data)->Dictionary:
 if not safe_value(data,0,[0]):return failure("UNSAFE_OR_OVERSIZED_VALUE")
 if not exact_keys(data,DATA_KEYS):return failure("DATA_KEYS")
 if not data.build is String or data.build.is_empty() or data.build.length()>128:return failure("BUILD")
 if not exact_keys(data.game,GAME_FIELDS):return failure("GAME_KEYS")
 if not game_types(data.game):return failure("GAME_FIELD_TYPES")
 var fields=module_fields(data.game.skirmish_mode)
 if not exact_keys(data.modules,fields.keys()):return failure("MODULE_KEYS")
 for name in fields:
  if not exact_keys(data.modules[name],fields[name]):return failure("MODULE_FIELDS:"+name)
  if not module_types(name,data.modules[name]):return failure("MODULE_FIELD_TYPES:"+name)
 if not exact_keys(data.rng,["seed","state"]) or not data.rng.seed is int or not data.rng.state is int:return failure("RNG")
 if not data.entities is Array or data.entities.size()>10000:return failure("ENTITY_BOUNDS")
 var ids={}
 var by_id={}
 for entity in data.entities:
  if not entity is Dictionary:return failure("ENTITY_TYPE")
  for key in ENTITY_NODE_FIELDS:
   if entity.has(key):return failure("ENTITY_OBJECT_FIELD")
  for key in ["id","kind","team","category","pos","alive","hp","max_hp","built","path","state","mode","checkpoint_body_rotation"]:
   if not entity.has(key):return failure("ENTITY_REQUIRED_FIELD")
  if not entity.id is int or entity.id<0 or ids.has(entity.id):return failure("ENTITY_ID")
  ids[entity.id]=true
  by_id[entity.id]=entity
  if entity.kind not in Rules.UNIT_KINDS+Rules.RESOURCE_KINDS+Rules.FOOTPRINT.keys():return failure("ENTITY_KIND")
  var category="unit" if entity.kind in Rules.UNIT_KINDS else ("resource" if entity.kind in Rules.RESOURCE_KINDS else "building")
  if entity.category!=category or entity.team not in ([-1] if category=="resource" else [0,1]):return failure("ENTITY_KIND_TEAM")
  if not entity.checkpoint_body_rotation is Vector3 or not finite_position(entity.checkpoint_body_rotation):return failure("ENTITY_VISUAL_ROTATION")
  if not entity.kind is String or not entity.team is int or not entity.pos is Vector3 or not entity.path is PackedVector3Array or not entity.alive is bool or not entity.built is bool:return failure("ENTITY_FIELD_TYPE")
  if not finite_position(entity.pos):return failure("ENTITY_POSITION")
  for point in entity.path:
   if not finite_position(point):return failure("ENTITY_PATH_POSITION")
  for key in ["hp","max_hp"]:
   if typeof(entity[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(entity[key])):return failure("ENTITY_HP_TYPE")
  if entity.max_hp!=Rules.HP[entity.kind] or entity.hp>entity.max_hp or (entity.alive and entity.hp<=0):return failure("ENTITY_HP")
  if not TacticalRoute.valid_entity(entity):return failure("ENTITY_TACTICAL_ROUTE")
  if entity.has("escort_target"):
   if not entity.escort_target is int or entity.escort_target<0:return failure("ENTITY_ESCORT_TARGET")
   if not entity.get("escort_next_tick",0) is int or entity.get("escort_next_tick",0)<0:return failure("ENTITY_ESCORT_TICK")
   if entity.has("escort_follow_origin") and (not entity.escort_follow_origin is Vector3 or not finite_position(entity.escort_follow_origin)):return failure("ENTITY_ESCORT_ORIGIN")
  if entity.has("construction_return"):
   var intent=entity.construction_return
   if not exact_keys(intent,["site","resource","type"]):return failure("CONSTRUCTION_RETURN_KEYS")
   if not intent.site is int or intent.site<0 or not intent.resource is int or intent.resource<0 or not intent.type is String or intent.type not in ["food","wood","stone","iron"]:return failure("CONSTRUCTION_RETURN_TYPES")
   if entity.kind!="villager" or entity.team!=0 or not entity.alive or entity.state!="build" or entity.target!=intent.site:return failure("CONSTRUCTION_RETURN_WORKER")
  if not entity.state is String or not entity.mode is String or entity.state.length()>64 or entity.mode.length()>64:return failure("ENTITY_STATE")
 for entity in data.entities:
  if entity.has("construction_return"):
   var site=by_id.get(entity.construction_return.site,{})
   if site.is_empty() or not site.alive or site.category!="building" or site.team!=entity.team:return failure("CONSTRUCTION_RETURN_SITE")
   var resource=by_id.get(entity.construction_return.resource,{})
   var types={"pine":"wood","oak":"wood","berry":"food","farm":"food","stone":"stone","iron":"iron"}
   if resource.is_empty() or types.get(resource.kind,"")!=entity.construction_return.type or (resource.kind=="farm" and resource.team!=entity.team):return failure("CONSTRUCTION_RETURN_RESOURCE")
 if not preload("res://scripts/ai_worker_safety_checkpoint.gd").validate(data):return failure("AI_WORKER_SAFETY_STATE")
 if not preload("res://scripts/garrison_checkpoint.gd").validate(data):return failure("GARRISON_STATE")
 if not preload("res://scripts/supply_station_checkpoint.gd").validate(data):return failure("SUPPLY_STATION_STATE")
 if data.game.skirmish_mode=="expedition" and not expedition_valid(data):return failure("EXPEDITION_STATE")
 var attack=data.modules.attack_ledger
 if attack._records.size()%80!=0:return failure("ATTACK_RECORD_ALIGNMENT")
 var attack_count=attack._records.size()/80
 if attack._settled_through!=attack_count or data.modules.combat_veterancy.settled_through!=attack_count:return failure("ATTACK_SETTLEMENT_BOUNDARY")
 for index in attack_count:
  var offset=index*80
  var release=attack._records.decode_s64(offset)
  var source=attack._records.decode_s64(offset+8);var target=attack._records.decode_s64(offset+16)
  var damage=attack._records.decode_s64(offset+24)
  if release<0 or release>data.game.tick_count or not ids.has(source) or not ids.has(target) or damage<0 or damage>1000000:return failure("ATTACK_RECORD_REFERENCE")
 if not data.work_memory is Array or data.work_memory.size()!=2:return failure("WORK_MEMORY")
 for memory in data.work_memory:
  if not exact_keys(memory,WORK_FIELDS+["grid_region","grid_solids"]):return failure("WORK_FIELDS")
  for key in WORK_FIELDS:
   if key=="revision":
    if not memory[key] is int or memory[key]<0:return failure("WORK_REVISION")
   elif not memory[key] is Dictionary:return failure("WORK_DICTIONARY")
  if not memory.grid_region is Rect2i or not memory.grid_solids is Array:return failure("WORK_GRID")
  var region:Rect2i=memory.grid_region
  if region!=Rect2i(0,0,Rules.MAP_SIZE,Rules.MAP_SIZE):return failure("GRID_REGION")
  if region.size.x<0 or region.size.y<0 or region.size.x>256 or region.size.y>256 or memory.grid_solids.size()>65536:return failure("GRID_BOUNDS")
  var cells={}
  for cell in memory.grid_solids:
   if not cell is Vector2i or not region.has_point(cell) or cells.has(cell):return failure("GRID_CELL")
   cells[cell]=true
 if not data.faction_views is Array or data.faction_views.size()!=2:return failure("FACTION_VIEWS")
 for view in data.faction_views:
  if not exact_keys(view,FACTION_FIELDS):return failure("FACTION_FIELDS")
 if not data.game.tick_count is int or data.game.tick_count<0 or data.game.tick_count>48000:return failure("TICK_BOUNDS")
 for key in ["visible_cells","explored_cells"]:
  if not data.game[key] is Array or data.game[key].size()!=2:return failure("FOG_ARRAY")
  for cells in data.game[key]:
   if not cells is PackedByteArray or cells.size()!=Rules.MAP_SIZE*Rules.MAP_SIZE:return failure("FOG_MASK")
   for cell in cells:
    if cell not in [0,1]:return failure("FOG_BIT")
 if not data.game.next_id is int or data.game.next_id<0:return failure("NEXT_ID")
 for id in ids:
  if id>=data.game.next_id:return failure("NEXT_ID_ORDER")
 return {"ok":true}

static func encode(data,build:String)->Dictionary:
 if build.is_empty() or build.length()>128:return failure("BUILD")
 var result=validation_result(data)
 if not result.ok:return result
 if data.build!=build:return failure("BUILD_MISMATCH")
 var payload=var_to_bytes(data)
 if payload.size()>MAX_BYTES:return failure("PAYLOAD_SIZE")
 var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(payload)
 var envelope={"magic":MAGIC,"schema":SCHEMA,"build":build,"sha256":digest.finish().hex_encode(),"payload":payload}
 var bytes=var_to_bytes(envelope)
 if bytes.size()>MAX_BYTES:return failure("ENVELOPE_SIZE")
 return {"ok":true,"bytes":bytes}

static func decode(bytes:PackedByteArray,expected_build:String)->Dictionary:
 if bytes.size()<64 or bytes.size()>MAX_BYTES:return failure("ENVELOPE_SIZE")
 var envelope=bytes_to_var(bytes)
 if not exact_keys(envelope,["magic","schema","build","sha256","payload"]):return failure("ENVELOPE_KEYS")
 if envelope.magic!=MAGIC or envelope.schema!=SCHEMA:return failure("MAGIC_OR_SCHEMA")
 if not envelope.build is String or envelope.build.is_empty() or envelope.build.length()>128:return failure("BUILD")
 if envelope.build!=expected_build or expected_build.is_empty():return {"ok":false,"reason":"BUILD_MISMATCH","source_build":envelope.build,"expected_build":expected_build}
 if not envelope.payload is PackedByteArray or envelope.payload.is_empty() or envelope.payload.size()>MAX_BYTES or not envelope.sha256 is String:return failure("PAYLOAD_TYPE")
 var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(envelope.payload)
 if digest.finish().hex_encode()!=envelope.sha256:return failure("CHECKSUM")
 var data=bytes_to_var(envelope.payload)
 var result=validation_result(data)
 if not result.ok:return result
 if data.build!=expected_build:return failure("BUILD_MISMATCH")
 return {"ok":true,"data":data}

static func expedition_valid(data:Dictionary)->bool:
 var m=data.modules.frontier_expedition
 if data.game.victory_mode!="conquest" or m.stage<0 or m.stage>4:return false
 if m.trained<0 or m.trained>100000 or m.supplied<0 or m.supplied>1000000000:return false
 if m.stage_ticks.size()!=m.stage:return false
 var previous=-1
 for tick in m.stage_ticks:
  if not tick is int or tick<0 or tick<=previous or tick>data.game.tick_count:return false
  previous=tick
 var entities={}
 for e in data.entities:entities[e.id]=e
 if not entities.has(m.outpost_id):return false
 var post=entities[m.outpost_id]
 if post.kind!="tower" or post.team!=1 or (m.stage>=3 and post.alive):return false
 if m.stage<3:
  if m.counter_due!=-1 or m.counter_launched or not m.counter_ids.is_empty():return false
 else:
  if m.counter_due!=m.stage_ticks[2]+600:return false
  if m.stage==4 and not m.counter_launched:return false
 if m.counter_launched:
  if m.stage<3 or m.counter_ids.size()!=6 or data.game.tick_count<m.counter_due:return false
  var unique={}
  var roster=preload("res://scripts/frontier_expedition.gd").COUNTER_ROSTER
  for i in 6:
   var id=m.counter_ids[i]
   if not id is int or unique.has(id) or not entities.has(id):return false
   unique[id]=true
   var e=entities[id]
   if e.team!=1 or e.kind!=roster[i] or (m.stage==4 and e.alive):return false
 elif not m.counter_ids.is_empty():return false
 return true
