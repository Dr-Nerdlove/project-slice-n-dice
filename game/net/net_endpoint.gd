class_name NetEndpoint
extends RefCounted
## Thin transport interface between the net cores and the wire. One implementation talks ENet, another is
## an in-memory loopback with delay and loss (tests), another wraps an endpoint with artificial lag.
##
## poll() returns the events since the last call, each a Dictionary:
##   {"kind": Kind, "peer": int, "data": PackedByteArray, "reliable": bool}
## A client sees the server as peer 1. A server numbers its clients itself (1, 2, 3, ...).

enum Kind { CONNECT, DISCONNECT, PACKET }


static func event(kind: int, peer: int, data := PackedByteArray(), reliable := true) -> Dictionary:
	return {"kind": kind, "peer": peer, "data": data, "reliable": reliable}


func poll() -> Array:
	return []


## Reliable packets arrive in order and are never lost; unreliable ones may be lost or overtaken.
func send(_peer: int, _data: PackedByteArray, _reliable: bool) -> void:
	pass


## Hands queued packets to the network now (the cores call this at the end of every tick).
func flush() -> void:
	pass


## Ends the connection to `peer` once the packets already queued for it have been sent.
func disconnect_peer(_peer: int) -> void:
	pass


func close() -> void:
	pass
