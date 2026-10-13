# Dialogue looks

Where a dialogue's windows stand, what they look like, and whose face is shown
beside the words. Read by `scripts/ui/dialogue_look.gd` (`DialogueLook`), laid on
by `DialogueBox._dress`, edited in the art studio's «Диалоги» tab.

## The file: `data/dialogue_looks.json`

```json
{
  "styles": {
    "default": {},
    "ember": {"bg": "#1a0d0ae6", "border": "#c2562aff", "border_width": 1, "radius": 4,
              "speaker": "#ff9a4dff", "text": "#f2ddd0ff", "caption": "#ffcf9eff",
              "portrait_bg": "#1a0d0ae6", "portrait_border": "#c2562aff"}
  },
  "speakers": {"NPC_NUN": "res://assets/portraits/nun.png"}
}
```

- **styles** — named looks. A key left out keeps the game's own theme, so
  `default` is `{}` and must exist. Colours are `#rrggbbaa`: `bg`, `border`,
  `speaker`, `text`, `caption`, `portrait_bg`, `portrait_border`. Numbers:
  `border_width` 0–4, `radius` 0–12, `speaker_size` 8–24, `text_size` 10–28,
  `caption_size` 9–24. A style may carry a `name` for the studio.
- **speakers** — a speaker key → its portrait. Without an entry the portrait is
  the `avatar` of the NPC in `data/npcs` whose `name` is that key; a speaker with
  neither has no portrait window.

## On a dialogue and on a line

A dialogue may carry `"look"`, and any node may carry its own, laid over the
dialogue's key by key (`DialogueLook.merged`):

| key        | value              | meaning |
|------------|--------------------|---------|
| `style`    | style id           | colours and sizes |
| `panel`    | `[x, y, w, h]`     | the bottom panel (≥ 120×48) |
| `caption`  | `[x, y, w]`        | the captions of a non-blocking dialogue (w ≥ 80) |
| `portrait` | `[x, y, size]` / `false` | the portrait window, a square 24–160; `false` hides it for a line |
| `face`     | `res://…png`       | another picture for this line (a frown, a smile) |

Rectangles are in 640×360 pixels — the game's base — and stretch with the
window; a portrait stays square. The validator refuses an unknown style, a
missing picture, a rectangle off the screen or below its minimum.

A dialogue with no look keeps the scene's own layout exactly; the box puts
every window back (`_home`, `_home_paint`) before the next one plays, and the
game's own announcements never take a look. Bubbles over heads keep to the
heads: only a style's colours reach them, and no portrait is shown beside them.

## In the studio

«Диалоги» draws the panel, the caption and the portrait window over the
640×360 frame. Drag a window to move it, drag its corner to size it (Shift
snaps to 4 px); the card above chooses whether the drag writes the whole
dialogue's look or this line's. Styles are made, copied and edited in the same
card; each speaker's portrait is picked from `assets/portraits` or uploaded
(saved as `assets/portraits/<name>_studio.png`). Sending writes
`data/dialogue_looks.json` merged with whatever changed on the other side.
«Катсцены» draws a dialogue step through the same code.

`dialogue_look_test.gd` checks the box; `tools/studio/tests/lib.test.js` the
studio's reading and writing of the file.
