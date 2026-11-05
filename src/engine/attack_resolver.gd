class_name AttackResolver
extends RefCounted
## Resolves a batch of attacks with one weapon against one unit using the 11th edition
## attack sequence: hit rolls, wound rolls, save rolls, inflict damage (core rules 05).
##
## Not yet modelled: modifier caps, random characteristics (these rules are not in the
## supplied PDFs), mixed-profile units, visibility per model. [TWIN-LINKED] is applied as
## "re-roll a failed wound roll" (the 10th edition rule): the 11th core text does not define it.

## Context keys (all optional):
##   half_range (bool)   target was within half range when targets were selected
##   cover (bool)        target has the benefit of cover against these attacks
##   heavy_bonus (bool)  the [HEAVY] conditions are met
##   charged (bool)      the attacking unit made a charge move this turn
##   hit_mod (int)       total modifier to the hit roll
##   wound_mod (int)     total modifier to the wound roll
##   models_firing (int) number of attacking models using this weapon (default 1)
##   indirect_min (int)  [INDIRECT FIRE] attacks: an unmodified hit roll below this fails (10.07)


## The roll needed to wound (core rules 05.02).
static func wound_threshold(strength: int, toughness: int) -> int:
	if strength >= toughness * 2:
		return 2
	if strength > toughness:
		return 3
	if strength == toughness:
		return 4
	if strength * 2 <= toughness:
		return 6
	return 5


## Skill and hit modifier for the weapon after cover, [HEAVY] and [PSYCHIC]. A [PSYCHIC] weapon
## ignores penalties to BS/WS and to the hit roll (24.29) but keeps bonuses.
static func hit_numbers(weapon: Weapon, ctx: Dictionary) -> Dictionary:
	var skill: int = weapon.skill + (1 if bool(ctx.get("cover", false)) and not weapon.has("IGNORES COVER") else 0)
	var hit_mod: int = int(ctx.get("hit_mod", 0)) + (1 if bool(ctx.get("heavy_bonus", false)) and weapon.has("HEAVY") else 0)
	if weapon.has("PSYCHIC"):
		skill = mini(skill, weapon.skill)
		hit_mod = maxi(hit_mod, 0)
	return {"skill": skill, "hit_mod": hit_mod}


## 0 = the wound roll fails, 1 = wounds, 2 = critical wound (a 6 or the [ANTI] threshold).
static func wound_result(roll: int, wound_mod: int, threshold: int, anti_at: int) -> int:
	if roll == 1:
		return 0
	if roll == 6 or roll >= anti_at:
		return 2
	return 1 if roll + wound_mod >= threshold else 0


## Extra attack dice each attacking model gains from [BLAST], [CLEAVE] and [RAPID FIRE].
static func extra_attacks_each(weapon: Weapon, target: UnitState, ctx: Dictionary) -> int:
	var extra_each: int = 0
	var fives: int = target.model_count() / 5
	var blast: Dictionary = weapon.ability("BLAST", target.keywords)
	if not blast.is_empty():
		extra_each += maxi(1, int(blast["value"])) * fives
	var cleave: Dictionary = weapon.ability("CLEAVE", target.keywords)
	if not cleave.is_empty() and bool(ctx.get("single_target", true)):
		extra_each += int(cleave["value"]) * fives
	var rapid: Dictionary = weapon.ability("RAPID FIRE", target.keywords)
	if not rapid.is_empty() and bool(ctx.get("half_range", false)):
		extra_each += int(rapid["value"])
	return extra_each


## Number of attack dice for the weapon, including [BLAST], [RAPID FIRE] and [CLEAVE].
static func gather_attacks(weapon: Weapon, target: UnitState, dice: Dice, ctx: Dictionary) -> int:
	var firing: int = int(ctx.get("models_firing", 1))
	var extra_each: int = extra_attacks_each(weapon, target, ctx)
	var total: int = 0
	for i in range(firing):
		total += dice.roll(weapon.attacks) + extra_each
	return total


