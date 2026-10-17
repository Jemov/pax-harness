extends RefCounted
## Shared measured text layout. No draw_string width clipping.
static func wrap_lines(text: String, width: float, font: Font, font_size: int = 12) -> PackedStringArray:
	var lines := PackedStringArray()
	for paragraph: String in text.split("\n"):
		var line := ""
		for word: String in paragraph.split(" ",false):
			var candidate: String = word if line == "" else line+" "+word
			if font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x <= width:
				line = candidate; continue
			if line != "": lines.append(line); line = ""
			for i: int in word.length():
				if line != "" and font.get_string_size(line+word[i],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width:
					lines.append(line); line = ""
				line += word[i]
		if line != "" or paragraph == "": lines.append(line)
	return lines

static func line_height(font: Font, font_size: int = 12) -> float:
	return ceilf(font.get_height(font_size))+3

static func height(text: String, width: float, font: Font, font_size: int = 12) -> float:
	return 0 if text == "" else wrap_lines(text,maxf(1,width),font,font_size).size()*line_height(font,font_size)

static func draw_text(owner: Control, text: String, rect: Rect2, color: Color, align: HorizontalAlignment, font_size: int, boxes: Array) -> void:
	if text == "" or rect.size.x < 1: return
	var font: Font = owner.get_theme_default_font()
	var step: float = line_height(font,font_size)
	var y: float = rect.position.y
	for line: String in wrap_lines(text,rect.size.x,font,font_size):
		var width: float = font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var x: float = rect.position.x+(rect.size.x-width if align == HORIZONTAL_ALIGNMENT_RIGHT else (rect.size.x-width)/2 if align == HORIZONTAL_ALIGNMENT_CENTER else 0)
		owner.draw_string(font,Vector2(x,y+font.get_ascent(font_size)),line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
		boxes.append({"text":line,"rect":Rect2(x,y,width,step-2)})
		y += step
