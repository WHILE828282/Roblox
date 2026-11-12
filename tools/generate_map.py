"""
generate_map.py
Generates map/Map.model.json for "Steal a Sea Monster" (6 players).

  * Z -40..110: a sunny lagoon pier with 6 bases (3 on each side) and the
    Trail Shop stand next to the ocean entrance.
  * Z 110..610: a 70 stud wide corridor that slopes down through 5 depth
    zones: Coral Reef, Sunken Fleet, Ruins of Atlantis, Jellyfish Cave and
    the Mariana Abyss. A glowing arch stands at the start of every zone.

Run from the repository root after changing the layout:
    python3 tools/generate_map.py

Scripts find important parts by CollectionService tags:
  BasePlot  - invisible marker in the middle of a base (attribute BaseIndex)
  EggNest   - a nest in the ocean (attribute Zone 1-5)
  GuardPost - where a zone's guardian sleeps (attribute Zone)
  DepthArch - the glowing bar of a zone arch (attribute Zone)
  TrailShop - the counter of the Trail Shop
The numbers marked "Config" must match src/shared/Config.luau.
"""

import json
import math
import os
import random

random.seed(5)

OCEAN_START = 110  # Config.OceanStartZ
ZONE_LENGTH = 375  # Config.ZoneLength
HALF_WIDTH = 60  # Config.CorridorHalfWidth
SLOPE = 0.16  # Config.Slope
BASE_HALF_WIDTH = 20  # Config.BaseHalfWidth (along Z)
BASE_HALF_DEPTH = 18  # Config.BaseHalfDepth (along X)
BASE_X = 62
BASE_Z = (0, 43, 86)
PIER_HALF = 96
PIER_Z0 = -40

ZONES = [  # floor color, wall color, glow color
    ("Coral Reef", (236, 214, 160), (70, 150, 170), (255, 120, 170)),
    ("Sunken Fleet", (150, 150, 130), (50, 96, 130), (120, 255, 220)),
    ("Ruins of Atlantis", (120, 140, 170), (40, 70, 120), (90, 200, 255)),
    ("Jellyfish Cave", (70, 60, 120), (40, 30, 86), (210, 120, 255)),
    ("Mariana Abyss", (24, 22, 40), (12, 10, 24), (255, 60, 90)),
]

IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def yaw(t):
    c, s = math.cos(t), math.sin(t)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def pitch(t):
    c, s = math.cos(t), math.sin(t)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def roll(t):
    c, s = math.cos(t), math.sin(t)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


UPRIGHT = roll(math.pi / 2)  # turns a Cylinder (axis X) upright
SLOPE_ANGLE = math.atan(SLOPE)
DOWNHILL = pitch(SLOPE_ANGLE)  # local Z points forward and down the slope


def floor_y(z):
    return 0.0 if z <= OCEAN_START else -(z - OCEAN_START) * SLOPE


def part(name, center, size, color, material="SmoothPlastic", orientation=IDENTITY, tags=None, attributes=None,
         children=None, class_name="Part", **extra):
    props = {
        "Anchored": True,
        "Size": [round(v, 3) for v in size],
        "CFrame": {"CFrame": {
            "position": [round(v, 3) for v in center],
            "orientation": [[round(v, 5) for v in row] for row in orientation],
        }},
        "Color": [round(c / 255, 4) for c in color],
        "Material": material,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
    }
    if tags:
        props["Tags"] = tags
    props.update(extra)
    node = {"name": name, "className": class_name, "properties": props}
    if attributes:
        node["attributes"] = attributes
    if children:
        node["children"] = children
    return node


def decor(name, center, size, color, material="SmoothPlastic", **extra):
    """A part without collision (glow, plants, water)."""
    extra.setdefault("CanCollide", False)
    extra.setdefault("CanQuery", False)
    extra.setdefault("CanTouch", False)
    extra.setdefault("CastShadow", False)
    return part(name, center, size, color, material, **extra)


def cylinder(name, x, bottom_y, z, radius, height, color, material, **extra):
    return part(name, (x, bottom_y + height / 2, z), (height, radius * 2, radius * 2), color, material,
                orientation=UPRIGHT, Shape="Cylinder", **extra)


def ball(name, center, radius, color, material, **extra):
    return part(name, center, (radius * 2,) * 3, color, material, Shape="Ball", **extra)


