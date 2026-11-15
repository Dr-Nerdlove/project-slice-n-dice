class_name SimShard
extends RefCounted
## A flying shard (the Shards modifier).

var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var dir := Vector2.RIGHT
var range_left := 0.0
var speed := 20.0
var radius := 0.12
var bounces_left := 0
var owner_id := 0
var pass_level := 0           # 1 = passes obstacle blocks, 2 = also the crate (Shards + Piercing)
var blast := 0.0              # > 0: explodes with this radius where it ends (Shards + Warhead)
