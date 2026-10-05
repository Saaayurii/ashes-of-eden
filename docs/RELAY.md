# Playing together from anywhere — the relay

What people install ZeroTier, Radmin VPN or Hamachi for — two players on
different networks, behind routers that never forwarded a port, in one game —
done inside the game. One player presses **Create game** and reads out a code
(`PF7-Z3V`); the other types it into **Join**. That is all.

It works between every build we ship, in any pairing: Windows, Linux, macOS,
Android, iOS and a browser tab. A browser can even *host* this way, which it
cannot do any other way (a page cannot listen for connections).

## How it works

```
 player A ──wss──▶ ┌───────┐ ◀──wss── player B
 (host)            │ relay │           (guest)
                   └───────┘
```

Both players dial **out** to the relay over a WebSocket, which every network
lets through and every build of Godot speaks. The relay keeps rooms by code
and pumps bytes between a room's host and its guests. It never reads a game
packet, simulates nothing, stores nothing — the host still owns the world
exactly as in docs/MULTIPLAYER.md.

| Piece | File |
|---|---|
| The wire: frame types, codes, reasons | `scripts/net/relay_protocol.gd` |
| A `MultiplayerPeer` whose wire is a relay room (RPCs and synchronizers run over it unchanged) | `scripts/net/relay_peer.gd` |
| The host on two wires at once: the local server *and* the relay room | `scripts/net/host_peer.gd` |
| The relay itself — headless Godot, the same binary as the dedicated host | `scripts/net/relay_server.gd` |
| "Games on this network": a UDP shout once a second, heard by the Join screen | `scripts/net/lan_beacon.gd` |
| Link quality, "connection unstable", "connection lost" | `Net._measure`, `scripts/ui/net_overlay.gd` |

**Codes** are six characters from an alphabet with no look-alikes (no 0/O,
1/I/L, 5/S, 8/B), shown as `ABC-DEF`; case, spaces and the dash are forgiven.
A host that loses the relay asks for its old code back when it reconnects.

**Three ways in, one screen.** A host listens locally *and* holds a relay
room (HostPeer), so a friend on the same Wi-Fi connects straight in — listed
under "Games on this network", no typing — while a friend elsewhere uses the
code. The Join field takes a code or an address; an address still connects
directly, as before.

## The link, on screen

`Net` pings whoever it watches once a second (a guest the host, a host each
guest) and keeps the round trip.

- **Top centre**: three bars and the round trip in ms — green under 100 ms,
  amber under 200, red above.
- **"Connection unstable — waiting for Roman… 4 s"** once the other side has
  been silent for `Net.LINK_STALL` (2.5 s), counting up.
- **"Connection lost"** with the reason, over the menu, when a match ends
  because the wire did: the host left, the relay went, or `Net.LINK_TIMEOUT`
  (15 s) of silence. A host lets a silent guest go after the same time and
  plays on, with "<name> left the game".
- A guest on another version of the game is turned away with that reason
  rather than desyncing on the first room.

## Running a relay

The relay is the one piece that has to live on a machine with a public
address. It is light — a room is two sockets and a byte pump — so the smallest
VPS carries hundreds of rooms. Anything that runs Docker will do.

```bash
# on the server, with a domain pointed at it (A record)
git clone https://github.com/Saaayurii/ashes-of-eden && cd ashes-of-eden
RELAY_DOMAIN=relay.example.com docker compose -f tools/relay/docker-compose.yml up -d --build
```

That starts the relay and Caddy in front of it; Caddy gets and renews the TLS
certificate itself. Then set the URL the builds use, in `project.godot`:

```ini
[ashes]
network/relay_url="wss://relay.example.com"
```

and push: every build from then on offers codes. Until a URL is set, the
screen says codes need a relay and offers the Wi-Fi and the typed address.

`wss://` (TLS) is not optional for the Web build: a page served over https
may not open a plain `ws://` socket. Desktop and mobile builds would accept
`ws://`, but one URL for everyone is simpler.

Locally, for trying it out:

```bash
make relay                                                     # ws://localhost:8920
godot --path . -- --relay-url=ws://127.0.0.1:8920              # two copies of the game
```

Limits (`RelayServer`): 512 rooms, 4 rooms per address, 3 guests a room (Net
itself seats two players), 1 MB a frame; a socket that has not said hello in
10 s is closed.

## Testing it

```bash
godot --headless -s scripts/tools/relay_test.gd    # codes, routing, refusals, kick, host leaving, HostPeer, LanBeacon
tools/net_test.sh coop-relay                        # the real game over the relay: relay + host + guest by code
tools/net_test.sh pvp-relay
```

Both run in CI (`make test`, `make net-test`).

## Not done (yet)

- **Direct peer-to-peer through NAT** (WebRTC with STUN). It would take the
  relay out of the path once two players have found each other, for a few
  milliseconds less. It needs the webrtc-native extension on every desktop
  and mobile build; the relay works today without it.
- **UPnP** (Godot's `UPNP`): asking the host's router to open the port, for a
  direct link with no relay at all. Many routers refuse, and carrier-grade NAT
  makes it moot; the relay covers both.
