extends RefCounted
## Restore only into a fresh disposable game, never the current session.
const Codec=preload("res://scripts/checkpoint_codec.gd")
static func apply(g,data:Dictionary)->bool:
 if not Codec.validate(data) or data.build!=g.Rules.BUILD_ID:return false
 data=bytes_to_var(var_to_bytes(data))
 for e in data.entities:
  if e.kind not in g.Rules.UNIT_KINDS+g.Rules.RESOURCE_KINDS+g.Rules.FOOTPRINT.keys():return false
  if e.team not in [-1,0,1]:return false
 g.set_process(false);g._cancel_mode();g._cancel_pointer_streams()
 g._test_reset()
 for proxy in g.presentation_nodes.values():proxy.node.free()
 g.presentation_nodes.clear();g.character_presenter.clear();g.building_damage_presenter.clear();g._clear_attack_effects()
 for e in g.entities:e.node.free()
 g.entities.clear();g.economy=g.Economy.new();g._reset_economy(g.INITIAL_STOCKS)
 for saved in data.entities:
  g.next_id=saved.id
  var e=g._spawn(saved.kind,saved.team,saved.pos,saved.built)
  for key in saved:
   if key!="checkpoint_body_rotation":e[key]=bytes_to_var(var_to_bytes(saved[key]))
  e.body.rotation=saved.checkpoint_body_rotation
  e.node.position=e.pos;e.node.visible=e.alive
 g._navigation_rebuild()
 for saved in data.entities:
  var e=g._get_entity(saved.id)
  for key in saved:
   if key!="checkpoint_body_rotation":e[key]=bytes_to_var(var_to_bytes(saved[key]))
  e.body.rotation=saved.checkpoint_body_rotation
 for key in Codec.GAME_FIELDS:g.set(key,data.game[key])
 for name in Codec.module_fields(data.game.skirmish_mode):
  var object=g.get(name)
  for key in Codec.module_fields(data.game.skirmish_mode)[name]:object.set(key,data.modules[name][key])
 for team in 2:
  var memory=g.work_memory[team];var saved=data.work_memory[team]
  for key in Codec.WORK_FIELDS:memory.set(key,saved[key])
  memory.grid.clear();memory.grid.region=saved.grid_region;memory.grid.update()
  for cell in saved.grid_solids:memory.grid.set_point_solid(cell)
  for key in Codec.FACTION_FIELDS:
   var value=data.faction_views[team][key]
   if key in ["memory","current"]:
    var restored={}
    for id in value:restored[id]=g.FactionView.freeze(value[id])
    if key=="current":restored.make_read_only()
    value=restored
   g.faction_views[team].set(key,value)
 g.rng.seed=data.rng.seed;g.rng.state=data.rng.state
 g.large_route_cache=[{},{}];g.pending_damage.clear();g.traffic_priority_order.clear();g.traffic_tick_segments.clear()
 g.paused=true;g.tick_accumulator=0;g.game_over=false;g.outcome="";g.end_reason=""
 g._camera_update()
 return true
