# The Android version

The same game as on PC, exported for Android phones and tablets. It plays online against Windows
and Mac players (the server runs every match, deck and reward), signs in with the same accounts and
downloads new cards, card backs and sounds at start-up like the PC game.

## Building it

```
node tools/build_android.mjs <path to Godot console exe>            # release APK, signed with the release key
node tools/build_android.mjs <path to Godot console exe> --debug    # debug APK (also runs in the emulator)
```

It writes `builds/AlleywayBrawlers-<version>-android.apk` (about 200 MB). The APK is exported from a
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

There are no in-place patches on Android yet: a version with code changes is a new APK. When
`minimum` in `shared/game_version.json` goes up, Android players see "UPDATE REQUIRED" and the
DOWNLOAD button opens `/download/android` (or `CLIENT_DOWNLOAD_URL_ANDROID` from the server's
`.env`). So when you raise `minimum`, build and deploy a new APK too. New cards, art and sounds need
no new APK.

## Touch controls

`godot/scripts/touch.gd` turns fingers into the mouse, so screens need no touch code:

| Gesture | Does |
|---|---|
| Tap | click |
| Drag | drag (play a card from your hand, sliders, scroll lists) |
| Hold a finger still (½ s) | right-click: zoom in on a card; in a duel, on nothing, cancel |
| Pinch | zoom the turf map |
| Back button | Esc (back, cancel, the duel's menu) |

A finger going down moves the pointer there straight away (the duel's card panel shows the card);
what it does is decided when it lifts, moves or is held. On a PC, `-- --touch` switches it on
(fake fingers: `godot --headless --path godot res://tests/touch_smoke.tscn -- --touch`), and
`-- --mobile` makes the game act as on a phone (`Game.mobile()`: no Display tab, no window settings).

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

- **Phone-sized screens.** Every screen is laid out for 1920×1080 and shrinks to fit, so on a phone
  the small print is small (tablets are fine). Next: bigger text and buttons where it matters most
  (the duel's hand and card panel, menus' small labels), maybe a text size setting.
  On 20:9 phones the game has black bars at the sides (the layout is 16:9).
- **Google Play:** a developer account ($25 once), an Android App Bundle (`.aab`, Godot's Gradle
  build) instead of an APK, the store listing, the Data safety form (what `backend/routes/legal.js`
  says the server stores), and Google Play Billing for Contraband (Google requires its own billing
  for in-game purchases bought in a Play Store app: GodotGooglePlayBilling plugin, and the server
  checking purchase tokens like it does Steam's).
- **In-place updates (patches) for Android**, like the Mac ones, so a code update doesn't need a
  new APK.
- **iPhone / iPad:** needs a Mac to build and an Apple Developer account ($99 a year).
