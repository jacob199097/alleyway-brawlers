# Steam

The game is ready for Steam, running against Valve's test app **Spacewar (App ID 480)** until
AlleyWay Brawlers has its own. What's built:

- **GodotSteam** (`godot/addons/godotsteam`, the GDExtension plugin 4.23.2 for Windows, Mac and Linux) and
  `godot/scripts/steam.gd` (`Game.steam`). Steam only switches on in the **Steam build** (the "Windows Steam"
  export preset adds the feature `steam`) or when the game is started with `--steam`. Everywhere else
  (the download from the server, the Mac build, older installs updated by patches) it does nothing.
- **Sign-in:** the Steam build signs the player in with their Steam account (a ticket the server checks
  with Valve: `backend/routes/steam.js`, `backend/utils/steam.js`). A Steam account with no player gets
  "CONTINUE WITH STEAM" (a new player, named after their Steam name); an email player signs in with email
  once in the Steam build, which links Steam to their account (or Settings → Account → LINK STEAM ACCOUNT).
  Steam players have no email or password: they delete their account by typing DELETE.
- **Achievements:** every one the game unlocks is unlocked on Steam too (and old ones are caught up at
  sign-in), as long as Steamworks has an achievement with the same API name.
- **Purchases:** Contraband through the Steam wallet (Valve requires it in Steam games): the server opens
  the order (InitTxn), Steam shows it in the overlay, and once the player approves the server completes it
  (FinalizeTxn) and adds the Contraband once.
- **Updates:** Steam updates the Steam build, so it has no in-game patches or download prompts.
- **Steam Deck:** the on-screen keyboard comes up for text boxes; controller support was already there.

## What you need to do

1. **Steamworks:** sign up at partner.steamgames.com and pay the Steam Direct fee ($100 per game).
   Create the app: you get an **App ID**, and a depot (usually App ID + 1).
2. **App ID in the game:** `APP_ID` in `godot/scripts/steam.gd` (and nothing else in the game).
3. **Server** (`backend/.env` on the server, then `node tools/deploy.mjs`):
   ```
   STEAM_APP_ID=<App ID>
   STEAM_PUBLISHER_KEY=<Steamworks → Users & Permissions → Manage Groups → Web API key>
   STEAM_MTX_SANDBOX=true        # Steam's sandbox: no money moves. "false" at launch.
   ```
   Before then, a normal **Steam Web API key** (steamcommunity.com/dev/apikey) as `STEAM_WEB_API_KEY`
   is enough to test sign-in with App ID 480 (not purchases).
4. **Achievements:** Steamworks → Stats & Achievements. Add one per line of
   `node tools/steam_achievements.mjs` (API name = the first column; `--csv` gives a file), with an icon,
   and publish. Each new clan adds two.
5. **Purchases:** Steamworks → enable Microtransactions for the app. Prices are in US dollars
   (`CONTRABAND_BUNDLES` in `backend/routes/shop.js`); Steam shows the player their own currency.
6. **Build and upload:** install steamcmd, then
   ```
   node tools/steam_build.mjs <Godot console exe> --upload        (STEAM_BUILD_USER=<your Steam login>)
   ```
   It exports `builds/steam/windows/`, writes the SteamPipe scripts and uploads; `--live` also puts it on
   the "beta" branch. Set the default branch live in Steamworks (Builds) when you're ready.
7. **Friends before launch:** Steamworks → Request Steam keys gives free keys: anyone with one can install
   it from Steam before the store page is public.

## Testing here (no App ID yet)

With Steam open on this PC: start the game with `--steam` (e.g. from the editor, or
`AlleywayBrawlers.exe --steam`). It runs as Spacewar; sign-in works once the server has
`STEAM_WEB_API_KEY` (step 3). `godot/tests/mock_server.mjs` has the Steam routes too (any real ticket
is accepted there).
