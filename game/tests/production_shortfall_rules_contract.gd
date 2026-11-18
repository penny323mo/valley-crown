extends SceneTree
const S=preload("res://scripts/production_shortfall.gd")
var checks=[]
func c(name,passed):checks.append({"name":name,"passed":bool(passed)})
func _initialize():
	var bank={"food":49999,"wood":180000,"stone":0,"iron":900000}
	var copy=bank.duplicate(true)
	c("fractional milli shortage rounds up one",S.describe({"food":50},bank,1,10,true)=="缺食1")
	c("workshop exact missing stone only",S.describe({"wood":180,"stone":80},bank,1,10,false)=="缺石80")
	c("all deficits stable resource order",S.describe({"wood":200,"food":60,"iron":901},bank,1,10,true)=="缺食11；缺木20；缺鐵1")
	c("housing differs from hard limit",S.describe({},bank,10,10,true)=="人口 10/10 · 需民居")
	c("hard population limit explicit",S.describe({},bank,50,50,true)=="人口 50/50 · 已達50人上限")
	c("building not blocked by population",S.describe({},bank,50,50,false).is_empty())
	c("queue technology and deficits all retained",S.describe({"stone":80},bank,10,10,true,false,5)=="需城防時代；生產隊列已滿；人口 10/10 · 需民居；缺石80")
	c("exact payment boundary",S.describe({"wood":180},bank,9,10,true).is_empty())
	c("bank remains unchanged",bank==copy)
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"production_shortfall_rules_contract","checks":checks,"failed":failed,"scope":"Pure presentation rules, milli precision, population, queue, technology. No authority actions."}))
	quit(1 if failed else 0)
