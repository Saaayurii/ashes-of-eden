# Localization

Four target markets from day one: **English (en), Russian (ru), Ukrainian (uk), Simplified Chinese (zh_CN)**.

## How it works

- `localization/strings.csv`: `keys,en,ru,uk,zh_CN`. Godot imports it into one `.translation` per column (git-ignored).
- Code and scenes only ever use keys: `text = "MENU_PLAY"` in a scene, `tr("HUD_WAVE") % wave` in code.
- The language is chosen in the main menu and saved to `user://settings.cfg`. On first launch it follows the OS locale.

## Rules for translators

1. Never leave a cell empty — `make validate` fails on empty cells. Copy the English text if unsure.
2. Wrap a cell in double quotes if it contains a comma or a quote; double the inner quotes (`""`).
3. Keep `%d` / `%s` placeholders exactly as in English.
4. Chinese: use full-width punctuation（，。？！）and no spaces around it.
5. Ukrainian and Russian differ in tone, not only in words. Do not machine-translate one from the other.
6. Names are not translated literally: *Elian / Элиан / Еліан / 埃利安*. Check `SPEAKER_*` keys for the canonical forms.

## Fonts

`assets/ui/theme.tres` builds one fallback chain, both faces SIL OFL and both with full Latin + Cyrillic:

- **Forum** (`assets/fonts/Forum-Regular.ttf`) — display face: buttons, and any Label with
  `theme_type_variation = &"TitleLabel"`.
- **EB Garamond** (`assets/fonts/EBGaramond-Variable.ttf`) — the theme's `default_font`, i.e. everything else.
- A `SystemFont` of CJK families closes the chain, which is what renders zh_CN today.

Neither face covers CJK, and the **Web build has no system fonts** — before the first Web/zh release add a
CJK font file under `assets/fonts/`, put it in the chain in place of the `SystemFont`, and credit it in
`assets/CREDITS.md`. Glyphs outside the two faces (`✚` was one) fall through to that system font, so keep
UI symbols to what EB Garamond has: `† · × → • ◆ §`.

## Adding a fifth language

Add a column to the CSV, the code to `Settings.LOCALES`, the native name to `MainMenu.NATIVE_NAMES`,
the locale to `LOCALES` in `scripts/tools/validate_data.gd`, and the generated `.translation` path to
`project.godot` → `internationalization/locale/translations`.
