extends RefCounted
## PNG encoder for in-memory pixels only; no filesystem/image-file APIs.
## CompressionMode.DEFLATE = 1 (zlib stream); IDAT uses standard PNG filter0.
const DEFLATE := 1
static var _crc_table: PackedInt64Array = PackedInt64Array()

static func _u32(value: int) -> PackedByteArray:
	return PackedByteArray([(value>>24)&255,(value>>16)&255,(value>>8)&255,value&255])

static func _crc32(bytes: PackedByteArray) -> int:
	if _crc_table.is_empty():
		for n: int in 256:
			var c: int = n
			for bit: int in 8: c=(c>>1)^0xedb88320 if c&1 else c>>1
			_crc_table.append(c)
	var crc: int = 0xffffffff
	for byte: int in bytes: crc=(crc>>8)^_crc_table[(crc^byte)&255]
	return (crc^0xffffffff)&0xffffffff

static func _chunk(kind: String, bytes: PackedByteArray) -> PackedByteArray:
	var body: PackedByteArray = kind.to_ascii_buffer(); body.append_array(bytes)
	var chunk: PackedByteArray = _u32(bytes.size()); chunk.append_array(body); chunk.append_array(_u32(_crc32(body)))
	return chunk

static func encode(image: Image) -> PackedByteArray:
	if image==null or image.is_empty() or image.get_format()!=Image.FORMAT_RGB8: return PackedByteArray()
	var width: int=image.get_width(); var height: int=image.get_height()
	if width<=0 or height<=0 or width>1600 or height>1600: return PackedByteArray()
	var pixels: PackedByteArray=image.get_data()
	var stride: int=width*3
	if pixels.size()!=stride*height: return PackedByteArray()
	var scanlines := PackedByteArray()
	for row: int in height:
		scanlines.append(0); scanlines.append_array(pixels.slice(row*stride,(row+1)*stride))
	var compressed: PackedByteArray=scanlines.compress(DEFLATE)
	if compressed.is_empty(): return PackedByteArray()
	var ihdr: PackedByteArray=_u32(width);ihdr.append_array(_u32(height));ihdr.append_array(PackedByteArray([8,2,0,0,0]))
	var png:=PackedByteArray([137,80,78,71,13,10,26,10])
	png.append_array(_chunk("IHDR",ihdr));png.append_array(_chunk("IDAT",compressed));png.append_array(_chunk("IEND",PackedByteArray()))
	return png