def light(color, brightness, light_range):
    return {"name": "Glow", "className": "PointLight", "properties": {
        "Color": [c / 255 for c in color], "Brightness": brightness, "Range": light_range, "Shadows": False}}


def folder(name, children):
    return {"name": name, "className": "Folder", "children": children}


# --------------------------------------------------------------------------
# The pier
# --------------------------------------------------------------------------
def build_pier():
    parts = []
    length = OCEAN_START - PIER_Z0
    mid = (OCEAN_START + PIER_Z0) / 2
    parts.append(part("Sand", (0, -3, mid), (PIER_HALF * 2, 6, length), (242, 222, 170), "Sand"))
    parts.append(part("Boardwalk", (0, 0.1, mid), (26, 0.3, length), (176, 128, 84), "WoodPlanks"))
    # The lagoon around the pier and the water surface above the dive.
    parts.append(decor("Lagoon", (0, -1.4, 900), (1600, 0.6, 2400), (60, 190, 220), "Glass", Transparency=0.35,
                       Reflectance=0.15))
    parts.append(part("SeaBed", (0, -9, -200), (1400, 4, 600), (230, 214, 170), "Sand"))
    # Low stone border and invisible walls so nobody falls off the pier.
    for sx in (-1, 1):
        parts.append(part("Border", (sx * PIER_HALF, 1, mid), (3, 3, length), (220, 214, 200), "Cobblestone"))
        parts.append(part("Wall", (sx * (PIER_HALF + 1), 40, mid), (2, 90, length), (255, 255, 255), Transparency=1,
                          CanQuery=False, CastShadow=False))
    parts.append(part("Border", (0, 1, PIER_Z0), (PIER_HALF * 2, 3, 3), (220, 214, 200), "Cobblestone"))
    parts.append(part("Wall", (0, 40, PIER_Z0 - 1), (PIER_HALF * 2, 90, 2), (255, 255, 255), Transparency=1,
                      CanQuery=False, CastShadow=False))
    # The pier closes around the ocean entrance.
    for sx in (-1, 1):
        x = sx * (HALF_WIDTH + (PIER_HALF - HALF_WIDTH) / 2)
        parts.append(part("Border", (x, 1, OCEAN_START), (PIER_HALF - HALF_WIDTH, 3, 3), (220, 214, 200),
                          "Cobblestone"))
        parts.append(part("Wall", (x, 40, OCEAN_START + 1), (PIER_HALF - HALF_WIDTH, 90, 2), (255, 255, 255),
                          Transparency=1, CanQuery=False, CastShadow=False))

    # Palm trees, lanterns and beach bits.
    for i, (x, z) in enumerate([(-90, -30), (90, -30), (-34, -34), (34, -34), (-90, 22), (90, 22), (-90, 64),
                                (90, 64), (-40, 104), (40, 104)]):
        height = 16 + (i % 3) * 3
        lean = 0.12 * (1 if x > 0 else -1)
        parts.append(part("PalmTrunk", (x, height / 2, z), (1.6, height, 1.6), (150, 110, 70), "Wood",
                          orientation=roll(lean)))
        top_x = x - math.sin(lean) * height / 2
        for k in range(6):
            angle = k * math.tau / 6
            parts.append(decor("PalmLeaf", (top_x + math.cos(angle) * 4, height - 0.4, z + math.sin(angle) * 4),
                               (9, 0.5, 3), (70, 180, 80), "Grass",
                               orientation=mat_mul(yaw(-angle), roll(-0.35)), CastShadow=True))
        parts.append(ball("Coconut", (top_x, height - 0.8, z), 0.9, (110, 78, 50), "Wood", CanCollide=False))
    for z in (-20, 20, 60, 100):
        for sx in (-1, 1):
            x = sx * 15
            parts.append(part("LampPost", (x, 4.5, z), (0.7, 9, 0.7), (60, 70, 100), "Metal"))
            parts.append(ball("Lamp", (x, 9.6, z), 1.1, (255, 236, 170), "Neon", CanCollide=False,
                              children=[light((255, 236, 170), 1.2, 22)]))
    for x, z, s in [(-30, -10, 3), (-27, -6, 2.2), (28, 30, 3), (30, 70, 2.5), (-30, 50, 2.8)]:
        parts.append(part("Crate", (x, s / 2, z), (s, s, s), (190, 140, 90), "WoodPlanks",
                          orientation=yaw(random.uniform(0, 1.5))))

    spawn = part("Spawn", (0, 0.4, -26), (12, 0.6, 12), (120, 210, 230), "SmoothPlastic", class_name="SpawnLocation",
                 Neutral=True, Duration=0, orientation=yaw(math.pi), Transparency=0.5)
    return parts + [spawn]


