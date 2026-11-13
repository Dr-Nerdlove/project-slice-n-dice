class_name SimShard
extends RefCounted
## A flying shard (Splitter).

var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var dir := Vector2.RIGHT
var range_left := 0.0
var speed := 20.0
var radius := 0.12
var bounces_left := 0
var owner_id := 0
