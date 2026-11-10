# Obby Parkour (Roblox + Rojo)

An obby (obstacle course) with 10 levels, checkpoints, a completion timer,
coins and a global coin leaderboard.

- All code is in this repository (Luau), synced into Roblox Studio with **Rojo**.
- You build the **map** by hand in Studio and mark special parts with **tags**.
- Every push to `main` builds the game and **publishes it to Roblox** with GitHub Actions.

---

## Contents

1. [How the project is organized](#1-how-the-project-is-organized)
2. [Install Rojo and the Studio plugin](#2-install-rojo-and-the-studio-plugin)
3. [Create the experience and find UNIVERSE_ID and PLACE_ID](#3-create-the-experience-and-find-universe_id-and-place_id)
4. [Work in Studio with `rojo serve`](#4-work-in-studio-with-rojo-serve)
5. [Build the map and tag parts](#5-build-the-map-and-tag-parts)
6. [Enable Studio Access to API Services (DataStore)](#6-enable-studio-access-to-api-services-datastore)
7. [Save the map into the repository](#7-save-the-map-into-the-repository)
8. [Create an Open Cloud API key](#8-create-an-open-cloud-api-key)
9. [Add the GitHub secrets and deploy](#9-add-the-github-secrets-and-deploy)
10. [Tuning the game](#10-tuning-the-game)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. How the project is organized

```
default.project.json   Rojo project used while developing (rojo serve)
deploy.project.json    Same, plus the map (used by GitHub Actions)
aftman.toml            Pinned tool versions (Rojo)
map/Map.rbxm           Your map, saved from Studio (you create this, step 7)
src/
  server/              -> ServerScriptService.Server   (all important logic)
    Main.server.luau      starts everything, handles client requests
    Services/
      PlayerData.luau     DataStore load/save, leaderstats, HUD state
      Checkpoints.luau    stages, respawning, run timer, finish + reward
      Coins.luau          coin pickups
      Hazards.luau        kill parts
      Leaderboard.luau    global top-coins list (OrderedDataStore)
    Lib/                  touch validation, rate limiter, tag helper
  client/              -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau      builds the UI and listens to the server
    UI/                   HUD, leaderboard panel, theme
    CoinSpin.luau         visual coin rotation (client only)
  shared/              -> ReplicatedStorage.Shared
    Config.luau           ALL gameplay numbers and tag names
    Remotes.luau          list of RemoteEvents
    Format.luau           time/number formatting
  gui/                 -> StarterGui
    ObbyHUD.model.json    empty ScreenGui; the client fills it from code
.github/workflows/deploy.yml   build + publish on push to main
```

### Security model (anti-exploit)

Exploiters can run any code on their own client, so:

- Coins, stages, the timer, rewards and saving are decided **only on the server**.
- The client can only send two requests: `RequestSync` (send me my state) and
  `RequestReset` (restart from level 1). Both take no arguments and are rate limited.
- Every touch is checked on the server: it must be a living player, standing near the part.
- Checkpoints must be reached **in order**, not faster than `MinSecondsPerStage` apart.
- A full run faster than `MinRunTime` seconds is rejected.
- If loading saved data fails, the game does **not** save that session, so real
  progress is never overwritten with empty data.

---

## 2. Install Rojo and the Studio plugin

Rojo copies the files from this repository into Roblox Studio while you work.

### 2.1 Install Rokit (a tool manager)

Rokit installs the exact Rojo version this project uses (from `aftman.toml`).

- **Windows:** download the latest `rokit-...-windows-x86_64.zip` from
  <https://github.com/rojo-rbx/rokit/releases>, unzip it, open a terminal in that
  folder and run:
  ```bash
  ./rokit.exe self-install
  ```
- **macOS / Linux:**
  ```bash
  curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
  ```

Close and reopen your terminal afterwards.

### 2.2 Install Rojo

Open a terminal **in this repository folder** and run:

```bash
rokit install
```

Answer "yes" if it asks whether to trust `rojo-rbx/rojo`. Check it worked:

```bash
rojo --version
```

It should print `Rojo 7.4.4`.

### 2.3 Install the Rojo plugin in Roblox Studio

Close Studio, then run:

```bash
rojo plugin install
```

Open Studio again: you will see a **Rojo** button on the **Plugins** tab.

> Optional: in VS Code, install the extensions **Rojo – Roblox Studio Sync**
> and **Luau Language Server** for autocomplete.

---

## 3. Create the experience and find UNIVERSE_ID and PLACE_ID

1. Open Roblox Studio and create a new **Baseplate** place.
2. **File → Publish to Roblox As...** → **Create new experience**, give it a name, click **Create**.
3. Go to <https://create.roblox.com/dashboard/creations> and find your experience.
4. **UNIVERSE_ID:** click the **...** on the experience card → **Copy Universe ID**.
5. **PLACE_ID:** open the experience → in the left menu choose **Places** →
   click **...** on the start place → **Copy Place ID**.
   (The Place ID is also the number in the game URL:
   `roblox.com/games/<PLACE_ID>/...`.)

Write both numbers down; you need them in step 9.

> The experience is private at first. To let others play, open the experience
> on the dashboard and set it to **Public** when you are ready.

---

## 4. Work in Studio with `rojo serve`

1. Open the place from step 3 in Studio.
2. In a terminal in this repository folder run:
   ```bash
   rojo serve
   ```
3. In Studio: **Plugins → Rojo → Connect**.

Now every time you save a file in `src/`, the change appears in Studio
immediately. Rojo only manages these places in Studio:

| Studio location | Folder |
| --- | --- |
| `ServerScriptService.Server` | `src/server` |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client` |
| `ReplicatedStorage.Shared` | `src/shared` |
| `StarterGui` | `src/gui` |

**Do not edit scripts in Studio**: Rojo syncs one way (files → Studio), and
changes made in Studio are overwritten. Edit the files in this repository instead.
`Workspace` is **not** managed by Rojo during `rojo serve`, so your map is safe there.

Press **Play** in Studio to test. Stop `rojo serve` with `Ctrl+C` when done.

---

## 5. Build the map and tag parts

Build the course in Studio from normal Parts. Put everything inside **one Folder
named `Map`** in `Workspace` (needed for step 7).

### Tags

The scripts find special parts by **tag** (CollectionService). To add a tag:
select the part → **Properties** window → scroll to **Tags** → click **+** →
type the tag name exactly (it is case-sensitive). Tags must be on a **Part**
(or MeshPart, Wedge...), not on a Model or Folder.

| Tag | What it does | Extra setup |
| --- | --- | --- |
| `Checkpoint` | Saves progress when touched. Players respawn on the last checkpoint they reached. | **Required** number attribute `Stage` (see below). |
| `Finish` | End of the obby. Stops the timer, gives `FinishReward` coins, counts a win, saves the best time, then sends the player back to the start. | Only works after the highest `Stage` checkpoint was reached. |
| `Coin` | Gives coins when touched, disappears for `CoinRespawnTime` seconds. Spins (visual only). | Optional number attribute `Value` (coins per pickup, default 1). Optional boolean attribute `Spin` = false to stop spinning. Make it **Anchored** and **CanCollide = off**. |
| `KillPart` | Kills the player on touch (lava, spikes, lasers). They respawn on their checkpoint. | None. |

### Adding the `Stage` attribute to checkpoints

Select the checkpoint part → **Properties** → bottom → **Attributes** →
**+ Add Attribute** → Name: `Stage`, Type: **Number** → set the value.

Number the checkpoints **0, 1, 2, 3...** with no gaps and no duplicates:

| Part | Tag | Stage |
| --- | --- | --- |
| Start platform (players spawn here, timer starts) | `Checkpoint` | `0` |
| End of level 1 / start of level 2 | `Checkpoint` | `1` |
| ... | `Checkpoint` | ... |
| End of level 9 / start of level 10 | `Checkpoint` | `9` |
| End of level 10 | `Finish` | – |

That gives 10 levels. Use more or fewer checkpoints and the HUD adapts
automatically ("Level X / N").

Tips:
- Make checkpoints and the finish **Anchored**, large flat pads (e.g. 12 × 1 × 12).
- Also anchor all obby parts, or they will fall.
- Put a `SpawnLocation` on the start platform as a backup spawn.
- Mistakes in tags/attributes are printed in the **Output** window when you press Play
  (look for `[Checkpoints]` warnings).

### Timer rules

- The timer starts when a player spawns on Stage 0 (joining, restarting, or dying before checkpoint 1).
- Dying later does not stop the timer: you respawn on your checkpoint.
- A player who rejoins in the middle of the course continues from their saved
  checkpoint, but that run is "Not timed" (still gets the finish reward).
- The **Restart obby** button (bottom-left, click twice) sends you back to level 1
  with a fresh timer.

---

## 6. Enable Studio Access to API Services (DataStore)

DataStores (saving) do not work in Studio until you enable this:

1. The place must be **published** (step 3).
2. In Studio: **File → Game Settings → Security**.
3. Turn on **Enable Studio Access to API Services**.
4. Click **Save**.

If it is off, the game still runs, but the HUD shows
"Progress is not being saved" and the Output shows DataStore warnings.
Saving always works in the live game.

Note: Studio tests use the **real** saved data of your account in this experience.

---

## 7. Save the map into the repository

GitHub Actions builds the game from this repository, so it needs your map too.
**Without `map/Map.rbxm` the deploy workflow stops on purpose** (otherwise it
would publish a place with no map and replace your live game with an empty world).

Every time you change the map:

1. In Studio's **Explorer**, right-click the `Map` folder in `Workspace`.
2. Choose **Save to File...** (newer Studio: **Save to File** / **Export Selection**).
3. Save it as **`map/Map.rbxm`** inside this repository, replacing the old file.
4. Commit and push (step 9).

Notes:
- Tags and attributes are saved in the file.
- **Terrain is not included.** Build the course from Parts, or keep terrain-free maps.
- Lighting, Sky and other settings outside `Workspace.Map` are not included either;
  the published place uses default Lighting.

---

## 8. Create an Open Cloud API key

The workflow uses this key to upload new versions of your place.

1. Go to <https://create.roblox.com/dashboard/credentials>
   (Creator Hub → **Open Cloud** → **API Keys**).
   If the experience is owned by a **group**, switch to that group first (top-left)
   and create the key there.
2. Click **Create API Key**. Name it, e.g. `github-deploy`.
3. **Access Permissions:**
   - **Select API System:** `universe-places` → **Add API System**.
   - **Experience:** pick your experience.
   - **Operations:** tick **Write**.
4. **Security → Accepted IP Addresses:** add `0.0.0.0/0`
   (GitHub runners use changing IP addresses; without this the request is rejected).
5. **Expiration:** optional. If you set a date, remember to create a new key before it.
6. Click **Save & Generate Key** and **copy the key now** (it is shown only once).

Keep the key secret. Never put it in a file in the repository.

---

## 9. Add the GitHub secrets and deploy

1. Open this repository on GitHub → **Settings** → **Secrets and variables** →
   **Actions** → **New repository secret**.
2. Add three secrets:

   | Name | Value |
   | --- | --- |
   | `ROBLOX_API_KEY` | the key from step 8 |
   | `UNIVERSE_ID` | from step 3 |
   | `PLACE_ID` | from step 3 |

3. Push to `main`:
   ```bash
   git add -A
   git commit -m "Update map"
   git push origin main
   ```
4. Open the **Actions** tab on GitHub and watch **Deploy to Roblox**.
   Green means the new version is live. You can also start it by hand there:
   **Deploy to Roblox → Run workflow**.

What the workflow does (`.github/workflows/deploy.yml`):
1. Installs Rojo with Aftman (version from `aftman.toml`).
2. Checks that `map/Map.rbxm` exists.
3. `rojo build deploy.project.json -o game.rbxl`
4. Uploads `game.rbxl` with the Open Cloud Place Publishing API
   (`POST /universes/v1/{UNIVERSE_ID}/places/{PLACE_ID}/versions?versionType=Published`).

Players in already running servers keep the old version until they rejoin.

---

## 10. Tuning the game

All numbers live in `src/shared/Config.luau`, for example:

| Setting | Default | Meaning |
| --- | --- | --- |
| `FinishReward` | 50 | Coins for finishing |
| `CoinValue` | 1 | Default coins per Coin part |
| `CoinRespawnTime` | 10 | Seconds until a coin reappears |
| `MinRunTime` | 20 | Faster full runs are rejected. Set it a bit below your fastest legit time. |
| `MinSecondsPerStage` | 1 | Minimum seconds between two checkpoints |
| `MaxTouchDistance` | 12 | Max studs between player and touched part |
| `AutosaveInterval` | 120 | Seconds between autosaves |
| `DataStoreName` | `ObbyPlayerData_v1` | Change the suffix to reset everyone's progress |

---

## 11. Troubleshooting

| Problem | Fix |
| --- | --- |
| `rojo` not found | Reopen the terminal after installing Rokit; run `rokit install` in this folder. |
| Plugin says version mismatch | Run `rojo plugin install` again and restart Studio. |
| "Progress is not being saved" | Step 6 (Studio), or Roblox DataStores are temporarily down. |
| Checkpoints do nothing | Check the tag spelling, the `Stage` attribute (Number type), and the Output window. |
| "You skipped a checkpoint!" | A Stage number is missing or out of order. |
| Workflow: `map/Map.rbxm not found` | Do step 7 and push the file. |
| Workflow: HTTP 401 / 403 | Wrong key, missing `universe-places` Write permission for this experience, or `0.0.0.0/0` not in the IP list. |
| Workflow: HTTP 404 | Wrong `UNIVERSE_ID` / `PLACE_ID`, or the place is not in that experience. |
| Workflow: HTTP 409 | The place is being edited in Team Create with unpublished drafts, or another publish is in progress. Retry. |
