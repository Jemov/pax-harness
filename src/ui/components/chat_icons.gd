extends RefCounted
## Re-rasterize SVG icons at the viewport's actual display density.
static var _cache: Dictionary = {}
const PATHS := {
	"attachment":"M8 13l7-7a3 3 0 0 1 4 4l-9 9a5 5 0 0 1-7-7l9-9m-5 12l9-9",
	"image":"M3 4h18v16H3zM3 16l5-5 5 5 3-3 5 5M15 8h1",
	"minus":"M5 12h14",
	"plus":"M5 12h14M12 5v14",
	"filter":"M3 5h18l-7 8v6l-4 2v-8L3 5z",
	"link":"M10 14l4-4M8 16l-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0m0 12a4 4 0 0 0 6 0l5-5a4 4 0 0 0-6-6l-1 1",
	"play":"M8 5l11 7-11 7V5z",
	"more":"M5 11v2m7-2v2m7-2v2",
	"reset":"M4 10a8 8 0 1 1 1 8M4 4v6h6",
	"root":"M12 20V4m-6 6l6-6 6 6M4 20h16",
	"check":"M5 12l4 4L19 6",
	"chevron":"M9 6l6 6-6 6",
	"expand":"M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5",
	"restore":"M8 3v5H3m13-5v5h5M3 16h5v5m13-5h-5v5",
	"close":"M6 6l12 12M18 6L6 18",
	"edit":"M4 16l-1 5 5-1L20 8l-4-4L4 16zm10-10l4 4",
	"external":"M14 3h7v7m0-7L10 14M10 5H4a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-6",
	"return":"M10 3H3v7m0-7l11 11M14 5h6a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-6",
	"instructions":"M6 3h12v18H6zM9 7h6M9 11h6M9 15h4",
	"mic":"M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0V5zm-3 5v2a6 6 0 0 0 12 0v-2M12 18v4m-4 0h8",
	"send":"M12 20V4m-6 6l6-6 6 6",
	"stop":"M6 6h12v12H6z",
	"pin":"M8 3h8m-6 0v6l-4 5h12l-4-5V3m-2 11v8",
	"section":"M8 5h13M8 12h13M8 19h13M3 5h1M3 12h1M3 19h1",
	"copy":"M9 9h12v12H9zM5 15H3V3h12v2",
	"trash":"M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7",
	"speed":"M4 18a9 9 0 1 1 16 0M12 13l5-6",
	"tokens":"M5 6c0-4 14-4 14 0s-14 4-14 0zm0 0v6c0 4 14 4 14 0V6M5 12v6c0 4 14 4 14 0v-6",
	"context":"M12 3a9 9 0 1 0 9 9m-9-9v9h9"
}
static func make(kind: String, color: Color = Color("#949ba7"), pixels: int = 18) -> Texture2D:
	var key: String = kind+color.to_html()+str(pixels)
	if _cache.has(key): return _cache[key]
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#%s" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>' % [pixels,pixels,PATHS.get(kind,PATHS.close),color.to_html(false)]
	var texture := DPITexture.create_from_string(svg)
	_cache[key] = texture
	return texture
