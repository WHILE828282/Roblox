# Steal a Sea Monster (Roblox + Rojo)

Dive from a sunny pier into the ocean abyss, steal glowing eggs from sleeping
guardians, run home before they catch you, hatch sea creatures in your
aquarium and train your speed on the treadmill. 6 players per server.

All code and the map are in this repository (Luau) and are built with **Rojo**.

## How the game works

| Step | What happens |
| --- | --- |
| Dive | A 120 stud wide corridor goes down through 5 depth zones of about 375 studs each: Coral Reef (-50m), Sunken Fleet (-150m), Ruins of Atlantis (-300m), Jellyfish Cave (-500m), Mariana Abyss (-1000m). The water gets darker the deeper you go. |
| Steal | Every zone has nests with glowing eggs. Rarer eggs are heavier: they slow you down more. |
| Run | Taking an egg (or coming close with one) wakes the zone's guardian. It runs at 95% of the zone's recommended speed and chases you until you reach the pier, so you need training. If it catches you, the egg goes back to its nest, you are sent to your base and guardians ignore you for 3 seconds. A glowing beam shows the way home. |
| Hatch | Your base has 4 incubators. Hatched creatures live in the glass aquarium and earn money. Step on the green plate to collect it. |
| Train | Step on your treadmill: it holds you in the middle and you run on the spot while Speed grows every second. **Jump** to get off. Upgrade it with the button next to it. |
| Trails | The Trail Shop on the pier sells 7 trails. The equipped trail multiplies treadmill training (x1.5 ... x12). |
| PvP | You can steal eggs from other players' incubators. **Lock Base** raises a water shield for 30 seconds. |

Controls: **Q** (or the DASH button) = dash. Buttons at the bottom: Dash, Drop Egg, Lock Base. Icons on the left: Trails, Shop, Index.

## Project layout

```
default.project.json   Rojo project: ONLY the scripts and ReplicatedStorage.Assets.
                       The map, Terrain and Lighting are made by hand in Studio.
place.project.json     A complete test place: scripts + the generated test map + lighting
map/Map.model.json     The generated test map (used only by place.project.json)
tools/generate_map.py  Generates the test map: python3 tools/generate_map.py
assets/models/         -> ReplicatedStorage.Assets (Creatures, Bosses, Eggs); see below
src/shared/            Config (all numbers), Sea (zones, creatures, trails), CreatureModel, Remotes, Format
src/server/Services/   PlayerData (DataStore), Bases, Ocean (nests, guardians), Trails
src/server/Lib/        Movement (the only place that sets WalkSpeed), RateLimiter
src/client/            Main, Effects (depth lighting, guide beam, animations), UI (Hud, Panels, Style, Icons)
assets/icons/          Source files of the UI icons
```

Map tags (CollectionService). When you build the map by hand, tag these parts:

| Tag | Part | Attribute |
| --- | --- | --- |
| `BasePlot` | small invisible part in the middle of each base (6) | `BaseIndex` 1-6 |
| `EggNest` | a nest; the egg sits on its top | `Zone` 1-5 |
| `GuardPost` | the bed where a zone's guardian sleeps | `Zone` 1-5 |
| `DepthArch` | the bar of the arch at the start of a zone (gets the depth sign) | `Zone` 1-5 |
| `TrailShop` | the counter of the Trail Shop | - |

The zones follow the Z axis: the pier ends at Z = 110 (`Config.OceanStartZ`), each zone is
`Config.ZoneLength` (375) long. Guardians walk on whatever ground is under them.

## Models (ReplicatedStorage.Assets)

Put Toolbox models here; the game copies them, removes every script, scales them and animates them:

- `Assets/Creatures/<id>`: one per creature id from `src/shared/Sea.luau` (Clownfish, Seahorse, Pufferfish,
  Crab, Swordfish, GhostShark, SeaTurtle, TridentEel, GoldenManta, MoonJelly, LanternAngler, PrismSquid,
  AbyssSerpent, KrakenSpawn, Leviathan)
- `Assets/Bosses/Zone1` ... `Zone5`: the guardians
- `Assets/Eggs/Egg`: one egg, tinted by rarity

Models should look along -Z; if one does not, give it a number attribute `Yaw` (degrees). Anything
missing is replaced by a simple stand-in and a warning in Output. Guardians breathe while asleep and glow
red when awake; creatures swim around the aquarium (all done with tweens on the client).

## Security

Money, eggs, creatures, speed and saving are decided only on the server. Clients send requests
(dash, drop, lock, buy, equip, upgrade, sell); every request is type-checked and rate-limited, and
prompt holds and distances are verified on the server. DataStore calls use pcall with retries; if
loading fails, that session is not saved.

## Build

```bash
rokit install
rojo serve            # sync the scripts into your own place in Studio
rojo build place.project.json -o SeaMonsters.rbxl   # or build the complete test place
```

Open `SeaMonsters.rbxl` in Roblox Studio. In **Game Settings** set the server size to **6** and the
avatar type to **R15**, and enable **Studio Access to API Services** to test saving.

## Tuning

- Timers, costs, speeds: `src/shared/Config.luau`
- Zones, creatures, rarities, trails: `src/shared/Sea.luau`
- Layout of the map: constants at the top of `tools/generate_map.py` (keep them equal to Config)
