class_name UISettings
extends RefCounted
## Player preferences. Saved to user://settings.cfg. Older files still load: every key has a
## default, and the keys that existed first keep their sections and names.

const PATH := "user://settings.cfg"
const TEXT_SCALES: Array[float] = [0.9, 1.0, 1.15, 1.3, 1.5]
## How long opponent animations last, as a share of normal. 0 skips them.
const AI_SPEEDS: Array[float] = [1.6, 1.0, 0.4, 0.0]
const AI_SPEED_NAMES: Array[String] = ["slow", "normal", "fast", "instant"]
const AI_SPEED_NORMAL := 1

var text_scale_index: int = 1
var colour_blind: bool = false
var reduced_motion: bool = false
var show_engagement: bool = true
var show_coherency: bool = false
var show_objectives: bool = true
var show_terrain_legend: bool = false
var show_plates: bool = true
var ai_speed_index: int = AI_SPEED_NORMAL
var confirm_end_phase: bool = true
## Reanimation Protocols brings destroyed models back. False means it heals wounds only.
var reanimate_models: bool = true


func text_scale() -> float:
	return TEXT_SCALES[clampi(text_scale_index, 0, TEXT_SCALES.size() - 1)]


func ai_speed() -> float:
	return AI_SPEEDS[clampi(ai_speed_index, 0, AI_SPEEDS.size() - 1)]


## [param path] is for tests. The game always uses [constant PATH].
func load_from_disk(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	text_scale_index = clampi(int(cfg.get_value("ui", "text_scale_index", 1)), 0, TEXT_SCALES.size() - 1)
	colour_blind = bool(cfg.get_value("ui", "colour_blind", false))
	reduced_motion = bool(cfg.get_value("ui", "reduced_motion", false))
	show_engagement = bool(cfg.get_value("overlays", "engagement", true))
	show_coherency = bool(cfg.get_value("overlays", "coherency", false))
	show_objectives = bool(cfg.get_value("overlays", "objectives", true))
	show_plates = bool(cfg.get_value("overlays", "plates", true))
	ai_speed_index = clampi(int(cfg.get_value("gameplay", "ai_speed", AI_SPEED_NORMAL)), 0, AI_SPEEDS.size() - 1)
	confirm_end_phase = bool(cfg.get_value("gameplay", "confirm_end_phase", true))
	reanimate_models = bool(cfg.get_value("gameplay", "reanimate_models", true))


## [param path] is for tests. The game always uses [constant PATH].
func save_to_disk(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "text_scale_index", text_scale_index)
	cfg.set_value("ui", "colour_blind", colour_blind)
	cfg.set_value("ui", "reduced_motion", reduced_motion)
	cfg.set_value("overlays", "engagement", show_engagement)
	cfg.set_value("overlays", "coherency", show_coherency)
	cfg.set_value("overlays", "objectives", show_objectives)
	cfg.set_value("overlays", "plates", show_plates)
	cfg.set_value("gameplay", "ai_speed", ai_speed_index)
	cfg.set_value("gameplay", "confirm_end_phase", confirm_end_phase)
	cfg.set_value("gameplay", "reanimate_models", reanimate_models)
	cfg.save(path)
