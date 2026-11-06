class_name UnitState
extends RefCounted
## One unit on the table. Every model in the unit shares one profile (mixed profiles,
## attached leaders and transports are not supported yet).

var id: String = ""
var unit_name: String = ""
var owner: int = 0
var toughness: int = 4
var save: int = 4
var invuln: int = 0  ## 0 = none
var fnp: int = 0  ## Feel No Pain X+, 0 = none
var wounds_per_model: int = 1
var move: float = 6.0
var objective_control: int = 1
var leadership: int = 6
var base_radius: float = 0.5
var keywords: Array[String] = []
var weapons: Array[Weapon] = []
var starting_strength: int = 0
var battle_shocked: bool = false
## Core abilities in upper case, e.g. "FIGHTS FIRST", "STEALTH".
var abilities: Array[String] = []
## Faction army rules in upper case, e.g. "SYNAPSE". See [ArmyRules].
var faction_abilities: Array[String] = []
var deadly_demise: String = ""  ## mortal wounds on a 6 when destroyed, "" = none
var last_position: Vector2 = Vector2.ZERO  ## where the most recent model was destroyed
## Turn flags, cleared at the end of each player turn by [method reset_turn_flags].
var advanced: bool = false
var fell_back: bool = false
var charged: bool = false
var last_fired_turn: int = -10  ## player-turn number of the last ranged attack, for hidden (13.09)
var max_model_move: float = 0.0  ## furthest any model moved this turn, for [HEAVY]
## Names of [ONE SHOT] weapons already fired this battle (24.26). Tracked per unit, not per model.
var one_shot_used: Array[String] = []
## Per model: {"pos": Vector2, "wounds": int, "character": bool}. Destroyed models are removed.
var models: Array[Dictionary] = []


## Build from a data dictionary; models are placed in a row starting at [param origin].
static func from_dict(d: Dictionary, unit_id: String, owner_id: int, origin: Vector2) -> UnitState:
	var u := UnitState.new()
	u.id = unit_id
	u.owner = owner_id
	u.unit_name = str(d.get("name", unit_id))
	u.toughness = int(d.get("toughness", 4))
	u.save = int(d.get("save", 4))
	u.invuln = int(d.get("invuln", 0))
	u.fnp = int(d.get("fnp", 0))
	u.deadly_demise = str(d.get("deadly_demise", ""))
	u.wounds_per_model = int(d.get("wounds", 1))
	u.move = float(d.get("move", 6))
	u.objective_control = int(d.get("oc", 1))
	u.leadership = int(d.get("leadership", 6))
	u.base_radius = float(d.get("base_mm", 32)) / 25.4 / 2.0
	for k in d.get("keywords", []) + d.get("faction_keywords", []):
		u.keywords.append(str(k).to_upper())
	for a in d.get("faction_abilities", []):
		u.faction_abilities.append(str(a).to_upper())
	for a in d.get("abilities", []):
		u.abilities.append(str(a).to_upper())
	for w in d.get("weapons", []):
		u.weapons.append(Weapon.from_dict(w))
	var count: int = int(d.get("models", 1))
	var columns: int = mini(count, 5)
	var spacing: float = u.base_radius * 2.0 + 0.1
	for i in range(count):
		u.models.append({
			"pos": origin + Vector2(float(i % columns) * spacing, float(i / columns) * spacing),
			"wounds": u.wounds_per_model,
			"character": u.keywords.has("CHARACTER"),
		})
	u.starting_strength = count
	return u


