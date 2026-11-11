"""
generate_map.py
Generates map/Map.model.json for Dino Raiders: a big valley for 20 players.

  * a large volcano in the center, surrounded by lava fields (inner ring)
  * the egg field with three rings (inner / middle / outer)
  * four biomes, one per quarter of the map, separated by shallow rivers:
      jungle (+X +Z), desert with bones (-X +Z), swamp (-X -Z), rocky canyon (+X -Z)
  * hills, bridges, giant trees, dinosaur skeletons, ruins
  * 20 player bases in a circle, and mountains all around the valley

Run from the repository root after changing the layout:
    python3 tools/generate_map.py

Scripts find important parts by CollectionService tags:
  Volcano  - top of the volcano (eggs fly out of it)
  BasePlot - invisible marker in the middle of a base (attribute BaseIndex)
Eggs only land on parts inside Map/Ground, and only where nothing else is in
the way. The numbers marked "Config" must match src/shared/Config.luau.
"""

import json
import math
import os
import random

random.seed(11)

# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------
BASE_COUNT = 20
BASE_RING_RADIUS = 680
BASE_RADIUS = 46  # Config.BaseRadius
HALF_MAP = 800  # the valley ends here (mountains + invisible wall)
GROUND_HALF = 960
FIELD_INNER = 105  # Config.FieldInnerRadius
INNER_RING = 240  # Config.RingRadii.Inner
MIDDLE_RING = 400  # Config.RingRadii.Middle
FIELD_OUTER = 530  # Config.FieldOuterRadius
RIVER_HALF = 13  # half of a river's width
RIVER_START = 246  # rivers start at the edge of the lava field
BASE_TOP = 0.5  # height of a base floor above the ground

# --------------------------------------------------------------------------
# Colors
# --------------------------------------------------------------------------
JUNGLE_GRASS = (72, 138, 62)
DESERT_SAND = (222, 196, 140)
SWAMP_MUD = (74, 92, 62)
CANYON_ROCK = (176, 112, 78)
BASALT = (58, 52, 54)
VOLCANO_ROCK = (52, 46, 48)
LAVA = (255, 96, 20)
LAVA_HOT = (255, 170, 40)
OBSIDIAN = (28, 24, 34)
DIRT = (140, 106, 70)
SAND = (232, 214, 170)
WOOD = (112, 78, 48)
DARK_WOOD = (78, 56, 40)
DEAD_WOOD = (96, 88, 78)
LEAF = (58, 142, 60)
DARK_LEAF = (36, 104, 52)
LIGHT_LEAF = (104, 170, 66)
SWAMP_LEAF = (70, 96, 50)
STONE = (132, 132, 138)
MOSS_STONE = (104, 124, 98)
RED_STONE = (150, 88, 62)
DARK_RED_STONE = (118, 70, 54)
BONE = (236, 228, 204)
WATER = (64, 150, 200)
SWAMP_WATER = (58, 86, 60)
CACTUS = (74, 140, 84)
MUSHROOM = (150, 230, 190)
SNOW = (240, 244, 248)

BIOME_GROUND = {
    "jungle": (JUNGLE_GRASS, "Grass"),
    "desert": (DESERT_SAND, "Sand"),
    "swamp": (SWAMP_MUD, "Mud"),
    "canyon": (CANYON_ROCK, "Sandstone"),
}
BIOME_MOUNTAIN = {
    "jungle": ((70, 104, 74), "Rock"),
    "desert": ((190, 150, 104), "Sandstone"),
    "swamp": ((66, 76, 70), "Slate"),
    "canyon": ((142, 86, 64), "Rock"),
}

# --------------------------------------------------------------------------
# Small math helpers (3x3 rotation matrices, rows first, like Roblox CFrames)
# --------------------------------------------------------------------------
IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def yaw(t):
    c, s = math.cos(t), math.sin(t)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def pitch(t):
    c, s = math.cos(t), math.sin(t)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def roll(t):
    c, s = math.cos(t), math.sin(t)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


# Rotates a Cylinder (axis X) so its axis points up (Y): a flat disc / pillar.
UPRIGHT = roll(math.pi / 2)


def facing_center(angle):
    """Rotation whose -Z axis points from a spot at `angle` toward the map center."""
    s, c = math.sin(angle), math.cos(angle)
    return [[s, 0, c], [0, 1, 0], [-c, 0, s]]


class Frame:
    """A position + rotation; `at` turns local offsets into world positions."""

    def __init__(self, position, rotation=IDENTITY):
        self.position = position
        self.rotation = rotation

    def at(self, x, y, z):
        dx, dy, dz = mat_vec(self.rotation, (x, y, z))
        return (self.position[0] + dx, self.position[1] + dy, self.position[2] + dz)

    def turned(self, rotation):
        return mat_mul(self.rotation, rotation)


# --------------------------------------------------------------------------
# Instance builders
# --------------------------------------------------------------------------
def part(name, center, size, color, material="SmoothPlastic", orientation=IDENTITY, tags=None,
         attributes=None, children=None, class_name="Part", **extra):
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
    """A part players walk through and eggs fly through (leaves, water, glow)."""
    extra.setdefault("CanCollide", False)
    extra.setdefault("CanQuery", False)
    extra.setdefault("CanTouch", False)
    extra.setdefault("CastShadow", False)
    return part(name, center, size, color, material, **extra)


def cylinder(name, x, bottom_y, z, radius, height, color, material, **extra):
    """An upright cylinder standing on bottom_y."""
    return part(name, (x, bottom_y + height / 2, z), (height, radius * 2, radius * 2), color, material,
                orientation=UPRIGHT, Shape="Cylinder", **extra)


def disc(name, x, top_y, z, radius, thickness, color, material, **extra):
    """A flat round part whose top surface is at top_y."""
    return cylinder(name, x, top_y - thickness / 2 - thickness / 2, z, radius, thickness, color, material, **extra)


