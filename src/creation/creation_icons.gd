extends RefCounted
static var cache: Dictionary={}
static func make(spec: Variant) -> Texture2D:
	var key: String=JSON.stringify(spec)
	if cache.has(key): return cache[key]
	var body: String=""
	if spec is Dictionary:
		var h: int=spec.rows.size(); var w: int=str(spec.rows[0]).length()
		for y: int in h:
			for x: int in w:
				var color: int=str(spec.rows[y])[x].hex_to_int()
				if color>0: body+='<rect x="%s" y="%s" width="%s" height="%s" fill="%s"/>' % [x*32.0/w,y*32.0/h,32.0/w+0.01,32.0/h+0.01,spec.palette[color-1]]
	else:
		match str(spec):
			"gate": body='<circle cx="16" cy="16" r="12" fill="none" stroke="#8fcaff" stroke-width="4"/><circle cx="16" cy="16" r="6" fill="#4b7088"/>'
			"dust": body='<path d="M16 1L19 12L30 16L19 20L16 31L13 20L2 16L13 12Z" fill="#e0bb7e"/><circle cx="5" cy="4" r="2" fill="#8fcaff"/>'
			"crystal": body='<path d="M16 1L27 12L21 29L11 29L5 12Z" fill="#8fcaff"/><path d="M16 1L20 13L16 29L12 13Z" fill="#b8a4db"/>'
			"panel": body='<rect x="3" y="4" width="26" height="24" rx="3" fill="none" stroke="#8fcaff" stroke-width="3"/><path d="M8 11H24M8 17H24M8 23H18" stroke="#8fcaff" stroke-width="2"/>'
			_: body='<path d="M3 10H12V3H20V10H29V22H20V29H12V22H3Z" fill="#8fcaff"/>'
	var image:=Image.new()
	if image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'+body+'</svg>')!=OK: return null
	var texture: Texture2D=ImageTexture.create_from_image(image)
	if cache.size()>=64: cache.erase(cache.keys()[0])
	cache[key]=texture; return texture
