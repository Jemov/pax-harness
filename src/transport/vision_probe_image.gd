extends RefCounted
const Png=preload("res://mods/pax_harness/src/images/ui_png.gd")
const DIGITS=["11111100011001110101110011000111111","00100011000010000100001000010001110","11111000010000111111100001000011111","11111000010000101111000010000111111","10001100011000111111000010000100001","11111100001000011111000010000111111","11111100001000011111100011000111111","11111000010001000100010000100001000","11111100011000111111100011000111111","11111100011000111111000010000111111"]
static func create() -> Dictionary:
 var random: PackedByteArray=Crypto.new().generate_random_bytes(6);var code:=""
 var image:=Image.create(224,64,false,Image.FORMAT_RGB8);image.fill(Color("172333"))
 for i: int in 6:
  var digit: int=int(random[i])%10;code+=str(digit)
  for y: int in 7:
   for x: int in 5:
    if DIGITS[digit][y*5+x]=="1":image.fill_rect(Rect2i(14+i*33+x*5,14+y*5,5,5),Color.WHITE)
 var bytes: PackedByteArray=Png.encode(image)
 var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes)
 return {"code":code,"bytes":bytes,"handle":{"id":"reference_"+digest.finish().hex_encode(),"mime_type":"image/png","width":224,"height":64,"byte_size":bytes.size(),"source":"user_reference","name":"Automatic image capability check"}}