def ball(name, center, radius, color, material, **extra):
    return part(name, center, (radius * 2, radius * 2, radius * 2), color, material, Shape="Ball", **extra)


def light(color, brightness, light_range):
    return {"name": "Glow", "className": "PointLight", "properties": {
        "Color": [c / 255 for c in color], "Brightness": brightness, "Range": light_range, "Shadows": False}}


def folder(name, children):
    return {"name": name, "className": "Folder", "children": children}


def model(name, children, **props):
    return {"name": name, "className": "Model", "properties": props, "children": children}


# --------------------------------------------------------------------------
# Where things are
# --------------------------------------------------------------------------
def base_angle(index):
    return math.radians((index + 0.5) * 360 / BASE_COUNT)


def base_center(index):
    angle = base_angle(index)
    return (math.cos(angle) * BASE_RING_RADIUS, math.sin(angle) * BASE_RING_RADIUS)


BASES = [base_center(i) for i in range(BASE_COUNT)]


def biome_at(x, z):
    if math.hypot(x, z) < INNER_RING:
        return "lava"
    if x >= 0 and z >= 0:
        return "jungle"
    if x < 0 and z >= 0:
        return "desert"
    if x < 0 and z < 0:
        return "swamp"
    return "canyon"


def in_river(x, z, margin=0.0):
    return ((abs(z) < RIVER_HALF + margin and abs(x) > RIVER_START - margin)
            or (abs(x) < RIVER_HALF + margin and abs(z) > RIVER_START - margin))


def near_base(x, z, margin):
    return any(math.hypot(x - bx, z - bz) < BASE_RADIUS + margin for bx, bz in BASES)


def segment_distance(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz)))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


# Dirt paths from every base toward the field.
PATHS = []
for _i in range(BASE_COUNT):
    _a = base_angle(_i)
    _r0, _r1 = BASE_RING_RADIUS - BASE_RADIUS + 2, FIELD_OUTER - 10
    PATHS.append((math.cos(_a) * _r0, math.sin(_a) * _r0, math.cos(_a) * _r1, math.sin(_a) * _r1))

# The canyon gorge runs along the diagonal of the canyon quarter.
GORGE_ANGLE = math.radians(-45)
GORGE_R0, GORGE_R1 = 290, 560
GORGE_HALF_WIDTH = 24


def near_path(x, z, margin):
    return any(segment_distance(x, z, *path) < 6 + margin for path in PATHS)


def in_gorge(x, z, margin=0.0):
    ax, az = math.cos(GORGE_ANGLE) * GORGE_R0, math.sin(GORGE_ANGLE) * GORGE_R0
    bx, bz = math.cos(GORGE_ANGLE) * GORGE_R1, math.sin(GORGE_ANGLE) * GORGE_R1
    return segment_distance(x, z, ax, az, bx, bz) < GORGE_HALF_WIDTH + 22 + margin


HILLS = []  # (x, z, sphere radius, height)


def hill_footprint(radius, height):
    return math.sqrt(radius * radius - (radius - height) ** 2)


def ground_y(x, z):
    """Height of the walkable ground at (x, z)."""
    y = 0.0
    for hx, hz, radius, height in HILLS:
        d2 = (x - hx) ** 2 + (z - hz) ** 2
        if d2 < radius * radius:
            y = max(y, height - radius + math.sqrt(radius * radius - d2))
    return y


def free_spot(x, z, margin):
    """True if decorations may be placed at (x, z)."""
    r = math.hypot(x, z)
    return (r < HALF_MAP - 34 - margin and r > INNER_RING + 6 + margin
            and not in_river(x, z, 5 + margin) and not near_base(x, z, 8 + margin)
            and not near_path(x, z, margin))


# Players appear here for a moment before they are moved to their base.
SPAWN_ANGLE = base_angle(0) + math.radians(360 / BASE_COUNT / 2)
SPAWN = (math.cos(SPAWN_ANGLE) * (BASE_RING_RADIUS + 30), math.sin(SPAWN_ANGLE) * (BASE_RING_RADIUS + 30))

TAKEN = [(SPAWN[0], SPAWN[1], 14)]  # (x, z, radius) of solid decorations, so they do not overlap


def claim(x, z, radius):
    if any(math.hypot(x - tx, z - tz) < radius + tr for tx, tz, tr in TAKEN):
        return False
    TAKEN.append((x, z, radius))
    return True


def random_spot(biome, r_min, r_max, margin, radius, tries=400):
    """A random free spot inside a biome quarter, or None."""
    quarter = {"jungle": (0, 90), "desert": (90, 180), "swamp": (180, 270), "canyon": (270, 360)}[biome]
    for _ in range(tries):
        angle = math.radians(random.uniform(*quarter))
        r = math.sqrt(random.uniform(r_min * r_min, r_max * r_max))
        x, z = math.cos(angle) * r, math.sin(angle) * r
        if not free_spot(x, z, margin):
            continue
        if biome == "canyon" and in_gorge(x, z):
            continue
        if claim(x, z, radius):
            return x, z
    return None


