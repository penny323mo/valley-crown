extends SceneTree
## Value-only presentation contract. No match, rendering or phone acceptance.
const Status=preload("res://scripts/construction_status.gd")
var checks=[]
func check(name: String, passed: bool):
	checks.append({"name":name,"pass":passed})
	if not passed: push_error(name)
func _initialize():
	var site={"id":20,"owned":true,"alive":true,"remembered":false,"team":0,"category":"building","built":false,"progress":0.25}
	var worker={"id":1,"owned":true,"alive":true,"remembered":false,"team":0,"category":"unit","kind":"villager","state":"build","target":20,"visual_action":"idle","path":[],"path_pending":false,"path_status":"IDLE"}
	var empty_text=Status.detail(site,{})
	check("unassigned site explains manual recovery",empty_text=="施工 25% · 無施工村民；可按「派閒置村民續建」")
	check("assignment alone does not claim work or arrival",Status.detail(site,{1:worker})=="施工 25% · 村民已接單，等候施工")
	var working=worker.duplicate(true); working.visual_action="build"
	check("only successful construction cue claims work",Status.detail(site,{1:working})=="施工 25% · 建造中")
	var walking=worker.duplicate(true); walking.path=[Vector3.ONE]
	check("existing route explains approach",Status.detail(site,{1:walking})=="施工 25% · 村民移動到工地")
	var searching=worker.duplicate(true); searching.path_pending=true
	check("pending path is not claimed to be walking",Status.detail(site,{1:searching})=="施工 25% · 村民已接單，尋路中")
	for status in ["NO_PATH","LIMIT_REACHED","NO_WORK"]:
		var blocked=worker.duplicate(true); blocked.path_status=status
		check(status+" explains route stopped and manual recovery",Status.detail(site,{1:blocked})=="施工 25% · 村民尋路停止；選村民後直接點工地")
	check("pause does not claim building from frozen work cue",Status.detail(site,{1:working},false,true)=="施工 25% · 已暫停；按繼續返回戰場")
	check("queued own command does not claim old assignment",Status.detail(site,{1:working},true)=="施工 25% · 指令等待中")
	check("queued reassignment does not claim new builder",Status.detail(site,{},true)=="施工 25% · 指令等待中")
	for patch in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"category":"building"},{"kind":"spearman"},{"state":"idle"},{"state":"gather"},{"state":"move"},{"target":21}]:
		var changed=working.duplicate(true); changed.merge(patch,true)
		check("ignore invalid builder even with work cue "+str(patch),Status.detail(site,{1:changed})==empty_text)
	for action in ["idle","gather_wood","gather_food","repair","attack"]:
		var changed=worker.duplicate(true); changed.visual_action=action
		check("unrelated action is not construction "+action,Status.detail(site,{1:changed}).ends_with("等候施工"))
	for patch in [{"owned":false},{"alive":false},{"remembered":true},{"team":1},{"category":"unit"},{"built":true}]:
		var changed=site.duplicate(true); changed.merge(patch,true)
		check("no construction status for excluded site "+str(patch),Status.detail(changed,{1:working}).is_empty())
	var later=site.duplicate(true); later.progress=0.67
	check("progress uses the supplied observation",Status.detail(later,{1:working}).begins_with("施工 67%"))
	var records={1:worker}; var before=records.duplicate(true); var before_site=site.duplicate(true)
	for i in 8: Status.detail(site,records)
	check("repeated presentation never mutates inputs",records==before and site==before_site)
	var failed=checks.filter(func(c): return not c.pass).size()
	print(JSON.stringify({"contract":"construction_status","passed":checks.size()-failed,"failed":failed,"checks":checks,"source_sha256":FileAccess.get_sha256("res://scripts/construction_status.gd"),"scope":"Value-only presentation; not gameplay, rendered pixels or physical-phone acceptance"}))
	quit(1 if failed else 0)
