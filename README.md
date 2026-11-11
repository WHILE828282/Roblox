# Dino Raiders (Roblox + Rojo)

A volcano shoots dinosaur eggs across the map. Grab them, run home before
someone knocks you over, hatch them in your nests, raise the dinosaurs, ride
them, and steal from other players.

- All code and the map are in this repository (Luau), synced into Roblox with **Rojo**.
- Every push to `main` builds the game and **publishes it to Roblox** with GitHub Actions.

---

## Contents

1. [How the game works](#1-how-the-game-works)
2. [How the project is organized](#2-how-the-project-is-organized)
3. [Create the experience and find UNIVERSE_ID and PLACE_ID](#3-create-the-experience-and-find-universe_id-and-place_id)
4. [Experience settings you must change](#4-experience-settings-you-must-change)
5. [Create an Open Cloud API key](#5-create-an-open-cloud-api-key)
6. [Add the GitHub secrets and deploy](#6-add-the-github-secrets-and-deploy)
7. [Robux items (gamepasses and products)](#7-robux-items-gamepasses-and-products)
8. [Work in Studio with rojo serve (optional)](#8-work-in-studio-with-rojo-serve-optional)
9. [The map and its tags](#9-the-map-and-its-tags)
10. [Tuning the game](#10-tuning-the-game)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. How the game works

| Step | What happens |
| --- | --- |
| Eruption | Every 45 s the volcano shoots eggs onto the field. Eggs near the volcano (inner ring) are rarer. Every 10 min a **BIG eruption** fires many eggs plus a guaranteed Legendary-or-better egg. |
| Grab | Hold the prompt on an egg to pick it up. On foot you carry 1 egg; on a dinosaur 1-3. |
| Run home | Get to your base: eggs go into free nests. If someone hits you, you drop your eggs. |
| Hatch | Eggs hatch after a timer (30 s for Common ... 30 min for Divine). |
| Grow | Dinosaurs grow Baby -> Teen -> Adult and earn more money per second as they grow. |
| Ride | Adult dinosaurs can be ridden (Dinos menu -> Ride, at your base). Each species has an ability (key **F**). |
| Steal eggs | Hold "Steal" on an egg in someone else's nest (3 s). Their adult dinosaurs guard the base and push thieves out. **Lock Base** blocks stealing for 60 s. |
| Steal dinosaurs | If a rider dies, the dinosaur stays with an **EMPTY SADDLE**. Anyone can saddle it (hold 5 s) and must ride it to **their own base** to keep it. The owner can win it back first. |

Rarities: Common, Rare, Epic, Legendary, Mythic, Secret, Divine. Mutations: Golden (x3 money), Rainbow (x10).
Species: Raptor (Sprint), Triceratops (Ram), Stegosaurus (Tail Spin, takes half damage), T-Rex (Roar: everyone near drops their eggs).

Safety rules: you can't be hurt inside your own base, and brand new players are protected for 10 minutes (until they attack).

### Security model (anti-exploit)

- Money, eggs, dinosaurs, damage and saving are decided **only on the server**.
- Clients only send requests (attack, ride, sell, buy upgrade, lock). Every request is
  type-checked and rate-limited; prompt holds are timed on the server; distances are checked.
- Robux purchases remember their purchase id, so a reward is never given twice.
- If loading saved data fails, that session is **not** saved, so real progress is never overwritten.

---

## 2. How the project is organized

```
default.project.json   Rojo project (used by rojo serve and GitHub Actions)
aftman.toml            Pinned tool versions (Rojo)
map/Map.model.json     The whole map -> Workspace.Map (generated)
tools/generate_map.py  Generates map/Map.model.json
src/
  shared/  -> ReplicatedStorage.Shared
    Config.luau       ALL timers, limits and Robux item ids
    Dinos.luau        species, rarities, mutations, egg odds
    Economy.luau      prices, income, growth, upgrades
    DinoModel.luau    builds dinosaurs and eggs from blocks
    Remotes.luau      list of RemoteEvents
  server/  -> ServerScriptService.Server
    Main.server.luau  starts everything
    Services/
      PlayerData.luau  DataStore load/save (pcall + retries), leaderstats
      Bases.luau       bases, nests, pen, income, growth, hatching, lock, guards
      Eggs.luau        volcano eruptions, grabbing, carrying, delivering eggs
      Mounts.luau      riding, empty saddles, stealing dinosaurs
      Combat.luau      hits, abilities, deaths, protection
      Shop.luau        upgrades, gamepasses, Robux products
      Leaderboard.luau global top hatchers (OrderedDataStore)
  client/  -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau  UI + controls (click = hit, F = ability)
    UI/               HUD, panels (Dinos, Upgrades, Shop, Odds), leaderboard
    Effects.luau      rainbow colors, nest timers, knockback
  gui/     -> StarterGui (empty ScreenGui, filled by the client)
.github/workflows/deploy.yml   build + publish on push to main
```

---

## 3. Create the experience and find UNIVERSE_ID and PLACE_ID

1. Roblox Studio -> **File -> Publish to Roblox** -> create a new experience (any name, you can rename it later).
2. Find the two numbers. Easiest: in Studio open **View -> Output**, then type in the command bar at the bottom:
   ```lua
   print("UNIVERSE_ID =", game.GameId, "PLACE_ID =", game.PlaceId)
   ```
   and press **Enter**. Or on <https://create.roblox.com/dashboard/creations>: **...** on the experience ->
   **Copy Universe ID**; open it -> **Places** -> **...** -> **Copy Place ID**.

---

## 4. Experience settings you must change

On <https://create.roblox.com/dashboard/creations> open the experience, or use **File -> Game Settings** in Studio:

1. **Server size = 6** (Places -> your place -> Configure / Game Settings -> Places).
   The map has 6 bases, one per player.
2. **Avatar type = R15** (Game Settings -> Avatar). Riding needs R15 characters.
3. **Enable Studio Access to API Services** (Game Settings -> Security) so saving works when you test in Studio.
4. When you are ready: make the experience **Public**.

---

## 5. Create an Open Cloud API key

1. <https://create.roblox.com/dashboard/credentials> -> **Create API Key**, name `github`.
2. **Access Permissions** -> API system **universe-places** -> pick your experience -> tick **Write**.
3. **Accepted IP Addresses**: `0.0.0.0/0` (GitHub uses changing addresses).
4. **Save & Generate Key** and copy it right away (it is shown only once). Never put it in a file.

---

## 6. Add the GitHub secrets and deploy

1. GitHub repository -> **Settings -> Secrets and variables -> Actions -> New repository secret**.
2. Add `ROBLOX_API_KEY`, `UNIVERSE_ID`, `PLACE_ID`.
3. Go to the **Actions** tab -> **Deploy to Roblox** -> **Run workflow** (it also runs on every push to `main`).
   Green = the new version is live.

---

## 7. Robux items (gamepasses and products)

The Shop shows these items. Until you create them they say "Coming soon".

1. Open the experience on create.roblox.com -> **Monetization**.
2. **Passes** -> create 4 passes: x2 Money, x2 Growth, +3 Nests, Saddle Lock. Set a price and put them on sale.
3. **Developer Products** -> create 6 products: Instant Hatch, Hatch All, Server Luck, Big Eruption, Cash Pack, Big Cash Pack.
4. Copy each id into `Config.GamePasses` / `Config.Products` in `src/shared/Config.luau` and push
   (or just send the ids to Claude).

Suggested prices: x2 Money 399, x2 Growth 299, +3 Nests 249, Saddle Lock 199, Instant Hatch 9,
Hatch All 49, Server Luck 199, Big Eruption 99, Cash Pack 25, Big Cash Pack 149.

The **Odds** menu shows the exact chances of every egg tier and mutation, as Roblox requires for paid random items.

---

## 8. Work in Studio with rojo serve (optional)

Only needed if you want to see code changes live in Studio.

```bash
rokit install
```

```bash
rojo plugin install
```

```bash
rojo serve
```

Then in Studio: **Plugins -> Rojo -> Connect**. Edit files in this repository, not in Studio:
Rojo overwrites `ServerScriptService.Server`, `StarterPlayerScripts.Client`, `ReplicatedStorage.Shared`,
`StarterGui` and `Workspace.Map`.

---

## 9. The map and its tags

`tools/generate_map.py` builds the map (run `python tools/generate_map.py`, then push).
Scripts find important parts by CollectionService tag:

| Tag | Part | Notes |
| --- | --- | --- |
| `Volcano` | top tier of the volcano | eggs fly out of its top |
| `BasePlot` | each player's base (6) | number attribute `BaseIndex` |

Eggs only land on parts inside `Workspace.Map.Ground`. Ring sizes must match `Config.RingRadii`.

---

## 10. Tuning the game

- Timers, limits, combat, eruptions: `src/shared/Config.luau`
- Odds per ring, rarities, species: `src/shared/Dinos.luau`
- Prices, income, growth, upgrades: `src/shared/Economy.luau`
- Change `Config.DataStoreName` (`_v1` -> `_v2`) to reset everyone's progress.

---

## 11. Troubleshooting

| Problem | Fix |
| --- | --- |
| "Progress is not being saved" | Step 4.3 (Studio), or Roblox DataStores are down. |
| Riding looks wrong / floats | Set Avatar type to R15 (step 4.2). |
| A player gets no base | Server size must be 6 (step 4.1). |
| Shop says "Coming soon" | Create the item and paste its id into Config.luau (step 7). |
| Workflow HTTP 401 / 403 | API key: `universe-places` Write for this experience, IP `0.0.0.0/0`. |
| Workflow HTTP 404 | Wrong `UNIVERSE_ID` / `PLACE_ID`. |
| Workflow HTTP 409 | Unpublished Team Create drafts or another publish in progress. Retry. |
