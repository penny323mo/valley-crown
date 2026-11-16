extends SceneTree
## ENGINE_UNRUN. Synthetic actors, observer withdrawal and unseen-death setup;
## actual visibility, known-grid update, bounded search, movement and attack ledger.
## No full match, rendered pixels or device input has run for this fixture.
const Game=preload("res://scripts/game.gd")
const Rules=preload("res://scripts/rules.gd")
class Fixture:
	extends Game
	func _note_unit_action(_ent: Dictionary,_action: String,_point: Vector3=Vector3.INF) -> void: pass
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func unit(id,team,kind,p):
	return {"id":id,"team":team,"category":"unit","kind":kind,"alive":true,"built":true,
		"pos":p,"anchor":p,"dest":p,"radius":Rules.UNIT_RADII[kind],"body":Node3D.new(),
		"state":"idle","mode":"STOP","target":-1,"auto_target":false,"last_known":p,
		"path":PackedVector3Array(),"path_version":-1,"cooldown_ticks":0,"stuck":0,
		"work_ticks":0,"last_repair_tick":-1,"queue":[]}
func setup(team):
	var game=Fixture.new(); game.tick_count=100; game.test_mode=true; game.ai_enabled=false
	for faction in 2:
		game.visible_cells[faction].resize(Rules.MAP_SIZE*Rules.MAP_SIZE); game.visible_cells[faction].fill(0)
		game.explored_cells[faction].resize(Rules.MAP_SIZE*Rules.MAP_SIZE); game.explored_cells[faction].fill(0)
	var archer=unit(0,team,"archer",Vector3(-6.5,0,0.5))
	var target={"id":1,"team":1-team,"category":"building","kind":"town_center","alive":true,"built":true,
		"pos":Vector3.ZERO,"radius":2.0,"hp":1000,"max_hp":1000,"queue":[],"death_observed_by":[false,false]}
	var observer=unit(2,team,"scout",Vector3(0.5,0,4.5))
	game.entities=[archer,target,observer]; game._path_state(archer); game._path_state(observer)
	game._navigation_rebuild(); game._update_vision(false)
	game._order(archer,"attack",target.id)
	check("separate scout supplies initial building sight",game._visible_to(target,team))
	check("old full-range slot is current archer position",game._attack_approach(archer,target)==archer.pos and is_equal_approx(game._attack_distance(archer.pos,target),4.5))
	return game
func dispose(game):
	for ent in game.entities:
		if ent.category=="unit": ent.body.free()
	game.free()
func _initialize():
	for team in 2:
		var visible=setup(team); var archer=visible.entities[0]; var target=visible.entities[1]
		var before=archer.pos
		visible._move_unit_phase(archer,Rules.TICK); visible._update_unit(archer,Rules.TICK)
		check("observed control fires without moving or routing",archer.pos==before and visible.path_requests.is_empty() and visible.attack_ledger.next_attack_id()==2)
		dispose(visible)
		for destroyed in [false,true]:
			var game=setup(team); archer=game.entities[0]; target=game.entities[1]
			# Physical-footprint sight now sees the keep from the old -6.5
			# origin. Move farther back so this remains a truly unseen-site case.
			archer.pos=Vector3(-8.5,0,0.5)
			game.entities[2].pos=Vector3(-20.5,0,20.5); game._update_vision(false)
			check("observer withdrawal really hides entire building footprint",not game._visible_to(target,team))
			if destroyed:
				# Explicit synthetic unseen destruction, not a natural combat claim.
				target.alive=false; game._navigation_rebuild()
			var remembered={"category":target.category,"kind":target.kind,"pos":archer.last_known,"radius":target.radius}
			var old_searches=archer.path_searches
			var approach=game._attack_approach(archer,remembered,true)
			check("first stage selects sight-valid ranged slot",approach==Vector3(-5.5,0,0.5) and game._attack_distance(approach,remembered)<=Rules.RANGE.archer and archer.path_searches==old_searches)
			# Synthetic known-grid mask tests blocked melee slots, not a claim
			# that this formation occurred in an ordinary match.
			var known=game._route_grid(archer); var saved={}
			for cell in game._perimeter_cells(remembered):
				if game._attack_distance(game._point(cell),remembered)<0.6:
					saved[cell]=known.is_point_solid(cell); known.set_point_solid(cell,true)
			check("blocked known melee ring cannot veto sight recovery",game._attack_approach(archer,remembered,true)==approach)
			for cell in saved: known.set_point_solid(cell,saved[cell])
			var start=archer.pos; var first=game.attack_ledger.next_attack_id(); var bounded=true; var hidden_hit=false
			for step in 160:
				game.tick_count+=1; game._process_path_requests(); game._begin_unit_motion()
				game._move_unit_phase(archer,Rules.TICK); game._update_vision(false)
				var observed=game._attack_target_observed(target,team); var previous=game.attack_ledger.next_attack_id()
				game._update_unit(archer,Rules.TICK)
				if not observed and game.attack_ledger.next_attack_id()!=previous: hidden_hit=true
				bounded=bounded and game.last_path_queries<=4 and game.last_path_expansions<=4*game.path_expansion_budget
				if destroyed and archer.state=="idle": break
				if not destroyed and game.attack_ledger.next_attack_id()>first: break
			check("pursuit actually advances under unchanged query caps",archer.pos!=start and bounded and not hidden_hit)
			if destroyed:
				check("unseen destroyed site finishes by old close inspection",archer.state=="idle" and archer.mode=="STOP" and game._attack_distance(archer.pos,remembered)<0.6 and game.attack_ledger.next_attack_id()==first and target.death_observed_by==[false,false])
			else:
				var event=game.attack_ledger.event(first)
				check("live target regained and genuine release issued",game._visible_to(target,team) and not event.is_empty() and event.attacker_id==archer.id and event.target_id==target.id)
				check("regained sight stops at normal range, not forced melee",game._attack_distance(archer.pos,target)>0.6 and game._attack_distance(archer.pos,target)<=Rules.RANGE.archer)
				var stopped=archer.pos; game._move_unit_phase(archer,Rules.TICK)
				check("observed in-range continuation holds position",archer.pos==stopped and not archer.path_pending)
			dispose(game)
	var failures=checks.filter(func(row):return not row.passed)
	print("ARCHER_SITE_INSPECTION "+JSON.stringify({"build":Rules.BUILD_ID,"checks":checks,"failure_count":failures.size(),"scope":"synthetic setup; actual callbacks; ENGINE_UNRUN at preparation"}))
	quit(0 if failures.is_empty() else 1)
