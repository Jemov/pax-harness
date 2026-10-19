extends RefCounted
## Bounded PCM input; no external paths, codecs or executable resources.
const RATE=16000
const MAX_SECONDS=30
const MAX_BYTES=2*1024*1024
static func inspect(bytes: PackedByteArray) -> Dictionary:
	if bytes.size()<44 or bytes.size()>MAX_BYTES or bytes.slice(0,4).get_string_from_ascii()!="RIFF" or bytes.slice(8,12).get_string_from_ascii()!="WAVE":return {"ok":false,"code":"audio.invalid_wav"}
	if bytes.decode_u32(4)+8!=bytes.size():return {"ok":false,"code":"audio.invalid_wav"}
	var offset:=12;var format_: Dictionary={};var pcm:=PackedByteArray()
	while offset+8<=bytes.size():
		var kind: String=bytes.slice(offset,offset+4).get_string_from_ascii();var size_: int=bytes.decode_u32(offset+4);offset+=8
		if size_>bytes.size()-offset:return {"ok":false,"code":"audio.invalid_wav"}
		if kind=="fmt ":
			if size_<16 or not format_.is_empty():return {"ok":false,"code":"audio.invalid_wav"}
			format_={"encoding":bytes.decode_u16(offset),"channels":bytes.decode_u16(offset+2),"rate":bytes.decode_u32(offset+4),"bits":bytes.decode_u16(offset+14)}
		elif kind=="data":
			if not pcm.is_empty():return {"ok":false,"code":"audio.invalid_wav"}
			pcm=bytes.slice(offset,offset+size_)
		offset+=size_+(size_%2)
	if format_.get("encoding")!=1 or format_.get("bits")!=16 or format_.get("channels") not in [1,2] or format_.get("rate",0)<8000 or format_.get("rate",0)>96000 or pcm.is_empty():return {"ok":false,"code":"audio.pcm_required"}
	var frames: int=pcm.size()/(2*format_.channels)
	if pcm.size()%(2*format_.channels)!=0 or float(frames)/format_.rate>MAX_SECONDS:return {"ok":false,"code":"audio.too_long"}
	return {"ok":true,"pcm":pcm,"rate":format_.rate,"channels":format_.channels,"seconds":float(frames)/format_.rate}
static func encode(samples: PackedFloat32Array, rate: int) -> PackedByteArray:
	if rate<8000 or rate>192000 or samples.is_empty() or samples.size()>rate*MAX_SECONDS:return PackedByteArray()
	var count: int=mini(RATE*MAX_SECONDS,int(samples.size()*float(RATE)/rate));var bytes:=PackedByteArray();bytes.resize(44+count*2)
	for pair: Array in [[0,"RIFF"],[8,"WAVE"],[12,"fmt "],[36,"data"]]:
		var name_: PackedByteArray=pair[1].to_ascii_buffer()
		for i: int in 4:bytes[int(pair[0])+i]=name_[i]
	bytes.encode_u32(4,bytes.size()-8);bytes.encode_u32(16,16);bytes.encode_u16(20,1);bytes.encode_u16(22,1);bytes.encode_u32(24,RATE);bytes.encode_u32(28,RATE*2);bytes.encode_u16(32,2);bytes.encode_u16(34,16);bytes.encode_u32(40,count*2)
	for i: int in count:
		var source: float=float(i)*rate/RATE;var a: int=mini(int(source),samples.size()-1);var b: int=mini(a+1,samples.size()-1)
		var sample: float=lerpf(samples[a],samples[b],source-a)
		bytes.encode_s16(44+i*2,int(clampf(sample if is_finite(sample) else 0.0,-1.0,1.0)*32767))
	return bytes
static func normalize(bytes: PackedByteArray) -> Dictionary:
	var read: Dictionary=inspect(bytes)
	if not read.ok:return read
	var samples:=PackedFloat32Array();samples.resize(read.pcm.size()/(2*read.channels));var energy:=0.0
	for i: int in samples.size():
		var value: float=float(read.pcm.decode_s16(i*2*read.channels))/32768.0
		if read.channels==2:value=(value+float(read.pcm.decode_s16(i*4+2))/32768.0)/2
		samples[i]=value;energy+=value*value
	if read.seconds<0.2 or sqrt(energy/maxi(1,samples.size()))<0.0005:return {"ok":false,"code":"audio.empty_recording"}
	return {"ok":true,"bytes":encode(samples,read.rate),"seconds":read.seconds}
static func stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var read: Dictionary=inspect(bytes)
	if not read.ok:return null
	var sound:=AudioStreamWAV.new();sound.format=AudioStreamWAV.FORMAT_16_BITS;sound.mix_rate=read.rate;sound.stereo=read.channels==2;sound.data=read.pcm;return sound
