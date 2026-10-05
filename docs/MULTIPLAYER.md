# Multiplayer — two players, every device

Two ways to play together, both online, both crossplay:

- **Story together** — co-op through the same chain of rooms.
- **Duel** — one on one, first to three rounds.

A desktop, a phone and a browser tab can sit in the same session. That
constraint is what picked the transport, and the transport shaped everything
else, so it comes first.

## Why WebSocket

Godot ships three multiplayer peers. ENet (UDP) is the fastest and the one most
Godot games use — and it does not exist in a Web export. WebRTC works in the
browser but needs a signalling server of its own before two peers can even say
hello. `WebSocketMultiplayerPeer` runs on every target we ship, and a browser
client can talk to a native host over it without any extra service.

So the whole game speaks WebSocket, host included. It is TCP, so a lost packet
stalls the ones behind it; for two players in a side-view brawler that is a
trade we can afford, and it is the only option that keeps a phone and a browser
in the same match.

One consequence worth knowing: **a browser cannot listen for connections.**
Through the relay (docs/RELAY.md) it does not need to: a browser hosts a room
by code like any other build. Without a relay, two browsers need the dedicated
host below.

## Who decides what

| Thing | Owner |
|---|---|
| Room chain, door, run end | host |
| Enemies (movement, attacks, death, essence) | host |
| Duel score and rounds | host |
| A player's body (input, position, animation) | that player's peer |
| Damage a body takes | the peer that owns the body |
| Gifts a player picks | that player's peer |

The rule that keeps this honest: **a body is only ever hurt by its owner.**
`Player.take_damage` and `Enemy.take_damage` are the only doors damage comes
through, and both forward the hit to the owner instead of applying it locally
when they are not it. A client cannot decide that it dodged, and it cannot
decide that an enemy died.

Bodies are mirrored by a `MultiplayerSynchronizer` built in code
(`Net.attach_sync`) rather than saved in the scene, so the same node has the
same replicated properties whether a spawner made it or the editor did.

Enemy theatre — the wind-up flash, the swing, the beam, the death — travels as
RPCs, not as replicated state, so both players read the same telegraph at the
same moment. Bolts are the exception: they fly straight at a constant speed, so
each client draws its own copy and only the host's bolt bites.

Awareness is the host's too. Whether an enemy has noticed anyone is decided
where it is simulated, so a backstab is not claimed by the client that swung:
the client sends what the blow would be worth on a sleeper (`sneak` in the hit
info) and the host applies it only if the body really was one. The "!" is an
RPC like the other theatre; `aware` is replicated so the minimap on a client
can tell a sleeper from a hunter.

## Joining a game

Main menu → **Play together**.

1. One player picks the mode and presses **Create game**. The screen shows a
   **code** (`PF7-Z3V`) and the addresses a friend on the same network can use.
2. The other types the code into **Join** — from any network, on any device —
   or picks the game from **Games on this network**, or types an address.
3. Both press **Ready**; the host presses **Start**.

Codes go through the relay, so nobody forwards a port: docs/RELAY.md. The
host also listens on `8910` (TCP) itself, which is what a friend on the same
Wi-Fi or a typed address connects to directly.

The address field also takes a full URL, which is what a browser needs when the
page is served over HTTPS:

```
wss://play.example.com/game
```

A page on `https://` may not open a plain `ws://` socket — browsers block it.
Put the host behind a TLS proxy and hand out the `wss://` URL.

While a match runs, the link shows at the top of the screen (round trip in
ms), "connection unstable" appears when the other side goes quiet, and a match
the wire ended says why over the menu (docs/RELAY.md, "The link, on screen").

## Dedicated host

For two browsers, or for a game that outlives whoever started it:

```bash
godot --headless -- --server --port=8910 --mode=coop     # or --mode=pvp
make server                                              # the same, in Docker
```

It holds no player of its own: it just referees, and starts the match once
every connected player has pressed Ready.

## Co-op rules that differ from solo

- **Essence and levels are shared.** The host counts; both players are offered
  a gift when the bar fills, and each picks their own.
- **Gifts are personal.** Your stats are yours, and so is the Grace /
  Temptation / Will a gift carries — you can each lean a different way, and
  each of you gets the ending line your own leaning earned. The host waits for
  both of you at the door before loading the next room.
- **Ash is minted by the host** (bosses are simulated there) and travels with
  the end-of-run verdict, so both profiles are paid.
- **The story has one voice.** Everyone sees the same dialogue; the host's
  buttons are the live ones and their answer is replayed on the other screen,
  so the run keeps a single alignment. Captions play on both.
- **Falling is not the end.** The run only ends when both of you are down. A
  fallen player is back on their feet, at half health, in the next room.
- **Nothing pauses.** Pausing the tree would freeze the synchronizers and
  desync the session, so online the world keeps turning while a menu, a gift
  card or a dialogue is open. `Net.set_paused` is the single place that knows
  this; call it instead of `get_tree().paused`.

## Duel rules

- Same body, same three hits, same roll. The one change is that the sword also
  bites players (`Player.versus`, which widens the hitbox mask to layer 2).
- First to three rounds. A round ends when somebody falls; both respawn at full
  health after a short break.
- The host owns the score, so a client cannot award itself a win.

## Testing it

```bash
tools/net_test.sh coop     # two processes: one hosts, one joins
tools/net_test.sh pvp
make net-test              # both modes, in Docker
```

The stand runs the real scenes over the real transport in two separate
processes and asserts what both of them see: bodies spawned on each side,
enemies replicated, movement mirrored, a client-dealt hit killing an enemy on
the host, the door opening for both, the room advancing, and — in a duel — a
blow crossing the wire and the host awarding the round.

## Adding to this

- A new replicated property on a body → add it to the `Net.attach_sync` list in
  that body's `_setup_net`, not to a `.tscn`.
- A new enemy attack that shows something → send its theatre as an RPC next to
  `_net_strike` / `_net_beam`, guarded by `if Net.active`.
- Anything that used `get_tree().paused` → `Net.set_paused`.
- Anything that used `get_tree().get_first_node_in_group("player")` → there may
  be two now; pick by `is_multiplayer_authority()`, or act on all of them.
