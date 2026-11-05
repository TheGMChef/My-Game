class_name UITokens
extends RefCounted
## Design tokens: colours, spacing and type sizes in one place.
##
## Spacing follows an 8px grid (4px for small gaps). Type sizes are 12 (meta), 14 (secondary),
## 16 (body), 20 (heading) and 24 (title). Colour budget: dark neutral canvas (about 60%),
## raised surfaces (about 30%), one teal accent for things you can act on (about 10%).
## The two sides use the Okabe-Ito blue and orange, which stay distinct for colour-blind players
## and are also told apart by shape (circles versus hexagons).

const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24
const SPACE_8 := 32

const TEXT_META := 12
const TEXT_SECONDARY := 14
const TEXT_BODY := 16
const TEXT_HEADING := 20
const TEXT_TITLE := 24

const HIT := 48          ## minimum touch target in px
const TOP_BAR := 56
const BOTTOM_BAR := 72
const SIDE_PANEL := 320
const RADIUS := 8

# Neutrals
const CANVAS := Color("12151b")
const SURFACE := Color("1b2029")
const RAISED := Color("232a35")
const BORDER := Color("323a48")
const BORDER_STRONG := Color("46505f")
const TEXT := Color("e6e9ef")
const TEXT_DIM := Color("a3acb9")
const TEXT_FAINT := Color("7b8594")

# Accent: interactive things
const ACCENT := Color("2dd4bf")
const ACCENT_DIM := Color("14675e")
const ON_ACCENT := Color("0b1514")

# Sides (Okabe-Ito)
const SIDE_COLOURS: Array[Color] = [Color("56b4e9"), Color("e69f00")]

# Terrain and board
const BOARD_FLOOR := Color("171c24")
const GRID := Color("222936")
const ZONE_TINT: Array[Color] = [Color(0.34, 0.71, 0.91, 0.07), Color(0.90, 0.62, 0.0, 0.07)]
const TERRAIN_DENSE := Color("3b4252")
const TERRAIN_LIGHT := Color("2c3340")
const TERRAIN_EXPOSED := Color("232a35")


static func legal(colour_blind: bool) -> Color:
	return Color("56b4e9") if colour_blind else Color("34d399")


static func illegal(colour_blind: bool) -> Color:
	return Color("d55e00") if colour_blind else Color("f87171")


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
