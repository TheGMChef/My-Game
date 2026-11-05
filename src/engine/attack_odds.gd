class_name AttackOdds
extends RefCounted
## Exact expected results of attacks, for showing the player before they shoot or fight.
## Mirrors [AttackResolver] step for step; tests compare the two by simulation.


## Returns a dictionary of per-step numbers:
## attacks, hit_target, wound_target, save_text, p_hit, p_wound, p_unsaved, hits, wounds,
## unsaved, expected_damage (including mortal wounds from Devastating Wounds), expected_models_destroyed.
static func compute(weapon: Weapon, target: UnitState, ctx: Dictionary = {}) -> Dictionary:
	var firing: int = int(ctx.get("models_firing", 1))
	var attacks: float = (Dice.average(weapon.attacks) + float(AttackResolver.extra_attacks_each(weapon, target, ctx))) * float(firing)

	# Hit rolls
	var skill: int = weapon.skill + (1 if bool(ctx.get("cover", false)) and not weapon.has("IGNORES COVER") else 0)
	var hit_mod: int = int(ctx.get("hit_mod", 0)) + (1 if bool(ctx.get("heavy_bonus", false)) and weapon.has("HEAVY") else 0)
	var torrent: bool = weapon.has("TORRENT")
	var p_hit: float = 1.0
	var p_crit_hit: float = 0.0
	if not torrent:
		var ok: int = 0
		for r in range(2, 7):
			if r == 6 or r + hit_mod >= skill:
				ok += 1
		p_hit = float(ok) / 6.0
		p_crit_hit = 1.0 / 6.0
	var sustained: Dictionary = weapon.ability("SUSTAINED HITS", target.keywords)
	var extra_hits: float = float(sustained["value"]) * p_crit_hit if not sustained.is_empty() else 0.0
	var lethal: bool = weapon.has("LETHAL HITS", target.keywords)
	var auto_wounds: float = p_crit_hit if lethal else 0.0
	var hits: float = attacks * (p_hit + extra_hits)
	var wound_rolls: float = attacks * (p_hit - auto_wounds + extra_hits)

	# Wound rolls
	var threshold: int = AttackResolver.wound_threshold(weapon.strength, target.toughness)
	var wound_mod: int = int(ctx.get("wound_mod", 0)) + (1 if bool(ctx.get("charged", false)) and weapon.has("LANCE") else 0)
	var anti: Dictionary = weapon.ability("ANTI", target.keywords)
	var anti_at: int = int(anti["threshold"]) if not anti.is_empty() else 7
	var ok_w: int = 0
	var crit_w: int = 0
	for r in range(2, 7):
		var crit: bool = r == 6 or r >= anti_at
		if crit:
			crit_w += 1
		if crit or r + wound_mod >= threshold:
			ok_w += 1
	var p_wound: float = float(ok_w) / 6.0
	var p_crit_wound: float = float(crit_w) / 6.0
	var devastating: bool = weapon.has("DEVASTATING WOUNDS")
	var wounds: float = wound_rolls * p_wound + attacks * auto_wounds
	var crit_wounds: float = wound_rolls * p_crit_wound
	var mortal_sources: float = crit_wounds if devastating else 0.0
	var normal_wounds: float = wounds - mortal_sources

	# Saves
	var unsaved_faces: int = 1  # an unmodified 1 always fails the save
	for r in range(2, 7):
		var blocked: bool = false
		if target.invuln > 0 and r >= target.invuln:
			blocked = true
		elif r + weapon.ap >= target.save:
			blocked = true
		if not blocked:
			unsaved_faces += 1
	var p_unsaved: float = float(unsaved_faces) / 6.0
	var unsaved: float = normal_wounds * p_unsaved

	# Damage: a model cannot lose more wounds than it has, and Feel No Pain ignores some.
	var bonus: int = 0
	var melta: Dictionary = weapon.ability("MELTA", target.keywords)
	if not melta.is_empty() and bool(ctx.get("half_range", false)):
		bonus = int(melta["value"])
	var per_hit: float = _capped_average(weapon.damage, bonus, target.wounds_per_model)
	var fnp_keep: float = 1.0
	if target.fnp > 0:
		fnp_keep = 1.0 - float(7 - target.fnp) / 6.0
	var damage: float = (unsaved + mortal_sources) * per_hit * fnp_keep
	return {
		"attacks": attacks,
		"hit_target": skill,
		"wound_target": threshold,
		"p_hit": p_hit,
		"p_wound": p_wound,
		"p_unsaved": p_unsaved,
		"hits": hits,
		"wounds": wounds,
		"unsaved": unsaved,
		"expected_damage": damage,
		"expected_models_destroyed": damage / float(maxi(1, target.wounds_per_model)),
		"auto_hit": torrent,
	}


static func _capped_average(expression: String, bonus: int, cap: int) -> float:
	var total: float = 0.0
	var dist: Dictionary = Dice.distribution(expression)
	for v in dist:
		total += float(mini(int(v) + bonus, cap)) * float(dist[v])
	return total
