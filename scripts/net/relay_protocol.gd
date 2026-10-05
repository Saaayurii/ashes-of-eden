extends RefCounted
class_name RelayProtocol
## The wire between a player and the relay (docs/RELAY.md): what ZeroTier or
## Radmin do for a LAN game, done inside the game. Both players dial *out* to
## the relay, so neither needs an open port, a forwarded router or a public
## address — a phone on mobile data and a browser tab can host as well as join.
##
## One binary WebSocket frame per message: a type byte, then a signed 32-bit
## little-endian peer id, then (for data) the multiplayer packet untouched.
## The relay never reads a game packet; it only knows rooms and who is in them.

## Bumped when a frame changes shape. The relay refuses a mismatch outright
## rather than forwarding frames the other side would misread.
const VERSION := 1
const DEFAULT_PORT := 8920

## player -> relay
const HELLO_HOST := 0x01  # [type][version][wanted code: 0 or CODE_LENGTH ascii]
const HELLO_JOIN := 0x02  # [type][version][code: CODE_LENGTH ascii]
const SEND := 0x10        # [type][i32 target][packet]  target 0 all, >0 one, <0 all but -target
const KICK := 0x11        # [type][i32 peer]  (host only)
## relay -> player
const WELCOME := 0x81     # [type][i32 your id][code: CODE_LENGTH ascii]
const PEER_IN := 0x82     # [type][i32 peer]
const PEER_OUT := 0x83    # [type][i32 peer]
const DELIVER := 0x90     # [type][i32 from][packet]
const ERROR := 0xE0       # [type][u8 reason]; the relay closes the socket after it

enum Reason {NONE, NO_ROOM, FULL, VERSION, BUSY, BAD}

## What each refusal says on the player's screen.
const REASON_KEYS := {
	Reason.NO_ROOM: "NET_ERR_NO_ROOM",
	Reason.FULL: "NET_ERR_FULL",
	Reason.VERSION: "NET_ERR_VERSION",
	Reason.BUSY: "NET_ERR_RELAY_BUSY",
	Reason.BAD: "NET_ERR_RELAY",
}

## Six characters read out over voice chat: neither half of 0/O, 1/I/L, 5/S
## or 8/B, so nothing can be misheard or mistyped. 27 left, ~387 million codes.
const CODE_ALPHABET := "234679ACDEFGHJKMNPQRTUVWXYZ"
const CODE_LENGTH := 6
const HEADER := 5


## What a player typed, as a code, or "" when it is not one: case, spaces and
## the dash the screen shows between the halves are forgiven.
static func normalize_code(text: String) -> String:
	var code := ""
	for ch in text.strip_edges().to_upper():
		if ch == "-" or ch == " ":
			continue
		if not CODE_ALPHABET.contains(ch):
			return ""
		code += ch
	return code if code.length() == CODE_LENGTH else ""


## A code read out loud: ABC-DEF.
static func pretty_code(code: String) -> String:
	if code.length() != CODE_LENGTH:
		return code
	return code.left(3) + "-" + code.right(3)


static func random_code(rng: RandomNumberGenerator) -> String:
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return code


static func frame(type: int, peer: int, payload := PackedByteArray()) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEADER)
	out[0] = type
	out.encode_s32(1, peer)
	out.append_array(payload)
	return out


static func hello(type: int, code: String) -> PackedByteArray:
	var out := PackedByteArray([type, VERSION])
	out.append_array(code.to_ascii_buffer())
	return out


static func error(reason: int) -> PackedByteArray:
	return PackedByteArray([ERROR, reason])


static func peer_of(packet: PackedByteArray) -> int:
	return packet.decode_s32(1) if packet.size() >= HEADER else 0