## Resolve every attack. Returns a report dictionary (counts) and changes [param target].
static func resolve(weapon: Weapon, target: UnitState, dice: Dice, ctx: Dictionary = {}) -> Dictionary:
	var report: Dictionary = {
		"attacks": 0, "hits": 0, "critical_hits": 0, "wounds": 0, "critical_wounds": 0,
		"saved": 0, "unsaved": 0, "damage": 0, "mortal_wounds": 0, "models_destroyed": 0,
		"fnp_saved": 0,
	}
	var start_models: int = target.model_count()
	var attacks: int = gather_attacks(weapon, target, dice, ctx)
	report["attacks"] = attacks

	var d_bonus: int = 0
	var melta: Dictionary = weapon.ability("MELTA", target.keywords)
	if not melta.is_empty() and bool(ctx.get("half_range", false)):
		d_bonus = int(melta["value"])

	# 1. Hit rolls
	var numbers: Dictionary = hit_numbers(weapon, ctx)
	var skill: int = numbers["skill"]
	var hit_mod: int = numbers["hit_mod"]
	var indirect_min: int = int(ctx.get("indirect_min", 0))
	var to_wound: int = 0       # hits that still need a wound roll
	var auto_wounds: int = 0    # lethal hits: wound without a roll
	var torrent: bool = weapon.has("TORRENT")
	var sustained: Dictionary = weapon.ability("SUSTAINED HITS", target.keywords)
	var lethal: bool = weapon.has("LETHAL HITS", target.keywords)
	var hit_rolls: Array[int] = []
	if not torrent:
		hit_rolls = dice.roll_many(attacks)
	if torrent:
		to_wound = attacks
		report["hits"] = attacks
	for r in hit_rolls:
		if r == 1 or r < indirect_min:
			continue
		var is_crit: bool = r == 6
		if not is_crit and r + hit_mod < skill:
			continue
		report["hits"] += 1
		if is_crit:
			report["critical_hits"] += 1
			if not sustained.is_empty():
				to_wound += int(sustained["value"])
				report["hits"] += int(sustained["value"])
			if lethal:
				auto_wounds += 1
				continue
		to_wound += 1

	# 2. Wound rolls
	var threshold: int = wound_threshold(weapon.strength, target.toughness)
	var wound_mod: int = int(ctx.get("wound_mod", 0)) + (1 if bool(ctx.get("charged", false)) and weapon.has("LANCE") else 0)
	var anti: Dictionary = weapon.ability("ANTI", target.keywords)
	var anti_at: int = int(anti["threshold"]) if not anti.is_empty() else 7
	var devastating: bool = weapon.has("DEVASTATING WOUNDS")
	var twin_linked: bool = weapon.has("TWIN-LINKED")
	var precision: bool = weapon.has("PRECISION")
	var normal_wounds: int = auto_wounds
	var devastating_crits: int = 0
	report["wounds"] += auto_wounds
	for r in dice.roll_many(to_wound):
		var result: int = wound_result(r, wound_mod, threshold, anti_at)
		if result == 0 and twin_linked:
			result = wound_result(dice.d6(), wound_mod, threshold, anti_at)
		if result == 0:
			continue
		report["wounds"] += 1
		if result == 2:
			report["critical_wounds"] += 1
			if devastating:
				devastating_crits += 1
				continue
		normal_wounds += 1

	# 3 and 4. Saves and damage
	var save_rolls: Array[int] = dice.roll_many(normal_wounds)
	save_rolls.sort()
	for r in save_rolls:
		if target.is_destroyed():
			break
		var group_index: int = _model_to_hit(target, precision)
		var model: Dictionary = target.models[group_index]
		var blocked: bool = false
		if r != 1:
			if target.invuln > 0 and r >= target.invuln:
				blocked = true
			elif r + weapon.ap >= target.save:
				blocked = true
		if blocked:
			report["saved"] += 1
			continue
		report["unsaved"] += 1
		var dmg: int = dice.roll(weapon.damage) + d_bonus
		var lost: int = _apply_damage(target, group_index, dmg, dice, report)
		report["damage"] += lost

	# Mortal wounds come after normal damage; one model at most per critical wound.
	for i in range(devastating_crits):
		if target.is_destroyed():
			break
		var mw: int = dice.roll(weapon.damage) + d_bonus
		var victim: Dictionary = target.models[_model_to_hit(target, precision)]
		var applied: int = 0
		for j in range(mw):
			applied += _apply_damage(target, target.models.find(victim), 1, dice, report)
			if int(victim["wounds"]) <= 0:
				break  # remaining mortal wounds from this critical wound are lost
		report["mortal_wounds"] += applied
	report["models_destroyed"] = start_models - target.model_count()
	return report


## Inflict [param count] mortal wounds one at a time (core rules 06.02).
static func mortal_wounds(target: UnitState, count: int, dice: Dice) -> int:
	var report: Dictionary = {"fnp_saved": 0}
	var lost: int = 0
	for i in range(count):
		if target.is_destroyed():
			break
		lost += _apply_damage(target, _model_to_hit(target), 1, dice, report)
	return lost


## Hazard roll (06.03): a 1 or 2 fails and the unit takes 1 mortal wound, or 3 if every
## model is a MONSTER or VEHICLE. Returns the wounds lost.
static func hazard_roll(target: UnitState, dice: Dice) -> int:
	var big: bool = target.has_keyword("MONSTER") or target.has_keyword("VEHICLE")
	if dice.d6() <= 2:
		return mortal_wounds(target, 3 if big else 1, dice)
	return 0


## Pick the model that takes the next hit: a wounded non-CHARACTER, else any
## non-CHARACTER, else a wounded CHARACTER, else any CHARACTER. With [PRECISION] the
## CHARACTER models come first (24.28; visibility per model is not modelled, so any
## CHARACTER in a visible unit counts as visible).
static func _model_to_hit(target: UnitState, precision: bool = false) -> int:
	for pass_no in range(4):
		var want_character: bool = (pass_no >= 2) != precision
		var want_wounded: bool = pass_no % 2 == 0
		for i in range(target.models.size()):
			var m: Dictionary = target.models[i]
			if bool(m["character"]) != want_character:
				continue
			if want_wounded and int(m["wounds"]) >= target.wounds_per_model:
				continue
			return i
	return 0


## Remove [param amount] wounds from one model, rolling Feel No Pain per wound. There is no
## spill-over damage. Returns the wounds actually lost.
static func _apply_damage(target: UnitState, index: int, amount: int, dice: Dice, report: Dictionary) -> int:
	var lost: int = 0
	for i in range(amount):
		if target.fnp > 0 and dice.d6() >= target.fnp:
			report["fnp_saved"] = int(report.get("fnp_saved", 0)) + 1
			continue
		lost += 1
	var m: Dictionary = target.models[index]
	m["wounds"] = int(m["wounds"]) - lost
	if int(m["wounds"]) <= 0:
		target.last_position = m["pos"]
		target.models.remove_at(index)
	return lost
