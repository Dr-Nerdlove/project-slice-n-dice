class_name SimWire
extends RefCounted
## A tripwire lying on the ground (Tripwire): a polyline that follows the string path.

var pts := PackedVector2Array()
var half_width := 0.06
var owner_id := 0
var ttl := 0.0
var lethal := false
var stun := 0.0