# --------------------------------------------------------------------------
# Ground, rivers, hills
# --------------------------------------------------------------------------
def build_ground():
    ground, water = [], []
    size = GROUND_HALF - RIVER_HALF
    center = RIVER_HALF + size / 2
    for name, sx, sz in (("jungle", 1, 1), ("desert", -1, 1), ("swamp", -1, -1), ("canyon", 1, -1)):
        color, material = BIOME_GROUND[name]
        ground.append(part(name.capitalize() + "Ground", (sx * center, -4, sz * center), (size, 8, size), color,
                           material))
    # The lava field around the volcano (also covers the river gaps near the center).
    ground.append(disc("LavaField", 0, 0.15, 0, INNER_RING + 8, 8, BASALT, "Basalt"))

    # Shallow rivers between the biomes. They are not part of Ground, so eggs never land in them.
    length = GROUND_HALF - RIVER_START
    middle = RIVER_START + length / 2
    for sx, sz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        swampy = (sx, sz) in ((-1, 0), (0, -1))
        bed_size = (length, 6, RIVER_HALF * 2 + 0.2) if sx else (RIVER_HALF * 2 + 0.2, 6, length)
        water_size = (length, 0.8, RIVER_HALF * 2) if sx else (RIVER_HALF * 2, 0.8, length)
        water.append(part("RiverBed", (sx * middle, -4.1, sz * middle), bed_size, SAND if not swampy else SWAMP_MUD,
                          "Sand" if not swampy else "Mud"))
        water.append(decor("River", (sx * middle, -0.6, sz * middle), water_size,
                           WATER if not swampy else SWAMP_WATER, "Glass", Transparency=0.35, Reflectance=0.1))

    # Bridges over the rivers.
    bridges = []
    for sx, sz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        for r in (330, 470, 610, 735):
            frame = Frame((sx * r, 0, sz * r), yaw(0) if sx else yaw(math.pi / 2))
            span = RIVER_HALF * 2 + 10
            ground.append(part("BridgeDeck", frame.at(0, 0.05, 0), (14, 0.7, span), WOOD, "WoodPlanks",
                               orientation=frame.rotation))
            for side in (-1, 1):
                bridges.append(part("BridgeRail", frame.at(side * 6.6, 2.4, 0), (0.6, 0.6, span), DARK_WOOD, "Wood",
                                    orientation=frame.rotation))
                for along in (-span / 2 + 0.6, 0, span / 2 - 0.6):
                    bridges.append(part("BridgePost", frame.at(side * 6.6, 1.3, along), (1, 3.2, 1), DARK_WOOD, "Wood",
                                        orientation=frame.rotation))

    # Hills: big balls sunk into the ground. They are walkable and eggs can land on them.
    hill_plan = {"jungle": 9, "desert": 10, "swamp": 6, "canyon": 8}
    for biome, count in hill_plan.items():
        color, material = BIOME_GROUND[biome]
        placed = 0
        attempts = 0
        while placed < count and attempts < 3000:
            attempts += 1
            radius = random.uniform(70, 150)
            height = random.uniform(7, 17) if biome != "swamp" else random.uniform(4, 8)
            foot = hill_footprint(radius, height)
            quarter = {"jungle": (0, 90), "desert": (90, 180), "swamp": (180, 270), "canyon": (270, 360)}[biome]
            angle = math.radians(random.uniform(*quarter))
            r = random.uniform(INNER_RING + foot + 14, HALF_MAP - 60)
            x, z = math.cos(angle) * r, math.sin(angle) * r
            if in_river(x, z, foot + 8) or near_base(x, z, foot + 10) or near_path(x, z, foot + 2):
                continue
            if biome == "canyon" and in_gorge(x, z, foot):
                continue
            if any(math.hypot(x - hx, z - hz) < foot + hill_footprint(hr, hh) - 12 for hx, hz, hr, hh in HILLS):
                continue
            HILLS.append((x, z, radius, height))
            shade = tuple(max(0, min(255, c + random.randint(-8, 8))) for c in color)
            ground.append(ball("Hill", (x, height - radius, z), radius, shade, material))
            placed += 1

    # Dirt paths from the bases to the field.
    for ax, az, bx, bz in PATHS:
        length = math.hypot(bx - ax, bz - az)
        angle = math.atan2((az + bz) / 2, (ax + bx) / 2)
        ground.append(part("Path", ((ax + bx) / 2, 0.03, (az + bz) / 2), (9, 0.16, length), DIRT, "Ground",
                           orientation=facing_center(angle), CanCollide=False))
    return ground, water, bridges


# --------------------------------------------------------------------------
# Volcano and lava fields
# --------------------------------------------------------------------------
def build_volcano():
    parts = []
    # Many thin tiers with a curved profile read as a cone, not as a staircase.
    steps = 22
    tiers = []
    for i in range(steps):
        t = i / (steps - 1)
        tiers.append((round(92 - (92 - 27) * (t ** 0.75), 1), 5))
    top = 0.0
    tops = []
    for i, (radius, height) in enumerate(tiers):
        last = i == len(tiers) - 1
        parts.append(cylinder("Tier%d" % (i + 1), 0, top, 0, radius, height, VOLCANO_ROCK,
                              "Basalt" if i % 2 == 0 else "Rock", tags=["Volcano"] if last else None))
        top += height
        tops.append(top)
    crater_radius = tiers[-1][0] - 5
    parts.append(part("Crater", (0, top + 0.2, 0), (0.8, crater_radius * 2, crater_radius * 2), LAVA_HOT, "Neon",
                      orientation=UPRIGHT, Shape="Cylinder", CanCollide=False, children=[
        {"name": "Fire", "className": "Fire", "properties": {"Size": 30, "Heat": 25}},
        light(LAVA, 6, 60),
    ]))
    # Rim rocks around the crater.
    for i in range(10):
        angle = i * math.tau / 10 + 0.2
        size = random.uniform(7, 11)
        parts.append(part("RimRock", (math.cos(angle) * (crater_radius + 2), top + size * 0.3,
                                      math.sin(angle) * (crater_radius + 2)), (size, size * 1.1, size), VOLCANO_ROCK,
                          "Basalt", orientation=mat_mul(yaw(angle), pitch(random.uniform(-0.3, 0.3)))))
    # Lava streams: a strip down every tier wall and across every terrace.
    for i in range(9):
        angle = i * math.tau / 9 + 0.35
        rotation = yaw(-angle)
        bottom = 0.0
        for step, (radius, height) in enumerate(tiers):
            x, z = math.cos(angle) * (radius + 0.2), math.sin(angle) * (radius + 0.2)
            width = 5 + (len(tiers) - step) * 0.5
            parts.append(decor("LavaFall", (x, bottom + height / 2, z), (1.2, height, width), LAVA, "Neon",
                               orientation=rotation))
            if step > 0:
                outer = tiers[step - 1][0]
                mid = (outer + radius) / 2
                parts.append(decor("LavaFlow", (math.cos(angle) * mid, bottom + 0.25, math.sin(angle) * mid),
                                   (outer - radius + 1.5, 0.5, width), LAVA, "Neon", orientation=rotation))
            bottom += height
        # The stream ends in a pool at the foot of the volcano.
        foot = tiers[0][0] + 9
        parts.append(part("LavaPool", (math.cos(angle) * foot, 0.3, math.sin(angle) * foot), (0.6, 22, 22), LAVA,
                          "Neon", orientation=UPRIGHT, Shape="Cylinder", CanCollide=False,
                          children=[light(LAVA, 3, 40)]))
    return parts, top


