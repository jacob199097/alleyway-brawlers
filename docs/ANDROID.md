# The Android version

The same game as on PC, exported for Android phones and tablets. It plays online against Windows
and Mac players (the server runs every match, deck and reward), signs in with the same accounts and
downloads new cards, card backs and sounds at start-up like the PC game.

## Building it

```
node tools/build_android.mjs <path to Godot console exe>            # release APK, signed with the release key
node tools/build_android.mjs <path to Godot console exe> --debug    # debug APK (also runs in the emulator)
```

It writes `builds/AlleywayBrawlers-<version>-android.apk` (about 200 MB), and a release build also
writes `builds/android_<version>/AlleywayBrawlers.pck`: the same files as a pack, which Android
patches are made against (keep it while that version is the Android `patchBase`). The APK is exported from a
copy of the project, `builds/android_project/`, where the pictures are set lighter for phones: card
art at most 1024 pixels tall and lossy, `.jpg` backgrounds lossy, other pictures at most 1024 wide
(the PC build's pictures would make a 900 MB APK). `godot/` and the PC builds are never touched. The
first build copies `godot/.godot`; after that a build only imports what changed (about a minute).

Version: the APK's version name is `config/version` from `godot/project.godot`, and its version code
(which Android uses to tell newer from older) is made from it: 0.9.137 is 9137, 1.0.0 is 1000000.

## Putting it on the server and a phone

```
node tools/deploy.mjs --build-android
```

copies the APK into `downloads/` on the server (older APKs are deleted). Then on the phone, open
**https://alleywaybrawlers.duckdns.org/download/android** in the browser (or just `/download`: an
Android browser gets the APK), and open the downloaded file. The first time, Android asks to allow
installing apps from the browser ("Install unknown apps"); allow it for that browser.

