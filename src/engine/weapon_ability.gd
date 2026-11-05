class_name WeaponAbility
extends RefCounted
## Parses weapon ability text such as "RAPID FIRE 1", "ANTI-VEHICLE 4+" or "LETHAL HITS: VEHICLE".


## Turn ability text into {name, value, threshold, keywords}.
## [code]ANTI-X Y+[/code] becomes name ANTI, keywords [X], threshold Y.
## PISTOL is the same as CLOSE-QUARTERS (24.27) so it is renamed.
static func parse(text: String) -> Dictionary:
	var main: String = text.strip_edges().to_upper()
	var keywords: Array[String] = []
	var colon: int = main.find(":")
	if colon >= 0:
		for k in main.substr(colon + 1).split("/"):
			keywords.append(k.strip_edges())
		main = main.substr(0, colon).strip_edges()
	var result: Dictionary = {"name": main, "value": 0, "threshold": 0, "keywords": keywords}
	if main.begins_with("ANTI-"):
		var rest: String = main.substr(5)
		var space: int = rest.rfind(" ")
		var anti_keywords: Array[String] = [rest.substr(0, space)]
		result["name"] = "ANTI"
		result["keywords"] = anti_keywords
		result["threshold"] = int(rest.substr(space + 1))
		return result
	var last_space: int = main.rfind(" ")
	if last_space > 0 and main.substr(last_space + 1).is_valid_int():
		result["value"] = int(main.substr(last_space + 1))
		result["name"] = main.substr(0, last_space)
	if result["name"] == "PISTOL":
		result["name"] = "CLOSE-QUARTERS"
	return result


## True if the ability applies to a target with these keywords. An ability with no
## keywords always applies (24.01).
static func applies(ability: Dictionary, target_keywords: Array) -> bool:
	var needed: Array = ability["keywords"]
	if needed.is_empty():
		return true
	for k in needed:
		if target_keywords.has(k):
			return true
	return false