def build_lava_field():
    parts = []
    # Lava pools: eggs do not land in them (they are not in Ground).
    for _ in range(16):
        for _try in range(50):
            angle = random.uniform(0, math.tau)
            r = random.uniform(FIELD_INNER + 22, INNER_RING - 22)
            x, z = math.cos(angle) * r, math.sin(angle) * r
            radius = random.uniform(7, 15)
            if claim(x, z, radius + 3):
                children = [light(LAVA, 2.5, 36)] if random.random() < 0.6 else None
                parts.append(part("LavaPool", (x, 0.28, z), (0.4, radius * 2, radius * 2), LAVA, "Neon",
                                  orientation=UPRIGHT, Shape="Cylinder", CanCollide=False, children=children))
                parts.append(part("LavaPoolCore", (x, 0.32, z), (0.4, radius * 1.1, radius * 1.1), LAVA_HOT, "Neon",
                                  orientation=UPRIGHT, Shape="Cylinder", CanCollide=False, CanQuery=False))
                break
    # Glowing cracks (flat, eggs may land on them).
    for _ in range(46):
        angle = random.uniform(0, math.tau)
        r = random.uniform(FIELD_INNER, INNER_RING)
        parts.append(decor("LavaCrack", (math.cos(angle) * r, 0.2, math.sin(angle) * r),
                           (random.uniform(10, 30), 0.25, random.uniform(0.8, 1.8)), LAVA, "Neon",
                           orientation=yaw(random.uniform(0, math.pi))))
    # Obsidian spikes and scorched rocks.
    for _ in range(34):
        for _try in range(50):
            angle = random.uniform(0, math.tau)
            r = random.uniform(FIELD_INNER + 6, INNER_RING + 4)
            x, z = math.cos(angle) * r, math.sin(angle) * r
            if not claim(x, z, 5):
                continue
            height = random.uniform(8, 24)
            width = random.uniform(3, 6)
            tilt = mat_mul(yaw(random.uniform(0, math.tau)), pitch(random.uniform(-0.25, 0.25)))
            parts.append(part("ObsidianSpike", (x, height / 2 - 1, z), (width, height, width * 0.8), OBSIDIAN, "Glass",
                              orientation=tilt, Reflectance=0.15))
            parts.append(part("ObsidianSpike", (x + width * 0.6, height * 0.3 - 1, z + width * 0.3),
                              (width * 0.7, height * 0.6, width * 0.6), OBSIDIAN, "Basalt",
                              orientation=mat_mul(tilt, roll(0.2))))
            break
    return parts


# --------------------------------------------------------------------------
# Decorations
# --------------------------------------------------------------------------
def tree(x, z, height, trunk_radius, leaf_colors, canopy):
    y = ground_y(x, z) - 0.5
    parts = [cylinder("Trunk", x, y, z, trunk_radius, height, WOOD, "Wood")]
    for i in range(canopy):
        radius = random.uniform(0.3, 0.42) * height * (1 - i * 0.12) * (0.75 if canopy > 3 else 1)
        offset = trunk_radius * 2.2 if i else 0
        angle = random.uniform(0, math.tau)
        parts.append(decor("Leaves", (x + math.cos(angle) * offset * (1 + i * 0.4), y + height + radius * 0.35 - i * 2.5,
                                      z + math.sin(angle) * offset * (1 + i * 0.4)),
                           (radius * 2, radius * 2, radius * 2), random.choice(leaf_colors), "Grass", Shape="Ball",
                           CastShadow=True))
    return parts


def giant_tree(x, z):
    """A huge jungle tree with roots."""
    height = random.uniform(62, 84)
    parts = tree(x, z, height, random.uniform(5.5, 7.5), [LEAF, DARK_LEAF], 5)
    y = ground_y(x, z)
    for i in range(5):
        angle = i * math.tau / 5 + random.uniform(-0.3, 0.3)
        parts.append(part("Root", (x + math.cos(angle) * 8, y + 3, z + math.sin(angle) * 8), (4, 3, 15), WOOD, "Wood",
                          orientation=mat_mul(yaw(-angle + math.pi / 2), pitch(-0.45))))
    return parts


def bush(x, z, color, size):
    y = ground_y(x, z)
    return [decor("Bush", (x, y + size * 0.3, z), (size * 2, size * 2, size * 2), color, "Grass", Shape="Ball")]


def rock(x, z, size, color, material):
    y = ground_y(x, z)
    rotation = mat_mul(yaw(random.uniform(0, math.tau)), pitch(random.uniform(-0.2, 0.2)))
    return [part("Rock", (x, y + size * 0.3, z), (size * 1.3, size * 0.9, size), color, material,
                 orientation=rotation)]


