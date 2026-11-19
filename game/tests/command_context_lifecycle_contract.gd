extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 for stage in ["queued", "connected"]:
  var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true
  var identity=[g._first(0,"town_center").id]
  g.action_selection_ids=identity.duplicate();g.action_reveal_ids=identity.duplicate()
  if stage=="queued":g.call_deferred("_reveal_context_primary",identity)
  else:g._reveal_context_primary(identity)
  var ref=weakref(g);g.free()
  await process_frame;await process_frame
  check(stage+" owner free cancels pending reveal without coroutine",ref.get_ref()==null)
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame;await process_frame
 var identity=[g._first(0,"town_center").id]
 g.action_selection_ids=identity.duplicate();g.action_reveal_ids=identity.duplicate();g._reveal_context_primary(identity)
 g.action_reveal_ids=[]
 await process_frame;await process_frame
 check("cancel before layout leaves pending reveal empty",g.action_reveal_ids.is_empty())
 g.action_selection_ids=identity.duplicate();g.action_reveal_ids=identity.duplicate();g._reveal_context_primary(identity)
 g._select([g._first(0,"villager").id])
 await process_frame;await process_frame
 check("replacement context invalidates old scheduled identity",g.action_selection_ids!=identity and g.action_reveal_ids.is_empty())
 g._select([g._first(0,"town_center").id]);g._update_hud()
 var home_identity=g.action_selection_ids.duplicate()
 g._select([g._first(0,"villager").id]);g._update_hud()
 g._select(home_identity);g._update_hud()
 await process_frame;await process_frame;await process_frame
 check("same-frame repeated producer identity shares owned connection",g.action_selection_ids==home_identity and g.action_reveal_ids.is_empty())
 g.free();await process_frame
 for variant in ["detached_schedule","connected_detach","queued_free","same_frame_reattach","later_reattach"]:
  var h=load("res://main.tscn").instantiate();h.skirmish_mode="practice";root.add_child(h);h.set_process(false);h.test_mode=true
  await process_frame;await process_frame
  var ids=[h._first(0,"town_center").id];h.action_selection_ids=ids.duplicate();h.action_reveal_ids=ids.duplicate()
  var generation=h.action_reveal_generation
  if variant=="queued_free":
   h._reveal_context_primary(ids);h.queue_free()
   var ref=weakref(h);await process_frame;await process_frame
   check("queued deletion cannot run reveal callback",ref.get_ref()==null)
   continue
  if variant!="detached_schedule":h._reveal_context_primary(ids,generation)
  h.call_deferred("_reveal_context_primary",ids,generation)
  var old_receivers=h.action_reveal_receivers.duplicate()
  root.remove_child(h)
  var disconnected=true
  for receiver in old_receivers:
   if process_frame.is_connected(receiver):disconnected=false
  check(variant+" tree exit disconnects owned signals immediately",disconnected and h.action_reveal_receivers.is_empty())
  if variant=="detached_schedule":h._reveal_context_primary(ids,generation)
  if variant=="same_frame_reattach":
   root.add_child(h)
   h.action_reveal_ids=ids.duplicate() # New intent: an old callback must not consume it.
  await process_frame;await process_frame
  var expected_pending=ids if variant=="same_frame_reattach" else []
  check(variant+" invalidates old frame lifetime",h.action_reveal_ids==expected_pending and h.action_reveal_generation>generation)
  if variant=="later_reattach":
   root.add_child(h);await process_frame;await process_frame
   check("reattach after detached callback does not replay pending reveal",h.action_reveal_ids.is_empty())
  h.free();await process_frame
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"command_context_lifecycle_contract","checks":checks,"failed":failed,"scope":"Owned one-shot frame receiver disposal and cancellation; engine errors remain guard failures"}));quit(1 if failed else 0)
