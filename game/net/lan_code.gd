class_name LanCode
extends RefCounted
## A short code for the IPv4 address of a hosting phone (the port is always NetProto.DEFAULT_PORT).
## Joining by code needs no broadcast, only plain unicast UDP.
##
## Layout: 2 class bits, then the address bits, padded with zero bits to a multiple of 5; every character
## carries 5 bits of the alphabet below.
##   class 0: 192.168.x.y        16 address bits  -> 4 characters
##   class 1: 172.16.0.0/12      20 address bits  -> 5 characters
##   class 2: 10.x.y.z           24 address bits  -> 6 characters
##   class 3: any other IPv4     32 address bits  -> 7 characters
## Decoding is case-insensitive and ignores spaces and dashes.

## 32 characters; 0, O, 1 and I are left out because they look alike (L stays: capital L is distinct).
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ADDRESS_BITS := [16, 20, 24, 32]
const CLASS_BITS := 2
## Mobile data interfaces, the last choice for hosting.
const MOBILE_PREFIXES := ["rmnet", "ccmni", "pdp"]
## Wi-Fi and Ethernet interfaces (and hotspot ones), the first choice.
const LAN_PREFIXES := ["wlan", "ap", "swlan", "softap", "wl", "en", "eth"]


## "a.b.c.d" -> the four octets, or [] when it is not a plain IPv4 address.
static func parse_ipv4(ip: String) -> Array[int]:
	var out: Array[int] = []
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4:
		return out
	for p in parts:
		if p.length() < 1 or p.length() > 3:
			return [] as Array[int]
		for c in p:
			if c < "0" or c > "9":
				return [] as Array[int]
		var v := int(p)
		if v > 255 or (p.length() > 1 and p.begins_with("0")):
			return [] as Array[int]
		out.append(v)
	return out


## 0..3 for the code class of an address, -1 for an invalid one.
static func class_of(o: Array[int]) -> int:
	if o.size() != 4:
		return -1
	if o[0] == 192 and o[1] == 168:
		return 0
	if o[0] == 172 and o[1] >= 16 and o[1] <= 31:
		return 1
	if o[0] == 10:
		return 2
	return 3


static func encode(ip: String) -> String:
	var o := parse_ipv4(ip)
	var cls := class_of(o)
	if cls < 0:
		return ""
	var addr := 0
	match cls:
		0:
			addr = (o[2] << 8) | o[3]
		1:
			addr = ((o[1] & 15) << 16) | (o[2] << 8) | o[3]
		2:
			addr = (o[1] << 16) | (o[2] << 8) | o[3]
		_:
			addr = (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3]
	var nbits: int = ADDRESS_BITS[cls]
	var chars := ceili(float(CLASS_BITS + nbits) / 5.0)
	var bits := ((cls << nbits) | addr) << (chars * 5 - CLASS_BITS - nbits)
	var out := ""
	for i in chars:
		out += ALPHABET[(bits >> ((chars - 1 - i) * 5)) & 31]
	return out


## "" when the code is not valid: wrong characters, a length that does not fit its class, or padding bits that
## are not zero.
static func decode(code: String) -> String:
	var clean := code.to_upper().replace(" ", "").replace("-", "")
	if clean.length() < 4 or clean.length() > 7:
		return ""
	var bits := 0
	for c in clean:
		var v := ALPHABET.find(c)
		if v < 0:
			return ""
		bits = (bits << 5) | v
	var chars := clean.length()
	var total := chars * 5
	var cls := bits >> (total - CLASS_BITS)
	var nbits: int = ADDRESS_BITS[cls]
	if ceili(float(CLASS_BITS + nbits) / 5.0) != chars:
		return ""
	var pad := total - CLASS_BITS - nbits
	if bits & ((1 << pad) - 1) != 0:
		return ""
	var addr := (bits >> pad) & ((1 << nbits) - 1)
	match cls:
		0:
			return "192.168.%d.%d" % [(addr >> 8) & 255, addr & 255]
		1:
			return "172.%d.%d.%d" % [16 + ((addr >> 16) & 15), (addr >> 8) & 255, addr & 255]
		2:
			return "10.%d.%d.%d" % [(addr >> 16) & 255, (addr >> 8) & 255, addr & 255]
	return "%d.%d.%d.%d" % [(addr >> 24) & 255, (addr >> 16) & 255, (addr >> 8) & 255, addr & 255]


## The code with a space after every 4 characters, for showing (decode ignores the space).
static func grouped(code: String) -> String:
	if code.length() <= 4:
		return code
	var out := ""
	for i in code.length():
		if i > 0 and i % 4 == 0:
			out += " "
		out += code[i]
	return out


## The best IPv4 address to host on, from the data of IP.get_local_interfaces() (a list of
## {"name", "addresses": [...]}). Never loopback, link-local (169.254), multicast or IPv6. Prefers 192.168.*,
## then 172.16/12, then 10.*, then the rest; among equal classes Wi-Fi / Ethernet / hotspot interfaces beat
## unknown ones, and those beat mobile data. "" when nothing fits.
static func pick_local_address(interfaces: Array) -> String:
	var best := ""
	var best_score := 1 << 30
	for itf: Variant in interfaces:
		if not (itf is Dictionary):
			continue
		var name := str((itf as Dictionary).get("name", "")).to_lower()
		var name_rank := 1
		for p: String in MOBILE_PREFIXES:
			if name.begins_with(p):
				name_rank = 2
		if name_rank == 1:
			for p: String in LAN_PREFIXES:
				if name.begins_with(p):
					name_rank = 0
					break
		var addrs: Variant = (itf as Dictionary).get("addresses", [])
		if not (addrs is Array or addrs is PackedStringArray):
			continue
		for a: Variant in addrs:
			var o := parse_ipv4(str(a))
			var cls := class_of(o)
			if cls < 0 or o[0] == 127 or o[0] == 0 or o[0] >= 224 or (o[0] == 169 and o[1] == 254):
				continue
			var score := cls * 10 + name_rank
			if score < best_score:
				best_score = score
				best = str(a)
	return best