def cactus(x, z):
    y = ground_y(x, z) - 0.3
    height = random.uniform(9, 16)
    parts = [cylinder("Cactus", x, y, z, 1.3, height, CACTUS, "Grass")]
    for side in (-1, 1):
        if random.random() < 0.8:
            arm_y = y + height * random.uniform(0.35, 0.6)
            parts.append(part("CactusArm", (x + side * 2.3, arm_y, z), (3.4, 1.6, 1.6), CACTUS, "Grass",
                              CanCollide=False))
            parts.append(cylinder("CactusArm", x + side * 3.6, arm_y, z, 0.8, height * 0.3, CACTUS, "Grass",
                                  CanCollide=False))
    return parts


def dead_tree(x, z):
    y = ground_y(x, z) - 0.5
    height = random.uniform(16, 28)
    turn = random.uniform(0, math.tau)
    parts = [cylinder("DeadTrunk", x, y, z, 1.6, height, DEAD_WOOD, "Wood")]
    for i in range(3):
        angle = turn + i * 2.1
        length = random.uniform(7, 12)
        rotation = mat_mul(yaw(angle), roll(0.7))
        dx, dy, dz = mat_vec(rotation, (length / 2, 0, 0))
        parts.append(part("DeadBranch", (x + dx, y + height * (0.55 + i * 0.14) + dy, z + dz), (length, 1, 1),
                          DEAD_WOOD, "Wood", orientation=rotation, CanCollide=False))
    if random.random() < 0.5:  # hanging moss
        parts.append(decor("Moss", (x, y + height * 0.8, z), (9, 5, 9), SWAMP_LEAF, "Grass", Shape="Ball",
                           Transparency=0.15))
    return parts


def mushroom(x, z, glowing):
    y = ground_y(x, z)
    height = random.uniform(3, 7)
    cap = part("MushroomCap", (x, y + height, z), (1.2, height * 1.1, height * 1.1), MUSHROOM,
               "Neon" if glowing else "SmoothPlastic", orientation=UPRIGHT, Shape="Cylinder", CanCollide=False,
               children=[light(MUSHROOM, 1.6, 22)] if glowing else None)
    return [cylinder("MushroomStem", x, y - 0.3, z, 0.6, height, BONE, "SmoothPlastic", CanCollide=False), cap]


def reeds(x, z):
    y = ground_y(x, z)
    parts = []
    for _ in range(3):
        height = random.uniform(5, 9)
        parts.append(decor("Reed", (x + random.uniform(-1.5, 1.5), y + height / 2 - 0.3, z + random.uniform(-1.5, 1.5)),
                           (0.4, height, 0.4), SWAMP_LEAF, "Grass"))
    return parts


def skeleton(x, z, scale):
    """A dinosaur skeleton half buried in the sand."""
    frame = Frame((x, ground_y(x, z), z), yaw(random.uniform(0, math.tau)))
    parts = []

    def bone(name, local, size, rotation=IDENTITY, collide=True):
        parts.append(part(name, frame.at(*[v * scale for v in local]), [v * scale for v in size], BONE, "Sandstone",
                          orientation=frame.turned(rotation), CanCollide=collide))

    for i in range(11):  # spine and tail
        along = -22 + i * 4.4
        thick = 2.2 - abs(i - 4) * 0.14
        bone("Spine", (0, 7.5 - max(0, i - 6) * 1.3, along), (thick, thick, 4.6))
    for i in range(6):  # ribs: two slanted bones that meet at the spine
        along = -18 + i * 4.4
        length = 9 - abs(i - 2.5) * 1.1
        for side in (-1, 1):
            bone("Rib", (side * length * 0.33, 7.3 - length * 0.42, along), (0.9, length, 0.9),
                 roll(side * 0.68))
    bone("Skull", (0, 7.2, -28.5), (5, 4.4, 8))
    bone("Jaw", (0, 4.3, -29), (4.2, 1, 7), pitch(0.25))
    bone("Horn", (0, 10, -30), (0.9, 3, 0.9), pitch(-0.3), collide=False)
    for side in (-1, 1):
        bone("Leg", (side * 3.4, 3, -14), (1.3, 7, 1.3), roll(side * 0.12))
        bone("Leg", (side * 3.4, 3, 4), (1.3, 7, 1.3), roll(side * 0.12))
    return parts


def ruins(x, z, mossy):
    """Broken columns, an arch and low walls."""
    color = MOSS_STONE if mossy else STONE
    frame = Frame((x, ground_y(x, z), z), yaw(random.uniform(0, math.tau)))
    parts = [part("RuinFloor", frame.at(0, 0.15, 0), (34, 0.5, 26), color, "Cobblestone",
                  orientation=frame.rotation, CanCollide=False)]
    for cx in (-13, -4.5, 4.5, 13):
        for cz in (-9, 9):
            height = random.choice([4, 9, 15, 15, 20])
            px, py, pz = frame.at(cx, 0, cz)
            parts.append(cylinder("Column", px, py - 0.3, pz, 1.7, height, color, "Marble"))
            if height >= 15:
                parts.append(part("Capital", frame.at(cx, height + 0.4, cz), (4.6, 1.4, 4.6), color, "Marble",
                                  orientation=frame.rotation))
    # An arch at one end and a fallen column.
    parts.append(part("Lintel", frame.at(-17, 16, 0), (4, 3, 24), color, "Cobblestone", orientation=frame.rotation))
    for cz in (-10, 10):
        parts.append(part("ArchPillar", frame.at(-17, 7.2, cz), (4, 15, 4), color, "Cobblestone",
                          orientation=frame.rotation))
    parts.append(part("FallenColumn", frame.at(8, 1.5, 15), (16, 3.2, 3.2), color, "Marble",
                      orientation=frame.turned(yaw(0.5)), Shape="Cylinder"))
    parts.append(part("BrokenWall", frame.at(17, 3, -2), (3, 7, 16), color, "Cobblestone",
                      orientation=frame.rotation))
    parts.append(part("BrokenWall", frame.at(17, 1.6, 9), (3, 4, 6), color, "Cobblestone",
                      orientation=frame.turned(yaw(0.2))))
    if mossy:
        parts.append(decor("Moss", frame.at(-17, 18, 3), (6, 3, 12), DARK_LEAF, "Grass", orientation=frame.rotation))
        parts.append(decor("Moss", frame.at(17, 6.6, -4), (4, 1.5, 9), DARK_LEAF, "Grass", orientation=frame.rotation))
    return parts