def build_bases():
    parts = []
    index = 0
    for sx in (-1, 1):
        for z in BASE_Z:
            index += 1
            x = sx * BASE_X
            parts.append(part("BaseFloor", (x, 0.1, z), (BASE_HALF_DEPTH * 2, 0.4, BASE_HALF_WIDTH * 2),
                              (250, 240, 214), "Marble"))
            parts.append(decor("BaseTrim", (x, 0.06, z), (BASE_HALF_DEPTH * 2 + 2, 0.36, BASE_HALF_WIDTH * 2 + 2),
                               (60, 190, 200), "SmoothPlastic"))
            parts.append(part("Plot", (x, 0.3, z), (4, 0.2, 4), (255, 255, 255), tags=["BasePlot"],
                              attributes={"BaseIndex": index}, Transparency=1, CanCollide=False, CanQuery=False,
                              CanTouch=False))
            # A short path from the boardwalk to the entrance.
            inner = x - sx * BASE_HALF_DEPTH
            parts.append(decor("Path", ((inner + sx * 13) / 2, 0.12, z), (abs(inner - sx * 13), 0.3, 8),
                               (176, 128, 84), "WoodPlanks"))
    return parts


def build_trail_shop():
    x, z = -26, 96
    parts = [
        part("Counter", (x, 2, z), (14, 4, 4), (255, 120, 170), "SmoothPlastic", tags=["TrailShop"]),
        part("CounterTop", (x, 4.2, z), (15, 0.5, 5), (255, 255, 255), "Marble"),
        decor("Canopy", (x, 11, z), (17, 1, 8), (120, 90, 255), "Fabric", orientation=pitch(0.18), CastShadow=True),
        decor("Sign", (x, 13.6, z - 2), (13, 3, 0.6), (255, 220, 70), "Neon",
              children=[light((255, 220, 70), 1.5, 26)]),
    ]
    for sx in (-1, 1):
        parts.append(part("CanopyPole", (x + sx * 7.5, 5.5, z + 3), (0.7, 11, 0.7), (255, 255, 255), "Metal"))
        parts.append(part("CanopyPole", (x + sx * 7.5, 5.5, z - 3), (0.7, 11, 0.7), (255, 255, 255), "Metal"))
    # Glowing trail samples on the counter.
    for i, color in enumerate([(120, 200, 255), (255, 150, 90), (60, 255, 200), (120, 255, 90), (255, 255, 140),
                               (255, 140, 255), (255, 60, 90)]):
        parts.append(ball("Sample", (x - 6 + i * 2, 5.4, z), 0.7, color, "Neon", CanCollide=False))
    return parts


# --------------------------------------------------------------------------
# The dive
# --------------------------------------------------------------------------
def slope_slab(name, x, z0, z1, width, thickness, lift, color, material, **extra):
    """A slab that follows the slope from z0 to z1; `lift` is how far its top is above the floor."""
    length = (z1 - z0) / math.cos(SLOPE_ANGLE)
    zm = (z0 + z1) / 2
    # Move the center along the slab's own normal so its top ends up `lift` above the floor.
    normal = (0, math.cos(SLOPE_ANGLE), math.sin(SLOPE_ANGLE))
    offset = lift - thickness / 2
    center = (x, floor_y(zm) + normal[1] * offset, zm + normal[2] * offset)
    return part(name, center, (width, thickness, length + 0.6), color, material, orientation=DOWNHILL, **extra)


def on_floor(x, z, up=0.0):
    return (x, floor_y(z) + up, z)


