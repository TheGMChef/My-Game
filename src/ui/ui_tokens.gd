class_name UITokens
extends RefCounted
## Muster design tokens: colours, spacing, type and corner cuts in one place.
##
## The rule is "cold board, hot actions": blue-black neutrals everywhere, and ACTION only on the
## current choice. Sides stay blue and orange, and are also told apart by shape (circles versus
## hexagons). Text and mark colours meet 4.5:1 and 3:1 on the grounds they are used on.

const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_6 := 24
const SPACE_8 := 32

const TEXT_META := 13
const TEXT_LABEL := 13
const TEXT_SECONDARY := 15
const TEXT_BODY := 16
const TEXT_STAT := 16
const TEXT_HEADING := 20
const TEXT_SCORE := 22
const TEXT_TITLE := 28
const TEXT_READOUT := 40
const TEXT_WORDMARK := 64
const TEXT_WORDMARK_HERO := 112

const HIT := 48          ## minimum touch target in px
const TOP_BAR := 64
const BOTTOM_BAR := 72
const SIDE_PANEL := 340
const PHONE_COLUMN := 196

# The notch: a 45-degree cut on the top-right and bottom-left corners.
const NOTCH_SM := 6
const NOTCH_MD := 10
const NOTCH_LG := 16

# Neutrals
const VOID := Color("080c12")
const HULL := Color("0f151d")
const PLATE := Color("161e29")
const RAISED := Color("212c3a")
const EDGE := Color("34445a")
const EDGE_STRONG := Color("6d819b")
const INK := Color("eef3f8")
const INK_DIM := Color("b1bfcf")
const INK_FAINT := Color("93a3b7")

# Sides
const PLAYER := Color("3fc8f2")
const ON_PLAYER := Color("04202b")
const ENEMY := Color("ff8a3c")
const ON_ENEMY := Color("2b1102")
const SIDE_COLOURS: Array[Color] = [PLAYER, ENEMY]

# Action: the current choice
const ACTION := Color("ffc72c")
const ACTION_HOVER := Color("ffd968")
const ON_ACTION := Color("1c1500")

# Objectives belong to neither side until claimed
const RELAY := Color("b9a0ff")

# Board
const BOARD_FLOOR := Color("0b1118")
const BOARD_GRID := Color("1c2734")
const ZONE_TINT: Array[Color] = [Color(0.247, 0.784, 0.949, 0.13), Color(1.0, 0.541, 0.235, 0.13)]
const TERRAIN_FILL := Color("2c3a4d")
const TERRAIN_EDGE := Color("8ea3bd")

# Fonts
const FONT_DISPLAY: Font = preload("res://assets/fonts/ChakraPetch-SemiBold.ttf")
const FONT_DISPLAY_BOLD: Font = preload("res://assets/fonts/ChakraPetch-Bold.ttf")
const FONT_SANS: Font = preload("res://assets/fonts/IBMPlexSans-Variable.ttf")
const FONT_MONO: Font = preload("res://assets/fonts/IBMPlexMono-Medium.ttf")
const FONT_MONO_BOLD: Font = preload("res://assets/fonts/IBMPlexMono-SemiBold.ttf")


static func legal(colour_blind: bool) -> Color:
	return Color("56b4e9") if colour_blind else Color("4be3a6")


static func illegal(colour_blind: bool) -> Color:
	return Color("e8701a") if colour_blind else Color("ff5c74")


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