def build_jungle():
    parts = []
    for _ in range(3):
        spot = random_spot("jungle", FIELD_OUTER + 40, HALF_MAP - 90, 16, 26)
        if spot:
            parts += ruins(spot[0], spot[1], True)
    for _ in range(14):
        spot = random_spot("jungle", INNER_RING + 40, HALF_MAP - 60, 6, 13)
        if spot:
            parts += giant_tree(*spot)
    for _ in range(26):  # a few trees inside the field
        spot = random_spot("jungle", INNER_RING + 20, FIELD_OUTER, 3, 9)
        if spot:
            parts += tree(spot[0], spot[1], random.uniform(26, 40), random.uniform(2, 3), [LEAF, DARK_LEAF, LIGHT_LEAF], 3)
    for _ in range(120):  # thick jungle outside the field
        spot = random_spot("jungle", FIELD_OUTER, HALF_MAP - 40, 3, 7)
        if spot:
            parts += tree(spot[0], spot[1], random.uniform(24, 46), random.uniform(1.8, 3.2),
                          [LEAF, DARK_LEAF, LIGHT_LEAF], 3)
    for _ in range(90):
        spot = random_spot("jungle", INNER_RING + 10, HALF_MAP - 40, 0, 0)
        if spot:
            parts += bush(spot[0], spot[1], random.choice([LEAF, DARK_LEAF, LIGHT_LEAF]), random.uniform(2, 4.5))
    for _ in range(24):
        spot = random_spot("jungle", INNER_RING + 10, HALF_MAP - 40, 2, 5)
        if spot:
            parts += rock(spot[0], spot[1], random.uniform(4, 9), MOSS_STONE, "Slate")
    return parts


def build_desert():
    parts = []
    for i in range(6):
        spot = random_spot("desert", INNER_RING + 50, HALF_MAP - 90, 14, 30)
        if spot:
            parts += skeleton(spot[0], spot[1], random.uniform(0.9, 1.5))
    for _ in range(55):
        spot = random_spot("desert", INNER_RING + 15, HALF_MAP - 40, 2, 5)
        if spot:
            parts += cactus(*spot)
    for _ in range(40):
        spot = random_spot("desert", INNER_RING + 10, HALF_MAP - 40, 2, 6)
        if spot:
            parts += rock(spot[0], spot[1], random.uniform(4, 11), (196, 160, 110), "Sandstone")
    for _ in range(40):  # scattered bones
        spot = random_spot("desert", INNER_RING + 10, HALF_MAP - 40, 0, 2)
        if spot:
            y = ground_y(*spot)
            parts.append(part("Bone", (spot[0], y + 0.4, spot[1]), (random.uniform(3, 7), 0.8, 0.8), BONE, "Sandstone",
                              orientation=yaw(random.uniform(0, math.tau)), CanCollide=False))
    for _ in range(30):
        spot = random_spot("desert", INNER_RING + 10, HALF_MAP - 40, 0, 0)
        if spot:
            parts += bush(spot[0], spot[1], (150, 150, 84), random.uniform(1.5, 3))
    spot = random_spot("desert", FIELD_OUTER + 40, HALF_MAP - 100, 16, 26)
    if spot:
        parts += ruins(spot[0], spot[1], False)
    return parts


def build_swamp():
    parts = []
    for _ in range(2):
        spot = random_spot("swamp", FIELD_OUTER + 40, HALF_MAP - 90, 16, 26)
        if spot:
            parts += ruins(spot[0], spot[1], True)
    for _ in range(30):  # murky pools (flat, walkable)
        spot = random_spot("swamp", INNER_RING + 20, HALF_MAP - 50, 2, 0)
        if spot and ground_y(*spot) < 0.01:
            radius = random.uniform(10, 24)
            parts.append(decor("SwampPool", (spot[0], 0.1, spot[1]), (0.24, radius * 2, radius * 2), SWAMP_WATER,
                               "Glass", orientation=UPRIGHT, Shape="Cylinder", Transparency=0.25, Reflectance=0.12))
    for _ in range(70):
        spot = random_spot("swamp", INNER_RING + 15, HALF_MAP - 40, 2, 5)
        if spot:
            parts += dead_tree(*spot)
    for _ in range(40):
        spot = random_spot("swamp", FIELD_OUTER - 40, HALF_MAP - 40, 3, 7)
        if spot:
            parts += tree(spot[0], spot[1], random.uniform(20, 34), random.uniform(2, 3), [SWAMP_LEAF, DARK_LEAF], 3)
    for _ in range(110):
        spot = random_spot("swamp", INNER_RING + 10, HALF_MAP - 40, 0, 0)
        if spot:
            parts += reeds(*spot)
    for i in range(46):
        spot = random_spot("swamp", INNER_RING + 10, HALF_MAP - 40, 0, 2)
        if spot:
            parts += mushroom(spot[0], spot[1], i % 3 == 0)
    for _ in range(26):
        spot = random_spot("swamp", INNER_RING + 10, HALF_MAP - 40, 2, 5)
        if spot:
            parts += rock(spot[0], spot[1], random.uniform(4, 9), MOSS_STONE, "Slate")
    return parts


