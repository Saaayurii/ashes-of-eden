# Releasing

Tag a version and CI does the rest:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

A tag with a hyphen — `v0.1.0-alpha.1`, `v0.2.0-beta.1` — is published as a **pre-release**.
`docs/releases/<tag>.md`, if it exists, is the release's text (the generated commit list follows).
Bump `application/config/version` in `project.godot` (shown in the main menu's corner) and the
Android `version/name` in `export_presets.cfg` before tagging.

That runs `.github/workflows/release.yml` (Windows, Linux, macOS, Web, attached to the GitHub
release) and `.github/workflows/mobile.yml` (Android, and iOS when it can be built). `pages.yml`
has already put the Web build at https://saaayurii.github.io/ashes-of-eden/ from `main`.

Everything below is about the part CI cannot do for you, because it needs a certificate that
belongs to a person or a company rather than to a repository.

## What ships unsigned, and what that costs the player

| Build | State | What the player sees |
|---|---|---|
| Web | fine as it is | nothing; a browser does not sign anything |
| Linux | fine as it is | nothing; Linux does not ask |
| Android | debug-signed | installs with `adb install -r`; Play refuses it |
| Windows | unsigned | SmartScreen: "Windows protected your PC", and a **More info → Run anyway** most people will not click |
| macOS | unsigned | Gatekeeper: "cannot be opened because the developer cannot be verified", and the only way in is right-click → Open, or a trip to System Settings |
| iOS | cannot be built at all | Godot refuses to export for iOS without an App Store Team ID |

None of this stops the game being open source and free. It stops the game being *easy to start*
for somebody who has not been told what to click, which on Windows and macOS is most people.

## macOS: Developer ID and notarization

**What it needs.** An Apple Developer account (99 USD a year) and a *Developer ID Application*
certificate from it. This is the same account iOS needs, so one purchase unblocks both.

**Secrets to add** (Settings → Secrets and variables → Actions):

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | the Developer ID Application `.p12`, base64: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | the password you set when exporting the `.p12` |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Your Name (ABCDE12345)` |
| `APPLE_ID` | the Apple ID the account belongs to |
| `APPLE_APP_PASSWORD` | an app-specific password from appleid.apple.com, **not** the account password |
| `APPLE_TEAM_ID` | the ten-character team id; also unblocks the iOS job |

With those present, the `sign-macos` job in `release.yml` signs the app with a hardened runtime,
sends it to Apple's notary service, waits for the ticket and staples it to the build. Without
them the job explains what is missing and does nothing, and the unsigned macOS zip ships as
before.

**Checking it worked**, on any Mac:

```bash
spctl -a -vvv -t install "Ashes of Eden.app"   # should say: accepted, source=Notarized Developer ID
```

## Windows: an Authenticode certificate

**What it needs.** A code-signing certificate from a CA. An OV certificate is roughly 200–400 USD
a year and still shows SmartScreen until the signature has built up reputation; an EV certificate
(600+ USD a year, and it arrives on a hardware token) clears SmartScreen immediately. The token is
the catch — a certificate on a USB key cannot be handed to a CI runner, so an EV certificate means
signing on your own machine or paying for a cloud signing service.

**Secrets to add**, for an OV certificate that exists as a file:

| Secret | What it is |
|---|---|
| `WINDOWS_CERTIFICATE` | the `.pfx`, base64 |
| `WINDOWS_CERTIFICATE_PASSWORD` | its password |

The `sign-windows` step uses [osslsigncode](https://github.com/mtrojnar/osslsigncode), which runs
on Linux, so it happens in the same job as the export. Timestamping is done against DigiCert's
public timestamp server, so the signature stays valid after the certificate expires.

**Checking it worked**, on Windows:

```powershell
Get-AuthenticodeSignature .\ashes-of-eden.exe | Format-List
```

## Android: a real upload key

The APK CI builds is signed with the debug keystore baked into the build image. Play will not take
it. For a store build:

```bash
keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep that file and its passwords somewhere you will still have them in five years — Play ties the
app to the key, and losing it means losing the ability to update. (Play App Signing softens this:
Google holds the app signing key and your upload key can be reset. Turn it on.)

Then add `ANDROID_KEYSTORE` (base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
`ANDROID_KEY_PASSWORD`, and the Android job will sign with them instead of the debug key.

## iOS

Blocked before signing even comes up: Godot will not export for iOS without an App Store Team ID.
See the comment at the top of `.github/workflows/mobile.yml`. Buy the Apple account, add
`APPLE_TEAM_ID`, and the job starts building; the same certificate secrets as macOS then take it
the rest of the way.

## The order that costs least

1. **Nothing.** Ship Web and Linux, and tell Windows and macOS players what they will see. This is
   where the project is now, and it is a legitimate place to be. Put the build somewhere people
   browse while you are there: [itch.io](ITCH.md) costs nothing, wants no developer account and no
   review, and takes both the browser build and the desktop zips. It is the only store on this page
   with no entry fee — the App Store's 99 USD a year and Google Play's 25 USD are not optional, and
   neither is waivable for an open-source or free game.
2. **99 USD.** The Apple account. It unblocks macOS notarization *and* iOS, which is two of the
   three problems for one price.
3. **Windows.** Only worth it once enough people are downloading the Windows build for SmartScreen
   to be costing you players — and worth measuring before paying for.
