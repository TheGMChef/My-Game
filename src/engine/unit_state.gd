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
	u.wounds_per_model = int(d.get("wounds", 1))
	u.move = float(d.get("move", 6))
	u.objective_control = int(d.get("oc", 1))
	u.leadership = int(d.get("leadership", 6))
	u.base_radius = float(d.get("base_mm", 32)) / 25.4 / 2.0
	for k in d.get("keywords", []):
		u.keywords.append(str(k).to_upper())
	for w in d.get("weapons", []):
		u.weapons.append(Weapon.from_dict(w))
	var count: int = int(d.get("models", 1))
	for i in range(count):
		u.models.append({
			"pos": origin + Vector2(float(i) * (u.base_radius * 2.0 + 0.1), 0.0),
			"wounds": u.wounds_per_model,
			"character": u.keywords.has("CHARACTER"),
		})
	u.starting_strength = count
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