def build_canyon():
    parts = []
    # The gorge: two rows of tall rock walls with gaps, and stone arches across.
    direction = (math.cos(GORGE_ANGLE), math.sin(GORGE_ANGLE))
    rotation = facing_center(GORGE_ANGLE)
    steps = int((GORGE_R1 - GORGE_R0) / 38)
    for i in range(steps):
        r = GORGE_R0 + 19 + i * 38
        if i % 4 == 3:
            continue  # a gap to walk through
        for side in (-1, 1):
            thickness = random.uniform(16, 26)
            height = random.uniform(30, 58)
            offset = GORGE_HALF_WIDTH + thickness / 2 + random.uniform(-2, 3)
            # right vector of the frame = (sin, 0, -cos)
            x = direction[0] * r + math.sin(GORGE_ANGLE) * offset * side
            z = direction[1] * r - math.cos(GORGE_ANGLE) * offset * side
            wall_rotation = mat_mul(rotation, yaw(random.uniform(-0.12, 0.12)))
            parts.append(part("GorgeWall", (x, height / 2 - 2, z), (thickness, height, 40), RED_STONE, "Rock",
                              orientation=wall_rotation))
            parts.append(part("GorgeWallTop", (x, height + 3, z), (thickness * 0.7, 10, 28), DARK_RED_STONE,
                              "Sandstone", orientation=mat_mul(wall_rotation, yaw(0.2))))
        if i % 4 == 1:
            x, z = direction[0] * r, direction[1] * r
            parts.append(part("GorgeArch", (x, 34, z), (GORGE_HALF_WIDTH * 2 + 44, 9, 14), DARK_RED_STONE, "Rock",
                              orientation=rotation))
    for _ in range(46):  # rock spires
        spot = random_spot("canyon", INNER_RING + 20, HALF_MAP - 50, 3, 8)
        if spot:
            y = ground_y(*spot) - 1
            height = random.uniform(14, 40)
            width = random.uniform(6, 12)
            turn = yaw(random.uniform(0, math.tau))
            parts.append(part("Spire", (spot[0], y + height / 2, spot[1]), (width, height, width * 0.9), RED_STONE,
                              "Rock", orientation=turn))
            parts.append(part("SpireTop", (spot[0], y + height + 2, spot[1]), (width * 1.4, 4.5, width * 1.3),
                              DARK_RED_STONE, "Sandstone", orientation=mat_mul(turn, yaw(0.5))))
    for _ in range(4):  # natural arches
        spot = random_spot("canyon", INNER_RING + 60, HALF_MAP - 90, 10, 22)
        if spot:
            frame = Frame((spot[0], ground_y(*spot), spot[1]), yaw(random.uniform(0, math.tau)))
            for side in (-1, 1):
                parts.append(part("ArchLeg", frame.at(side * 14, 11, 0), (9, 24, 10), RED_STONE, "Rock",
                                  orientation=frame.turned(roll(side * -0.12))))
            parts.append(part("ArchTop", frame.at(0, 25, 0), (40, 8, 11), DARK_RED_STONE, "Rock",
                              orientation=frame.rotation))
    for _ in range(60):
        spot = random_spot("canyon", INNER_RING + 10, HALF_MAP - 40, 2, 5)
        if spot:
            parts += rock(spot[0], spot[1], random.uniform(4, 11), random.choice([RED_STONE, DARK_RED_STONE]), "Rock")
    for _ in range(22):
        spot = random_spot("canyon", INNER_RING + 10, HALF_MAP - 40, 2, 5)
        if spot:
            parts += dead_tree(*spot)
    for _ in range(30):
        spot = random_spot("canyon", INNER_RING + 10, HALF_MAP - 40, 0, 0)
        if spot:
            parts += bush(spot[0], spot[1], (132, 140, 80), random.uniform(1.5, 3))
    return parts


def build_ring_markers():
    """Standing stones on the border of the middle ring (rarer eggs inside)."""
    parts = []
    count = 40
    for i in range(count):
        angle = (i + 0.5) * math.tau / count
        x, z = math.cos(angle) * MIDDLE_RING, math.sin(angle) * MIDDLE_RING
        if in_river(x, z, 8) or (biome_at(x, z) == "canyon" and in_gorge(x, z)):
            continue
        if not claim(x, z, 4):
            continue
        y = ground_y(x, z) - 1
        parts.append(part("RingStone", (x, y + 6, z), (3.4, 12, 2.4), STONE, "Slate",
                          orientation=mat_mul(facing_center(angle), roll(random.uniform(-0.08, 0.08)))))
        parts.append(decor("RingRune", (x - math.cos(angle) * 1.3, y + 8, z - math.sin(angle) * 1.3), (1.4, 2.4, 0.3),
                           (120, 200, 255), "Neon", orientation=facing_center(angle)))
    return parts


