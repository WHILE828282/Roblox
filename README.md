# Steal a Sea Monster (Roblox + Rojo)

Dive from a sunny pier into the ocean abyss, steal glowing eggs from sleeping
guardians, run home before they catch you, hatch sea creatures in your
aquarium and train your speed on the treadmill. 6 players per server.

All code and the map are in this repository (Luau) and are built with **Rojo**.

## How the game works

| Step | What happens |
| --- | --- |
| Dive | A 70 stud wide corridor slopes down through 5 depth zones: Coral Reef (-50m), Sunken Fleet (-150m), Ruins of Atlantis (-300m), Jellyfish Cave (-500m), Mariana Abyss (-1000m). The water gets darker the deeper you go. |
| Steal | Every zone has nests with glowing eggs. Rarer eggs are heavier: they slow you down more. |
| Run | Taking an egg wakes the zone's guardian. It chases you until you reach the pier. If it catches you, the egg goes back to its nest. A glowing beam shows the way to your base. |
| Hatch | Your base has 4 incubators. Hatched creatures live in the glass aquarium and earn money. Step on the green plate to collect it. |
| Train | Stand on your treadmill to raise your Speed. Upgrade it with the button next to it. |
| Trails | The Trail Shop on the pier sells 7 trails. The equipped trail multiplies treadmill training (x1.5 ... x12). |
| PvP | You can steal eggs from other players' incubators. **Lock Base** raises a water shield for 30 seconds. |

Controls: **Q** (or the DASH button) = dash. Buttons at the bottom: Dash, Drop Egg, Lock Base. Icons on the left: Trails, Shop, Index.

## Project layout

```
default.project.json   Rojo project (also sets the lighting)
map/Map.model.json     The whole map (generated, do not edit by hand)
tools/generate_map.py  Generates the map: python3 tools/generate_map.py
src/shared/            Config (all numbers), Sea (zones, creatures, trails), CreatureModel, Remotes, Format
src/server/Services/   PlayerData (DataStore), Bases, Ocean (nests, guardians), Trails
src/server/Lib/        Movement (the only place that sets WalkSpeed), RateLimiter
src/client/            Main, Effects (depth lighting, guide beam, animations), UI (Hud, Panels, Style, Icons)
assets/icons/          Source files of the UI icons
```

Map tags (CollectionService): `BasePlot`, `EggNest`, `GuardPost`, `DepthArch`, `TrailShop`.

## Security

Money, eggs, creatures, speed and saving are decided only on the server. Clients send requests
(dash, drop, lock, buy, equip, upgrade, sell); every request is type-checked and rate-limited, and
prompt holds and distances are verified on the server. DataStore calls use pcall with retries; if
loading fails, that session is not saved.

## Build

```bash
rokit install
rojo build default.project.json -o SeaMonsters.rbxl
```

Open `SeaMonsters.rbxl` in Roblox Studio. In **Game Settings** set the server size to **6** and the
avatar type to **R15**, and enable **Studio Access to API Services** to test saving.

## Tuning

- Timers, costs, speeds: `src/shared/Config.luau`
- Zones, creatures, rarities, trails: `src/shared/Sea.luau`
- Layout of the map: constants at the top of `tools/generate_map.py` (keep them equal to Config)
