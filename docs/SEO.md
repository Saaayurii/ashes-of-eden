# The web page and search engines

The playable build lives at <https://saaayurii.github.io/ashes-of-eden/>
(`.github/workflows/pages.yml`). What a crawler or a link preview reads there:

- **The page itself** — `tools/web/shell.template.html` → `tools/web/shell.html`
  (`python3 tools/art/make_web_gate.py`): title, description, keywords,
  `canonical`, Open Graph and Twitter cards (`og.jpg`), a `VideoGame` JSON-LD
  block with screenshots, and a short visible paragraph in English and Russian
  under the Play button, so the gate has words a search engine can index
  before anyone presses anything.
- **The files beside it** — `tools/web/site/`, written by
  `python3 tools/web/make_site.py` and copied into the build by the Pages
  workflow: `robots.txt`, `sitemap.xml` (with image entries), `og.jpg`,
  `screens/*.webp`, icons and `manifest.webmanifest`.

`python3 tools/web/check_shell.py` fails if the canonical link, the JSON-LD,
the full-screen button or any of the site files goes missing.

## Registering (once, by hand)

**Google Search Console** — <https://search.google.com/search-console>
1. Add property → **URL prefix** → `https://saaayurii.github.io/ashes-of-eden/`
   (a *Domain* property needs DNS, which github.io does not give you).
2. Verify with **HTML tag**: copy the `content` value into
   `<meta name="google-site-verification" content="">` in
   `tools/web/shell.template.html`, run `make_web_gate.py`, push, wait for the
   Pages deploy, press Verify. (Or choose **HTML file** and drop the
   `googleXXXX.html` it gives you into `tools/web/site/`.)
3. Sitemaps → submit `sitemap.xml`. URL inspection → Request indexing.

**Yandex Webmaster** — <https://webmaster.yandex.ru>
1. Add site `https://saaayurii.github.io/ashes-of-eden/`.
2. Verify by **meta tag** (`yandex-verification`, same place as Google's) or
   by **HTML file** (`yandex_XXXX.html` into `tools/web/site/`).
3. Indexing → Sitemap files → add
   `https://saaayurii.github.io/ashes-of-eden/sitemap.xml`; Reindex pages →
   the home URL.

## Things worth knowing

- **robots.txt here is a courtesy.** Crawlers read it only at the root of a
  host (`https://saaayurii.github.io/robots.txt`), which belongs to the
  `saaayurii.github.io` repository, not this one. Nothing is disallowed, so it
  does not matter; the sitemap is submitted to both consoles directly instead.
  If that root repository is ever made, give it a robots.txt with
  `Sitemap: https://saaayurii.github.io/ashes-of-eden/sitemap.xml`.
- A **custom domain** (Pages → Settings → Custom domain) would make a Domain
  property and a real robots.txt possible; then change the URL in
  `make_site.py` and in the template (canonical, og:url, JSON-LD) together.
- Most of the page is a canvas; search engines index the words around it, not
  the game. Links from the README, itch.io and store pages to the play URL do
  more for ranking than any tag here.
- Link previews (Telegram, VK, Discord) cache `og.jpg` per URL; after changing
  it, Telegram's @WebpageBot and VK's link checker refresh their copy.

## Full screen

Play asks the browser for full screen (a gesture is the only time it may),
locks landscape on a phone and lets Chrome keep Esc for the pause menu
(`navigator.keyboard.lock`). The corner button asks again after Esc or a tab
switch; it fades over the game and is gone while the page fills the screen.
An iPhone's Safari has no full screen for a page: the button explains
Share → Add to Home Screen, and `manifest.webmanifest` /
`apple-mobile-web-app-capable` make the home-screen icon open the game with no
browser around it.
