# Waiting at a locked room exit

`Door` previously handled only `body_entered`. A player standing inside a
locked exit when the last enemy died never produced another entry event;
they had to walk out and back in after the gate opened.

Opening now schedules an overlap check after room listeners are connected.
It uses the same entry handler as walking into an already open door. A
one-shot latch suppresses duplicate overlap events and repeated `open=true`
assignments; closing the door resets that latch. Teleported stale entries
are still rejected by the existing distance check. Dead players cannot
trigger an exit.

No room geometry, gate position, painting, dialogue or localization changes.
This applies to painted and constructed doors, not just the hell arena.

## Verification

`door_waiting_test.gd` exercises hell_gate, village_night and crypt_lava: waiting while
locked, unlocking in place, repeated notifications, closing/reopening,
stale entry after teleport and dead-player rejection. Each live entry emits
exactly one transition. The run lifecycle regression also passes. These
headless harnesses retain resource cleanup warnings at shutdown.

```sh
godot --headless --fixed-fps 60 --path . -s scripts/tools/door_waiting_test.gd
godot --headless --fixed-fps 60 --path . -s scripts/tools/run_lifecycle_test.gd
godot --headless --fixed-fps 60 --path . -s scripts/tools/reach_test.gd -- hell_gate props reverse no_mantle all_surfaces
```