def coral(x, z, glow):
    parts = []
    palette = [(255, 120, 170), (255, 170, 80), (190, 110, 255), (90, 230, 200), glow]
    for _ in range(random.randint(3, 5)):
        height = random.uniform(3, 9)
        cx, cz = x + random.uniform(-3, 3), z + random.uniform(-3, 3)
        color = random.choice(palette)
        parts.append(part("Coral", on_floor(cx, cz, height / 2 - 0.5), (height, 1.4, 1.4), color, "SmoothPlastic",
                          orientation=UPRIGHT, Shape="Cylinder", CanCollide=False))
        parts.append(ball("CoralTip", on_floor(cx, cz, height - 0.4), random.uniform(1, 1.8), color, "SmoothPlastic",
                          CanCollide=False))
    return parts


def seaweed(x, z, color=(60, 170, 90)):
    parts = []
    for _ in range(3):
        height = random.uniform(5, 11)
        parts.append(decor("Seaweed", on_floor(x + random.uniform(-1.5, 1.5), z + random.uniform(-1.5, 1.5),
                                               height / 2 - 0.4), (0.7, height, 0.3), color, "Grass",
                           orientation=mat_mul(yaw(random.uniform(0, 3)), roll(random.uniform(-0.2, 0.2)))))
    return parts


def rock(x, z, size, color):
    return [part("Rock", on_floor(x, z, size * 0.25), (size * 1.3, size * 0.9, size), color, "Slate",
                 orientation=mat_mul(yaw(random.uniform(0, 6)), pitch(random.uniform(-0.3, 0.3))))]


def shipwreck(x, z, turn):
    base = on_floor(x, z)
    rot = mat_mul(yaw(turn), roll(0.35))
    wood, dark = (120, 86, 60), (84, 60, 44)
    return [
        part("Hull", (base[0], base[1] + 4, base[2]), (9, 8, 30), wood, "WoodPlanks", orientation=rot),
        part("Deck", (base[0], base[1] + 8.5, base[2]), (10, 0.8, 26), dark, "Wood", orientation=rot),
        part("Mast", (base[0] + 4, base[1] + 16, base[2]), (1.4, 26, 1.4), dark, "Wood",
             orientation=mat_mul(yaw(turn), roll(0.9))),
        decor("Sail", (base[0] + 8, base[1] + 19, base[2]), (0.4, 12, 12), (220, 220, 200), "Fabric",
              orientation=mat_mul(yaw(turn), roll(0.9)), Transparency=0.25),
        ball("Lantern", (base[0], base[1] + 11, base[2] + 12), 1, (120, 255, 220), "Neon", CanCollide=False,
             children=[light((120, 255, 220), 2, 30)]),
    ]


def atlantis_column(x, z, height, glow):
    base = on_floor(x, z)
    parts = [
        part("ColumnBase", (base[0], base[1] + 0.8, base[2]), (5, 2, 5), (200, 210, 230), "Marble"),
        cylinder("Column", base[0], base[1] + 1.4, base[2], 1.7, height, (220, 228, 240), "Marble"),
        decor("Rune", (base[0], base[1] + height * 0.6, base[2]), (0.5, 3.6, 3.6), glow, "Neon",
              orientation=UPRIGHT, Shape="Cylinder"),
    ]
    if height > 18:
        parts.append(part("Capital", (base[0], base[1] + height + 2, base[2]), (5, 1.6, 5), (200, 210, 230),
                          "Marble"))
    return parts


def jellyfish(x, z, up, glow):
    y = floor_y(z) + up
    color = random.choice([glow, (140, 220, 255), (255, 160, 230)])
    parts = [ball("Jelly", (x, y, z), random.uniform(1.6, 2.8), color, "Neon", CanCollide=False, Transparency=0.15,
                  children=[light(color, 1.6, 26)])]
    for k in range(4):
        angle = k * math.tau / 4
        parts.append(decor("JellyTentacle", (x + math.cos(angle) * 0.9, y - 3.2, z + math.sin(angle) * 0.9),
                           (0.3, 4.5, 0.3), color, "Neon", Transparency=0.3))
    return parts


def abyss_spike(x, z, glow):
    height = random.uniform(10, 30)
    tilt = mat_mul(yaw(random.uniform(0, 6)), pitch(random.uniform(-0.3, 0.3)))
    parts = [part("Spike", on_floor(x, z, height / 2 - 1.5), (random.uniform(3, 6), height, random.uniform(3, 6)),
                  (14, 12, 26), "Basalt", orientation=tilt)]
    if random.random() < 0.6:
        parts.append(decor("Vent", on_floor(x + 3, z + 2, 0.25), (0.5, 5, 5), glow, "Neon", orientation=UPRIGHT,
                           Shape="Cylinder", children=[light(glow, 2, 24)]))
    return parts


