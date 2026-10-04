class_name Num
extends RefCounted
## Big numbers for an economy that never stops growing.
##
## Every amount that can grow without limit (money, income, prices, multipliers, stars, Grit) is
## stored as its base-10 logarithm: $1,000 is 3.0, $1e5000 is 5000.0. A double holds logs up to
## about 1e308, so values can reach 10^(10^308): there is no ceiling in practice. Multiplying
## is adding logs, so the multiplicative economy stays cheap, and nothing allocates.
##
## Zero is ZERO (-1e300, a finite stand-in for -infinity so saves stay valid JSON and sums never
## turn into NaN); anything below -330 counts as zero. Stored values are never negative: anything
## that can go below zero (cash in a challenge) is kept as two non-negative parts instead (cash
## and an amount owed). A few calculations need signed amounts; they use [log, is_negative] pairs
## (see sadd / scmp).
##
## Naming: variables and functions holding logs end in _l.

const ZERO := -1.0e300
const LN10 := 2.302585092994046


## log10 of an ordinary number (0 or less gives ZERO).
static func L(v: float) -> float:
	if v <= 0.0 or is_nan(v):
		return ZERO
	if is_inf(v):
		return INF
	return log(v) / LN10


## The ordinary number for a log (INF past ~1e308, 0 below ~1e-308). Only for display maths,
## ratios and small values.
static func V(l: float) -> float:
	if l < -330.0:
		return 0.0
	if l > 308.0:
		return INF
	return pow(10.0, l)


static func is_zero(l: float) -> bool:
	return l < -330.0 or is_nan(l)


## log10(10^a + 10^b)
static func add(a: float, b: float) -> float:
	if is_zero(a):
		return b
	if is_zero(b):
		return a
	var hi := maxf(a, b)
	var lo := minf(a, b)
	var d := lo - hi
	if d < -17.0:
		return hi
	return hi + log(1.0 + pow(10.0, d)) / LN10


## log10(10^a - 10^b), floored at zero.
static func sub(a: float, b: float) -> float:
	if is_zero(b):
		return a
	if b >= a:
		return ZERO
	var d := b - a
	if d < -17.0:
		return a
	return a + log(1.0 - pow(10.0, d)) / LN10


static func sum(ls: Array) -> float:
	var s := ZERO
	for l in ls:
		s = add(s, float(l))
	return s


## Signed difference 10^a - 10^b as [log10 of the size, is negative].
static func diff(a: float, b: float) -> Array:
	if a >= b:
		return [sub(a, b), false]
	return [sub(b, a), true]


## Total price of k items when the first costs 10^c0 and each costs g times the last:
## c0 * (g^k - 1) / (g - 1).
static func geo(c0: float, g: float, k: int) -> float:
	if k <= 0:
		return ZERO
	var lg := L(g)
	var kg := lg * k
	var top: float
	if kg > 15.0:
		top = kg   # g^k - 1 ~ g^k
	else:
		top = L(pow(10.0, kg) - 1.0)
	return c0 + top - L(g - 1.0)


## The most items affordable with a budget of 10^budget when the first costs 10^c0 and each
## costs g times the last.
static func geo_max(budget: float, c0: float, g: float) -> int:
	if is_zero(budget) or budget < c0:
		return 0
	var lg := L(g)
	var x := budget + L(g - 1.0) - c0   # log10(budget * (g-1) / c0)
	var k: float
	if x > 15.0:
		k = x / lg
	else:
		k = L(pow(10.0, x) + 1.0) / lg
	k = floor(k + 1e-9)
	if k > 1.0e15:
		return 1000000000000000
	return maxi(1, int(k))


## A whole number of items (stars, Grit): rounds down while the count is small enough to matter.
static func floor_l(l: float) -> float:
	if is_zero(l) or l >= 15.0:
		return l
	return L(floor(pow(10.0, l) + 1e-6))


## Sum of two signed amounts, each [log10 of the size, is negative].
static func sadd(a: Array, b: Array) -> Array:
	var an: bool = a[1] and not is_zero(a[0])
	var bn: bool = b[1] and not is_zero(b[0])
	if an == bn:
		return [add(a[0], b[0]), an]
	if an:
		return diff(b[0], a[0])
	return diff(a[0], b[0])


static func sneg(a: Array) -> Array:
	return [a[0], not a[1]]


## -1, 0 or 1 comparing two signed amounts (relative tolerance tol on the logs).
static func scmp(a: Array, b: Array, tol := 1e-12) -> int:
	var d := sadd(a, sneg(b))
	if is_zero(d[0]) or d[0] < maxf(float(a[0]), float(b[0])) + log(tol) / LN10:
		return 0
	return -1 if d[1] else 1


# ------------------------------------------------------------------ formatting

const SUFFIX := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "UDc", "DDc", "TDc", "QaDc",
	"QiDc", "SxDc", "SpDc", "OcDc", "NoDc", "Vg", "UVg", "DVg", "TVg", "QaVg", "QiVg", "SxVg", "SpVg", "OcVg", "NoVg", "Tg"]


## A number from its log: 950, 1.23K, 45.6Qa, then 1.23e100 and 1.23e12,345 past the named ones.
static func fmt(l: float) -> String:
	if is_zero(l):
		return "0"
	if is_inf(l):
		return "∞"
	if l < 3.0:
		var v := pow(10.0, l)
		if v < 10.0 and absf(v - round(v)) > 1e-9:
			return "%.2f" % v
		if v < 100.0 and absf(v - round(v)) > 1e-9:
			return "%.1f" % v
		return "%d" % int(round(v))
	var e := int(floor(l + 1e-9))
	var g := e / 3
	if g < SUFFIX.size():
		var m := pow(10.0, l - g * 3)
		if m >= 999.995:
			m /= 1000.0
			g += 1
		if g < SUFFIX.size():
			return ("%.2f" % m if m < 100.0 else "%.1f" % m) + SUFFIX[g]
	var mant := pow(10.0, l - e)
	if mant >= 9.995:
		mant /= 10.0
		e += 1
	return "%.2fe%s" % [mant, _group(e)]


static func fmt_money(l: float) -> String:
	return "$" + fmt(l)


## A signed amount, e.g. a net income that can be negative.
static func fmt_signed_money(l: float, neg: bool) -> String:
	return ("-" if neg and not is_zero(l) else "") + fmt_money(l)


static func _group(n: int) -> String:
	var s := str(absi(n))
	if s.length() <= 4:
		return ("-" if n < 0 else "") + s
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