## Plain data for a save file: the profile as well as the state, so a save does not depend on the
## army file it came from. Vectors are [x, y], which survives JSON.
func to_save() -> Dictionary:
	var model_rows: Array = []
	for m in models:
		model_rows.append({"pos": [m["pos"].x, m["pos"].y], "wounds": m["wounds"], "character": m["character"]})
	var weapon_rows: Array = []
	for w in weapons:
		weapon_rows.append(w.to_save())
	return {"id": id, "name": unit_name, "owner": owner, "toughness": toughness, "save": save, "invuln": invuln,
		"fnp": fnp, "wounds_per_model": wounds_per_model, "move": move, "oc": objective_control,
		"leadership": leadership, "base_radius": base_radius, "keywords": keywords.duplicate(),
		"weapons": weapon_rows, "starting_strength": starting_strength, "battle_shocked": battle_shocked,
		"abilities": abilities.duplicate(), "faction_abilities": faction_abilities.duplicate(),
		"deadly_demise": deadly_demise, "last_position": [last_position.x, last_position.y],
		"advanced": advanced, "fell_back": fell_back, "charged": charged, "last_fired_turn": last_fired_turn,
		"max_model_move": max_model_move, "one_shot_used": one_shot_used.duplicate(), "models": model_rows}


## Rebuild from [method to_save]. Numbers may arrive as floats from JSON, so each is cast.
static func from_save(d: Dictionary) -> UnitState:
	var u := UnitState.new()
	u.id = str(d["id"])
	u.unit_name = str(d["name"])
	u.owner = int(d["owner"])
	u.toughness = int(d["toughness"])
	u.save = int(d["save"])
	u.invuln = int(d["invuln"])
	u.fnp = int(d["fnp"])
	u.wounds_per_model = int(d["wounds_per_model"])
	u.move = float(d["move"])
	u.objective_control = int(d["oc"])
	u.leadership = int(d["leadership"])
	u.base_radius = float(d["base_radius"])
	u.keywords.assign(d["keywords"])
	u.starting_strength = int(d["starting_strength"])
	u.battle_shocked = bool(d["battle_shocked"])
	u.abilities.assign(d["abilities"])
	u.faction_abilities.assign(d["faction_abilities"])
	u.deadly_demise = str(d["deadly_demise"])
	u.last_position = Vector2(float(d["last_position"][0]), float(d["last_position"][1]))
	u.advanced = bool(d["advanced"])
	u.fell_back = bool(d["fell_back"])
	u.charged = bool(d["charged"])
	u.last_fired_turn = int(d["last_fired_turn"])
	u.max_model_move = float(d["max_model_move"])
	u.one_shot_used.assign(d["one_shot_used"])
	for w in d["weapons"]:
		u.weapons.append(Weapon.from_save(w))
	for m in d["models"]:
		u.models.append({"pos": Vector2(float(m["pos"][0]), float(m["pos"][1])), "wounds": int(m["wounds"]), "character": bool(m["character"])})
	return u


func model_count() -> int:
	return models.size()


func is_destroyed() -> bool:
	return models.is_empty()


func has_keyword(k: String) -> bool:
	return keywords.has(k)


func total_wounds_left() -> int:
	var t: int = 0
	for m in models:
		t += int(m["wounds"])
	return t


## True when the unit is at or below half its starting strength (battle-shock trigger).
func at_or_below_half_strength() -> bool:
	return models.size() * 2 <= starting_strength


## Centre of the unit, for rough range checks.
func centre() -> Vector2:
	var sum := Vector2.ZERO
	for m in models:
		sum += m["pos"]
	return sum / maxf(1.0, float(models.size()))


## Forget the per-turn movement flags (call at the end of a player turn).
func reset_turn_flags() -> void:
	advanced = false
	fell_back = false
	charged = false
	max_model_move = 0.0


## A unit is a Fights First unit if it has the ability or made a charge move this turn (11.04).
func is_fights_first() -> bool:
	return charged or abilities.has("FIGHTS FIRST")


## Smallest gap between the edges of this unit's models and another unit's models.
func gap_to(other: UnitState) -> float:
	var best: float = INF
	for m in models:
		for n in other.models:
			best = minf(best, Geo.edge_distance(m["pos"], base_radius, n["pos"], other.base_radius))
	return best