def build_zone(index):
    name, floor_color, wall_color, glow = ZONES[index - 1]
    z0 = OCEAN_START + (index - 1) * ZONE_LENGTH
    z1 = z0 + ZONE_LENGTH
    parts = [slope_slab("Floor", 0, z0, z1, HALF_WIDTH * 2, 6, 0, floor_color, "Sand" if index < 3 else "Slate")]
    for sx in (-1, 1):
        # Cliffs end just under the water surface, so from the pier you only see the sea.
        bottom = floor_y(z1) - 8
        parts.append(part("Cliff", (sx * (HALF_WIDTH + 8), (bottom - 1.8) / 2, (z0 + z1) / 2),
                          (16, -1.8 - bottom, ZONE_LENGTH), wall_color, "Rock"))
        # Glowing veins on the cliffs so the walls are never plain.
        for _ in range(12):
            z = random.uniform(z0 + 4, z1 - 4)
            parts.append(decor("Vein", (sx * (HALF_WIDTH - 0.2), floor_y(z) + random.uniform(4, 40), z),
                               (0.4, random.uniform(3, 10), random.uniform(0.6, 1.4)), glow, "Neon",
                               orientation=pitch(random.uniform(-0.5, 0.5))))
    if index >= 4:  # the cave and the abyss have a roof
        parts.append(slope_slab("Roof", 0, z0, z1, HALF_WIDTH * 2 + 32, 8, 68, wall_color, "Rock"))

    # The arch at the entrance of the zone.
    arch_y = floor_y(z0)
    for sx in (-1, 1):
        parts.append(part("ArchPillar", (sx * (HALF_WIDTH - 3), arch_y + 15, z0 + 2), (5, 34, 5), (40, 46, 70),
                          "Marble"))
        parts.append(decor("ArchGlow", (sx * (HALF_WIDTH - 3), arch_y + 15, z0 - 0.7), (1.2, 30, 0.4), glow,
                           "Neon"))
    parts.append(part("ArchBar", (0, arch_y + 31, z0 + 2), (HALF_WIDTH * 2 - 1, 5, 4), glow, "Neon",
                      tags=["DepthArch"], attributes={"Zone": index}, CanCollide=False,
                      children=[light(glow, 2.5, 50)]))

    # Nests and the guardian's bed.
    nests = []
    for k in range(8):
        z = z0 + 60 + k * 38
        x = (-1 if k % 2 == 0 else 1) * random.uniform(16, 50)
        nests.append((x, z))
        y = floor_y(z)
        parts.append(part("Nest", (x, y + 0.5, z), (1, 7, 7), (90, 70, 60), "Slate", orientation=UPRIGHT,
                          Shape="Cylinder", tags=["EggNest"], attributes={"Zone": index}))
        parts.append(decor("NestGlow", (x, y + 0.95, z), (0.3, 5.6, 5.6), glow, "Neon", orientation=UPRIGHT,
                           Shape="Cylinder", children=[light(glow, 1.4, 18)]))
    guard_x, guard_z = (-1 if index % 2 else 1) * 4, z0 + 200
    parts.append(part("GuardBed", on_floor(guard_x, guard_z, 0.3), (0.8, 24, 24), wall_color, "Slate",
                      orientation=UPRIGHT, Shape="Cylinder", tags=["GuardPost"], attributes={"Zone": index},
                      CanCollide=False))

    def free(x, z, margin):
        return (all(math.hypot(x - nx, z - nz) > margin + 5 for nx, nz in nests)
                and math.hypot(x - guard_x, z - guard_z) > margin + 14 and z0 + 8 < z < z1 - 4)

    def spots(count, margin, x_range=HALF_WIDTH - 5):
        found = []
        tries = 0
        while len(found) < count and tries < 3000:
            tries += 1
            x, z = random.uniform(-x_range, x_range), random.uniform(z0 + 8, z1 - 4)
            if free(x, z, margin) and all(math.hypot(x - fx, z - fz) > margin * 2 for fx, fz in found):
                found.append((x, z))
        return found

    if index == 1:
        for x, z in spots(55, 3):
            parts += coral(x, z, glow)
        for x, z in spots(60, 1):
            parts += seaweed(x, z)
        for x, z in spots(30, 2):
            parts += rock(x, z, random.uniform(4, 9), (150, 150, 160))
    elif index == 2:
        for i, (x, z) in enumerate(spots(8, 16, HALF_WIDTH - 14)):
            parts += shipwreck(x, z, i * 1.1)
        for x, z in spots(35, 2):
            parts.append(part("Crate", on_floor(x, z, 1.5), (3, 3, 3), (120, 90, 64), "WoodPlanks",
                              orientation=mat_mul(yaw(random.uniform(0, 2)), pitch(0.2))))
        for x, z in spots(45, 1):
            parts += seaweed(x, z, (50, 130, 110))
        for x, z in spots(20, 3):
            parts += coral(x, z, glow)
    elif index == 3:
        for x, z in spots(48, 4):
            parts += atlantis_column(x, z, random.choice([8, 14, 22, 28]), glow)
        for x, z in spots(10, 9, HALF_WIDTH - 12):
            base = on_floor(x, z)
            for sx in (-1, 1):
                parts.append(part("ArchLeg", (base[0] + sx * 7, base[1] + 8, base[2]), (3, 16, 3), (210, 220, 236),
                                  "Marble"))
            parts.append(part("ArchTop", (base[0], base[1] + 17.5, base[2]), (20, 3, 4), (210, 220, 236), "Marble"))
            parts.append(decor("ArchRune", (base[0], base[1] + 17.5, base[2] - 2.1), (12, 1.2, 0.3), glow, "Neon",
                               children=[light(glow, 2, 28)]))
        for x, z in spots(30, 2):
            parts += rock(x, z, random.uniform(4, 9), (150, 164, 190))
    elif index == 4:
        for x, z in spots(70, 2):
            parts += jellyfish(x, z, random.uniform(9, 34), glow)
        for x, z in spots(40, 3):
            parts += rock(x, z, random.uniform(5, 10), (60, 50, 104))
        for x, z in spots(25, 3):
            parts += coral(x, z, glow)
    else:
        for x, z in spots(70, 4):
            parts += abyss_spike(x, z, glow)
        for x, z in spots(30, 2):
            parts += jellyfish(x, z, random.uniform(12, 30), glow)
    return folder("Zone%d" % index, parts)