With the phone plugged into the PC (USB debugging on, in the phone's Developer options):

```
C:\Users\jacob\Android\Sdk\platform-tools\adb.exe install -r builds\AlleywayBrawlers-<version>-android.apk
```

## Updates

Like Windows and Mac, Android gets small in-place patches (since 0.9.138). With each new version:

```
node tools/make_patch.mjs <path to Godot console exe> --android
```

brings `builds/android_project/` up to date and writes `builds/AlleywayBrawlers-<version>-patch-android.pck`
(only what changed since the APK at `"android": {"patchBase"}` in `shared/game_version.json`, compared
against `builds/android_<patchBase>/AlleywayBrawlers.pck`). `node tools/deploy.mjs --patch` copies it
with the Windows and Mac ones. The game downloads it at start-up and restarts itself into it
(`scripts/patcher.gd`: on Android the app relaunches; if a phone won't allow that, it closes and the
patch loads the next time it's opened).

A patch can't change project settings (the APK's manifest: name, icon, orientation, permissions) or
add autoloads or `class_name` scripts. Those need a new APK: build it, set the Android `patchBase` to
its version, deploy it with `--build-android`, and raise `minimum` if older APKs must update (they see
"UPDATE REQUIRED", and DOWNLOAD opens `/download/android`, or `CLIENT_DOWNLOAD_URL_ANDROID` from the
server's `.env`). New cards, art and sounds need neither: the game downloads them itself.

## Touch controls

`godot/scripts/touch.gd` turns fingers into the mouse, so screens need no touch code:

| Gesture | Does |
|---|---|
| Tap | click |
| Drag | drag (play a card from your hand, sliders, scroll lists) |
| Hold a finger still (½ s) | right-click: zoom in on a card; in a duel, on nothing, cancel |
| Pinch | zoom the turf map |
| Back button | Esc (back, cancel, the duel's menu) |

A finger is wider than most buttons: a tap that lands just beside one (within 34 pixels of the game,
on a panel or the empty board) presses it. A tap on anything that takes taps itself (a card, a card
tile, a text box) stays where it is. Hints written for the mouse ("Hover a card…", "right-click to
cancel") say tap and hold on a phone (`UI.touch_words`).

A finger going down moves the pointer there straight away (the duel's card panel shows the card);
what it does is decided when it lifts, moves or is held. On a PC, `-- --touch` switches it on
(fake fingers: `godot --headless --path godot res://tests/touch_smoke.tscn -- --touch`), and
`-- --mobile` makes the game act as on a phone (`Game.mobile()`: no Display tab, no window settings, the
layout below). Test both: `touch_smoke.tscn -- --touch --mobile` (headless) is the phone-shaped run.

## The screen

The game is landscape only (`window/handheld/orientation` in `project.godot`, and set again at start-up).
Every screen is laid out on a 1920×1080 frame; a phone is wider (20:9) and a tablet taller (4:3). So
on mobile there are no black bars: `scripts/widescreen.gd` lets the view grow to fill the screen, keeps
the frame in its middle (`Game.wide.margin`), and stretches full-screen backgrounds, dimmers and fades
to the edges. Things that sit at the frame's edge use the screen's instead (the chat tab, message
pop-ups). In a duel the side columns move out into the extra room on a wide phone: the card panel
(wider, with a smaller picture and bigger text) and the player plate to the left, the rival, phases
and turn to the right. Small print (under 20 points) is 3 points bigger on a phone.
To look at it on a PC: `godot --path godot --resolution 1200x540 res://tests/screens_tour.tscn -- <out dir> --phone --mobile`
(against the mock server, `node godot/tests/mock_server.mjs`).

## Set up on this PC (done once, 2026-11-10)

- **JDK 17:** `C:\Users\jacob\Android\jdk-17.0.21.0.2+1` (Microsoft OpenJDK).
- **Android SDK:** `C:\Users\jacob\Android\Sdk` (command-line tools, platform-tools, build-tools
  35.0.1, platform android-35). More with `Sdk\cmdline-tools\latest\bin\sdkmanager.bat`.
- **Godot's Android templates:** `android_debug.apk`, `android_release.apk`, `android_source.zip` in
  `%APPDATA%\Godot\export_templates\4.7.2.stable\` (from Godot's 4.7.2 export templates .tpz). A new
  Godot version needs its own.
- **Godot editor settings** (`%APPDATA%\Godot\editor_settings-4.7.tres`): `export/android/java_sdk_path`
  and `export/android/android_sdk_path` point at the two folders above; the debug key is Godot's
  usual `%APPDATA%\Godot\keystores\debug.keystore`.
- **The emulator** is installed (`Sdk\emulator`, image android-35 x86_64) but needs Windows
  Hypervisor Platform switched on to run (Windows Features, as administrator, then restart).

## The release key

`C:\Users\jacob\Android\alleyway-release.keystore` signs release APKs; its password and alias are in
`C:\Users\jacob\Android\release-keystore.json` (the build reads it; or set `ANDROID_KEYSTORE`,
`ANDROID_KEYSTORE_PASS`, `ANDROID_KEYSTORE_ALIAS`). **Back both files up somewhere safe and never put
them in git.** A phone only installs an update signed with the same key as the game it has: lose the
key and every player has to uninstall (losing nothing on the server, but it's a bad day). On Google
Play this key becomes the "upload key" and Google keeps the app signing key.

## Still to do

- **Phone-sized screens.** The layout is still the PC's, scaled to the screen's height: text is
  bigger than it was, but small on a small phone. Further: layouts made for phones (the duel's hand
  and buttons bigger), or a text size setting.
- **Google Play:** a developer account ($25 once), an Android App Bundle (`.aab`, Godot's Gradle
  build) instead of an APK, the store listing, the Data safety form (what `backend/routes/legal.js`
  says the server stores), and Google Play Billing for Contraband (Google requires its own billing
  for in-game purchases bought in a Play Store app: GodotGooglePlayBilling plugin, and the server
  checking purchase tokens like it does Steam's).
- **iPhone / iPad:** needs a Mac to build and an Apple Developer account ($99 a year).
