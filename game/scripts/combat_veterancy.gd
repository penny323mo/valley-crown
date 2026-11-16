extends RefCounted
## Private settled-combat progression. Not a player command or visibility source.
const KINDS=["scout","spearman","archer","cavalry","siege"]
var kills={}
var settled_through=0
func count(id: int) -> int:return int(kills.get(id,0))
func rank(id: int) -> int:return 2 if count(id)>=6 else (1 if count(id)>=3 else 0)
func settle(events: Array,damage: Dictionary,lookup: Callable) -> void:
	var contributions={}
	var through=settled_through
	for event in events:
		if event.attack_id<=settled_through:continue
		through=maxi(through,event.attack_id)
		if not contributions.has(event.target_id):contributions[event.target_id]={}
		var group=contributions[event.target_id]
		group[event.attacker_id]=group.get(event.attacker_id,0)+event.damage
	settled_through=through
	for target_id in contributions:
		var target=lookup.call(target_id)
		if target.is_empty() or not target.get("alive",false) or target.get("category","")!="unit" or target.get("kind","") not in KINDS or damage.get(target_id,0)<target.hp:continue
		var winner=-1;var best=0
		for id in contributions[target_id]:
			var attacker=lookup.call(id);var amount=contributions[target_id][id]
			if attacker.is_empty() or not attacker.get("alive",false) or attacker.get("category","")!="unit" or attacker.get("kind","") not in KINDS or attacker.get("team",-1) not in [0,1] or target.get("team",-1)!=1-attacker.team:continue
			# A unit that dies in the same settlement cannot become a veteran.
			if damage.get(id,0)>=attacker.hp:continue
			if amount>best or (amount==best and (winner<0 or id<winner)):winner=id;best=amount
		if winner>=0:kills[winner]=count(winner)+1

static func label(record: Dictionary) -> String:
	if record.get("kind","") not in KINDS:return ""
	var victories=int(record.get("combat_kills",0));var level=int(record.get("veterancy_rank",0))
	return ("精銳 · 擊破 %d · 攻擊 +2" % victories) if level>=2 else (("老兵 · 擊破 %d / 6 · 攻擊 +1" % victories) if level==1 else ("新兵 · 擊破 %d / 3" % victories))