def build():
    end_z = OCEAN_START + 5 * ZONE_LENGTH
    end = [
        part("EndWall", (0, floor_y(end_z) + 50, end_z + 8), (HALF_WIDTH * 2 + 40, 130, 16), (10, 8, 20), "Basalt"),
        decor("AbyssEye", (-9, floor_y(end_z) + 22, end_z - 0.4), (7, 7, 7), (255, 60, 90), "Neon", Shape="Ball",
              children=[light((255, 60, 90), 3, 50)]),
        decor("AbyssEye", (9, floor_y(end_z) + 22, end_z - 0.4), (7, 7, 7), (255, 60, 90), "Neon", Shape="Ball"),
    ]
    # Invisible walls along the whole dive (the cliffs are low near the surface).
    for sx in (-1, 1):
        end.append(part("Wall", (sx * (HALF_WIDTH + 0.5), -70, (OCEAN_START + end_z) / 2), (1, 400, end_z - OCEAN_START),
                        (255, 255, 255), Transparency=1, CanQuery=False, CastShadow=False))
    root = folder("Map", [
        folder("Pier", build_pier()),
        folder("Bases", build_bases()),
        folder("TrailShop", build_trail_shop()),
        folder("Ocean", [build_zone(i) for i in range(1, 6)] + [folder("End", end)]),
    ])
    root.pop("name")
    return root


def count_parts(node):
    return (1 if node.get("className") not in ("Folder", "Model") else 0) + sum(
        count_parts(child) for child in node.get("children", []))


if __name__ == "__main__":
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(repo, "map", "Map.model.json")
    result = build()
    with open(out, "w") as f:
        json.dump(result, f, separators=(",", ":"))
        f.write("\n")
    print("Wrote %s: %d instances" % (out, count_parts(result)))
