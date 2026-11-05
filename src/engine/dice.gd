class_name Dice
extends RefCounted
## Seedable dice roller. Tests can pass a fixed list of D6 results instead of random ones.
##
## Supported expressions: "3", "D3", "D6", "2D6", "D6+1", "2D6+3".

var rolls_made: int = 0

var _rng := RandomNumberGenerator.new()
var _scripted: Array[int] = []
var _use_script: bool = false


## [param seed_value] makes random rolls repeatable. If [param scripted] is not empty,
## [method d6] returns those values in order instead of random ones.
func _init(seed_value: int = 1, scripted: Array[int] = []) -> void:
	_rng.seed = seed_value
	if not scripted.is_empty():
		_scripted = scripted.duplicate()
		_use_script = true


## Roll one six-sided die.
func d6() -> int:
	rolls_made += 1
	if _use_script:
		if _scripted.is_empty():
			push_error("Dice: scripted dice ran out")
			return 1
		return _scripted.pop_front()
	return _rng.randi_range(1, 6)


## Number of scripted results that have not been used yet.
func scripted_left() -> int:
	return _scripted.size()


## Roll a dice expression such as "D6+1". A D3 is a D6 halved, rounded up.
func roll(expression: String) -> int:
	var parsed: Dictionary = Dice.parse(expression)
	var total: int = parsed["plus"]
	var sides: int = parsed["sides"]
	for i in range(int(parsed["count"])):
		var r: int = d6()
		total += r if sides == 6 else (r + 1) >> 1
	return total


## Roll a number of D6 and return each result.
func roll_many(count: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(count):
		out.append(d6())
	return out


## Split an expression into {count, sides, plus}. A plain number has count 0.
static func parse(expression: String) -> Dictionary:
	var text: String = expression.strip_edges().to_upper()
	var plus: int = 0
	var plus_at: int = text.find("+")
	if plus_at >= 0:
		plus = int(text.substr(plus_at + 1))
		text = text.substr(0, plus_at)
	var d_at: int = text.find("D")
	if d_at < 0:
		return {"count": 0, "sides": 0, "plus": int(text) + plus}
	var count: int = 1 if d_at == 0 else int(text.substr(0, d_at))
	var sides: int = int(text.substr(d_at + 1))
	return {"count": count, "sides": sides, "plus": plus}


## True if the expression is one this class can roll.
static func is_valid(expression: String) -> bool:
	var text: String = expression.strip_edges()
	if text.is_empty():
		return false
	var parsed: Dictionary = Dice.parse(text)
	var sides: int = parsed["sides"]
	if int(parsed["count"]) == 0:
		return text.is_valid_int()
	return sides == 3 or sides == 6


## Average result of an expression (a D3 averages 2, a D6 averages 3.5).
static func average(expression: String) -> float:
	var parsed: Dictionary = Dice.parse(expression)
	var sides: int = parsed["sides"]
	var per_die: float = 3.5 if sides == 6 else 2.0
	return float(parsed["count"]) * per_die + float(parsed["plus"])
