class_name Weapon
extends RefCounted
## One weapon profile. A range of 0 means a melee weapon.

var weapon_name: String = ""
var range_in: float = 0.0
var attacks: String = "1"
var skill: int = 4
var strength: int = 4
var ap: int = 0
var damage: String = "1"
var abilities: Array[Dictionary] = []


## Build a weapon from a data dictionary.
static func from_dict(d: Dictionary) -> Weapon:
	var w := Weapon.new()
	w.weapon_name = str(d.get("name", "weapon"))
	w.range_in = float(d.get("range", 0))
	w.attacks = str(d.get("attacks", "1"))
	w.skill = int(d.get("skill", 4))
	w.strength = int(d.get("strength", 4))
	w.ap = -absi(int(d.get("ap", 0)))
	w.damage = str(d.get("damage", "1"))
	for text in d.get("abilities", []):
		w.abilities.append(WeaponAbility.parse(str(text)))
	return w


## Plain data for a save file. Unlike the army data, this holds the parsed abilities.
func to_save() -> Dictionary:
	var ability_rows: Array = []
	for a in abilities:
		ability_rows.append({"name": a["name"], "value": a["value"], "threshold": a["threshold"],
			"keywords": (a["keywords"] as Array).duplicate()})
	return {"name": weapon_name, "range": range_in, "attacks": attacks, "skill": skill, "strength": strength,
		"ap": ap, "damage": damage, "abilities": ability_rows}


## Rebuild from [method to_save].
static func from_save(d: Dictionary) -> Weapon:
	var w := Weapon.new()
	w.weapon_name = str(d["name"])
	w.range_in = float(d["range"])
	w.attacks = str(d["attacks"])
	w.skill = int(d["skill"])
	w.strength = int(d["strength"])
	w.ap = int(d["ap"])
	w.damage = str(d["damage"])
	for a in d["abilities"]:
		var keywords: Array[String] = []
		for k in a["keywords"]:
			keywords.append(str(k))
		w.abilities.append({"name": str(a["name"]), "value": int(a["value"]), "threshold": int(a["threshold"]), "keywords": keywords})
	return w


func is_melee() -> bool:
	return range_in <= 0.0


## The ability with this name that applies to a target with these keywords, or an
## empty dictionary. Duplicates do not stack (24.02): the highest value is used.
func ability(ability_name: String, target_keywords: Array = []) -> Dictionary:
	var best: Dictionary = {}
	for a in abilities:
		if a["name"] != ability_name or not WeaponAbility.applies(a, target_keywords):
			continue
		if best.is_empty() or int(a["value"]) > int(best["value"]):
			best = a
	return best


func has(ability_name: String, target_keywords: Array = []) -> bool:
	return not ability(ability_name, target_keywords).is_empty()
