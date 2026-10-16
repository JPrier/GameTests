extends RefCounted
## Small integer-only random generator (xorshift32 seeded through splitmix-style mixing).
## Only integer arithmetic, so a seed gives the same sequence on every platform and engine
## version (unlike float-based generators). Level generation uses nothing else.

var state := 1


func _init(seed_value: int = 1) -> void:
	var s := seed_value & 0xFFFFFFFF
	s = (s ^ 0x9E3779B9) & 0xFFFFFFFF
	s = ((s ^ (s >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	s = ((s ^ (s >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	s = (s ^ (s >> 16)) & 0xFFFFFFFF
	state = s if s != 0 else 0x6D2B79F5


func next_u32() -> int:
	var x := state
	x = (x ^ (x << 13)) & 0xFFFFFFFF
	x = x ^ (x >> 17)
	x = (x ^ (x << 5)) & 0xFFFFFFFF
	state = x
	return x


## Integer in [lo, hi], inclusive.
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo + 1)


## True with probability pct/100.
func chance(pct: int) -> bool:
	return next_u32() % 100 < pct


func pick(arr: Array):
	return arr[next_u32() % arr.size()]


## String hash that doesn't depend on the engine's String.hash() (stable FNV-1a over UTF-8).
static func hash_str(s: String) -> int:
	var h := 0x811C9DC5
	for b in s.to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	return h
