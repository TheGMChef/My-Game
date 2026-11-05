class_name UISettings
extends RefCounted
## Player preferences for the interface. Saved to user://settings.cfg.

const PATH := "user://settings.cfg"
const TEXT_SCALES: Array[float] = [0.9, 1.0, 1.15, 1.3, 1.5]

var text_scale_index: int = 1
var colour_blind: bool = false
var reduced_motion: bool = false
var show_engagement: bool = true
var show_coherency: bool = false
var show_objectives: bool = true
var show_terrain_legend: bool = false


func text_scale() -> float:
	return TEXT_SCALES[clampi(text_scale_index, 0, TEXT_SCALES.size() - 1)]


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	text_scale_index = int(cfg.get_value("ui", "text_scale_index", 1))
	colour_blind = bool(cfg.get_value("ui", "colour_blind", false))
	reduced_motion = bool(cfg.get_value("ui", "reduced_motion", false))
	show_engagement = bool(cfg.get_value("overlays", "engagement", true))
	show_coherency = bool(cfg.get_value("overlays", "coherency", false))
	show_objectives = bool(cfg.get_value("overlays", "objectives", true))


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "text_scale_index", text_scale_index)
	cfg.set_value("ui", "colour_blind", colour_blind)
	cfg.set_value("ui", "reduced_motion", reduced_motion)
	cfg.set_value("overlays", "engagement", show_engagement)
	cfg.set_value("overlays", "coherency", show_coherency)
	cfg.set_value("overlays", "objectives", show_objectives)
	cfg.save(PATH)