# --------------------------------------------------------------------------
# Bases
# --------------------------------------------------------------------------
def build_bases():
    parts = []
    for index in range(BASE_COUNT):
        angle = base_angle(index)
        x, z = BASES[index]
        frame = Frame((x, BASE_TOP, z), facing_center(angle))  # -Z of the frame points at the volcano
        base = [
            # Invisible marker the scripts look for.
            part("Plot", (x, BASE_TOP, z), (4, 0.2, 4), SAND, orientation=frame.rotation, tags=["BasePlot"],
                 attributes={"BaseIndex": index + 1}, Transparency=1, CanCollide=False, CanQuery=False,
                 CanTouch=False),
            disc("Floor", x, BASE_TOP, z, BASE_RADIUS, 1.2, SAND, "Sand"),
            disc("FloorRim", x, BASE_TOP - 0.25, z, BASE_RADIUS + 1.6, 1.0, DARK_WOOD, "Wood"),
        ]
        # A low fence all around, open toward the volcano.
        posts = 28
        gap = math.radians(34)  # half of the opening
        previous = None
        for i in range(posts + 1):
            local = gap + i * (math.tau - gap * 2) / posts  # angle around the base, 0 = toward the volcano
            px, pz = math.sin(local) * (BASE_RADIUS - 1), -math.cos(local) * (BASE_RADIUS - 1)
            base.append(part("FencePost", frame.at(px, 1.6, pz), (1.1, 3.2, 1.1), WOOD, "Wood",
                             orientation=frame.rotation))
            if previous:
                mx, mz = (px + previous[0]) / 2, (pz + previous[1]) / 2
                length = math.hypot(px - previous[0], pz - previous[1])
                turn = math.atan2(px - previous[0], pz - previous[1])
                base.append(part("FenceRail", frame.at(mx, 2.2, mz), (0.5, 0.6, length), DARK_WOOD, "Wood",
                                 orientation=frame.turned(yaw(turn))))
            previous = (px, pz)
        # The gate: two tall posts with torches and a beam. The name sign floats above it.
        for side in (-1, 1):
            gx, gz = math.sin(gap) * (BASE_RADIUS - 1) * side, -math.cos(gap) * (BASE_RADIUS - 1)
            base.append(part("GatePost", frame.at(gx, 6, gz), (2, 12, 2), DARK_WOOD, "Wood",
                             orientation=frame.rotation))
            base.append(part("Torch", frame.at(gx, 12.8, gz), (1.4, 1.6, 1.4), LAVA_HOT, "Neon",
                             orientation=frame.rotation, CanCollide=False, children=[
                {"name": "Fire", "className": "Fire", "properties": {"Size": 4, "Heat": 6}},
                light(LAVA_HOT, 1.4, 26),
            ]))
        beam = math.sin(gap) * (BASE_RADIUS - 1) * 2 + 4
        base.append(part("GateBeam", frame.at(0, 11.2, -math.cos(gap) * (BASE_RADIUS - 1)), (beam, 1.4, 1.6),
                         DARK_WOOD, "Wood", orientation=frame.rotation, CanCollide=False))
        parts.append(folder("Base%d" % (index + 1), base))
    return parts


# --------------------------------------------------------------------------
# Mountains and the invisible wall around the valley
# --------------------------------------------------------------------------
def build_boundary():
    mountains, walls = [], []
    count = 52
    for i in range(count):
        angle = (i + 0.5) * math.tau / count
        r = HALF_MAP + 62 + random.uniform(-8, 14)
        x, z = math.cos(angle) * r, math.sin(angle) * r
        color, material = BIOME_MOUNTAIN[biome_at(x, z)]
        height = random.uniform(110, 220)
        width = 2 * r * math.tan(math.pi / count) + 34
        rotation = mat_mul(facing_center(angle), yaw(random.uniform(-0.15, 0.15)))
        mountains.append(part("Mountain", (x, height / 2 - 6, z), (width, height, 120), color, material,
                              orientation=rotation))
        mountains.append(part("MountainPeak", (x + math.cos(angle) * 16, height + 20, z + math.sin(angle) * 16),
                              (width * 0.62, 70, 80), color, material,
                              orientation=mat_mul(rotation, mat_mul(yaw(0.5), roll(random.uniform(-0.2, 0.2))))))
        if height > 170:
            mountains.append(part("SnowCap", (x + math.cos(angle) * 16, height + 54, z + math.sin(angle) * 16),
                                  (width * 0.5, 16, 62), SNOW, "Snow",
                                  orientation=mat_mul(rotation, yaw(0.5))))
        # Foothill in front, so the valley edge is not a flat wall.
        mountains.append(part("Foothill", (math.cos(angle) * (HALF_MAP + 4), 14, math.sin(angle) * (HALF_MAP + 4)),
                              (width * 0.9, 44, 46), color, material,
                              orientation=mat_mul(rotation, pitch(-0.35))))
    segments = 48
    for i in range(segments):
        angle = (i + 0.5) * math.tau / segments
        r = HALF_MAP - 22
        width = 2 * r * math.tan(math.pi / segments) + 4
        walls.append(part("Wall", (math.cos(angle) * r, 150, math.sin(angle) * r), (width, 320, 2), STONE,
                          orientation=facing_center(angle), Transparency=1, CanQuery=False, CastShadow=False))
    return mountains, walls


def build():
    ground, water, bridges = build_ground()
    volcano, volcano_top = build_volcano()
    lava_field = build_lava_field()
    markers = build_ring_markers()
    jungle = build_jungle()
    desert = build_desert()
    swamp = build_swamp()
    canyon = build_canyon()
    bases = build_bases()
    mountains, walls = build_boundary()

    spawn = part("Spawn", (SPAWN[0], 0.3, SPAWN[1]), (12, 0.6, 12), STONE, "Slate",
                 class_name="SpawnLocation", Neutral=True, Duration=0, orientation=facing_center(SPAWN_ANGLE))

    root = folder("Map", [
        folder("Ground", ground),
        folder("Water", water + bridges),
        # Always loaded for every player, so the skyline never pops in.
        model("Volcano", volcano, ModelStreamingMode="Persistent"),
        model("Mountains", mountains, ModelStreamingMode="Persistent"),
        folder("LavaField", lava_field),
        folder("Bases", bases),
        folder("Decor", [
            folder("RingStones", markers),
            folder("Jungle", jungle),
            folder("Desert", desert),
            folder("Swamp", swamp),
            folder("Canyon", canyon),
        ]),
        folder("Boundary", walls + [spawn]),
    ])
    root.pop("name")
    return root, volcano_top


def count_parts(node):
    return (1 if node.get("className") not in ("Folder", "Model") else 0) + sum(
        count_parts(child) for child in node.get("children", []))


if __name__ == "__main__":
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(repo, "map", "Map.model.json")
    result, top = build()
    with open(out, "w") as f:
        json.dump(result, f, separators=(",", ":"))
        f.write("\n")
    print("Wrote %s: %d instances, %d hills, volcano top at %.0f" % (out, count_parts(result), len(HILLS), top))
