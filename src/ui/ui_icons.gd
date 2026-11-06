class_name UIIcons
extends RefCounted
## Vector icons built from SVG text at startup. Never use font glyphs for icons: a glyph the
## font lacks shows as a missing-character box on some platforms.

const RENDER_SCALE := 3.0

const SHAPES := {
	"plus": "<path d='M12 4V20M4 12H20' stroke='%s' stroke-width='2' fill='none'/>",
	"minus": "<path d='M4 12H20' stroke='%s' stroke-width='2' fill='none'/>",
	"fit": "<path d='M3 8V3H8M16 3H21V8M3 16V21H8M16 21H21V16' stroke='%s' stroke-width='2' fill='none'/>",
	"close": "<path d='M5 5L19 19M19 5L5 19' stroke='%s' stroke-width='2' fill='none'/>",
	"check": "<path d='M4 13L10 19L20 6' stroke='%s' stroke-width='3' fill='none'/>",
	"menu": "<path d='M3 6H21M3 12H21M3 18H21' stroke='%s' stroke-width='2' fill='none'/>",
	"panel": "<path d='M3 4H21V20H3ZM14 4V20M16.5 9H19M16.5 12H19M16.5 15H19' stroke='%s' stroke-width='2' fill='none'/>",
	"ruler": "<path d='M2 16.5L16.5 2L22 7.5L7.5 22ZM6.5 12L9.5 15M10 8.5L13 11.5M13.5 5L16.5 8' stroke='%s' stroke-width='2' fill='none'/>",
	"chevron": "<path d='M5 9L12 16L19 9' stroke='%s' stroke-width='2' fill='none'/>",
	"chevron_up": "<path d='M5 15L12 8L19 15' stroke='%s' stroke-width='2' fill='none'/>",
	"box": "<rect x='3' y='3' width='18' height='18' stroke='%s' stroke-width='2' fill='none'/>",
	"box_on": "<rect x='3' y='3' width='18' height='18' fill='%s'/>",
	"box_check": "<rect x='3' y='3' width='18' height='18' fill='%s'/><path d='M7 12L11 16L18 8' stroke='#1c1500' stroke-width='2.5' fill='none'/>",
}

static var _cache: Dictionary = {}


## A square icon in the given colour, [param size] logical pixels across.
static func get_icon(icon_name: String, colour: Color, size: int = 24) -> Texture2D:
	var key: String = "%s_%s_%d" % [icon_name, colour.to_html(false), size]
	if _cache.has(key):
		return _cache[key]
	var body: String = str(SHAPES[icon_name]) % ("#" + colour.to_html(false))
	var svg: String = "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'>%s</svg>" % body
	var tex: Texture2D = _render(svg, RENDER_SCALE * float(size) / 24.0, Vector2i(size, size))
	_cache[key] = tex
	return tex


## The hazard stripe mark that sits on the main action button.
static func stripe(colour: Color) -> Texture2D:
	var key: String = "stripe_" + colour.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var c: String = "#" + colour.to_html(false)
	var body: String = ""
	for x in [0, 8, 16]:
		body += "<polygon points='%d,12 %d,12 %d,0 %d,0' fill='%s'/>" % [x, x + 3, x + 9, x + 6, c]
	var svg: String = "<svg xmlns='http://www.w3.org/2000/svg' width='26' height='12' viewBox='0 0 26 12'>%s</svg>" % body
	var tex: Texture2D = _render(svg, RENDER_SCALE, Vector2i(26, 12))
	_cache[key] = tex
	return tex


## Rendered larger than shown, so icons stay sharp when the interface is scaled up.
static func _render(svg: String, scale: float, shown_size: Vector2i) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(svg, scale)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	tex.set_size_override(shown_size)
	return tex
