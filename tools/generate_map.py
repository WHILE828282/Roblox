"""
generate_map.py
Generates map/Map.model.json for Dino Raiders: the volcano in the center,
the egg field with its three rings, six player bases and decorations.

Run from the repository root after changing the layout:
    python tools/generate_map.py

Scripts find important parts by CollectionService tags:
  Volcano  - top of the volcano (eggs fly out of it)
  BasePlot - a player's base (attribute BaseIndex)
Eggs only land on parts inside Map/Ground.
"""

import json
import math
import os
import random

random.seed(7)

BASE_COUNT = 6
BASE_RING_RADIUS = 315
BASE_SIZE = 72
HALF_MAP = 420
INNER_RING = 110  # must match Config.RingRadii.Inner
MIDDLE_RING = 180  # must match Config.RingRadii.Middle

GRASS = (95, 160, 70)
DIRT = (165, 130, 85)
ASH = (70, 60, 60)
ROCK = (60, 55, 55)
LAVA = (255, 90, 20)
SAND = (225, 205, 160)
WOOD = (110, 75, 45)
LEAF = (60, 140, 60)
DARK_LEAF = (40, 110, 50)
STONE = (130, 130, 135)

IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
# Rotates a Cylinder (axis X) so its axis points up (Y): a flat disc / pillar.
UPRIGHT = [[0, -1, 0], [1, 0, 0], [0, 0, 1]]


def cframe(x, y, z, orientation=IDENTITY):
    return {"CFrame": {"position": [x, y, z], "orientation": orientation}}


def part(name, center, size, color, material="SmoothPlastic", tags=None, attributes=None,
         orientation=IDENTITY, children=None, class_name="Part", **extra):
    props = {
        "Anchored": True,
        "Size": list(size),
        "CFrame": cframe(*center, orientation=orientation),
        "Color": [c / 255 for c in color],
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


def disc(name, x, top_y, z, radius, thickness, color, material, **extra):
    """Flat round part whose top surface is at top_y."""
    return part(name, (x, top_y - thickness / 2, z), (thickness, radius * 2, radius * 2), color, material,
                orientation=UPRIGHT, Shape="Cylinder", **extra)


def folder(name, children):
    return {"name": name, "className": "Folder", "children": children}


def base_centers():
    centers = []
    for i in range(BASE_COUNT):
        angle = math.radians(i * 360 / BASE_COUNT + 30)
        centers.append((math.cos(angle) * BASE_RING_RADIUS, math.sin(angle) * BASE_RING_RADIUS))
    return centers


def far_from_bases(x, z, margin):
    return all(math.hypot(x - bx, z - bz) > BASE_SIZE / 2 + margin for bx, bz in base_centers())


def build():
    ground = [
        part("Ground", (0, -1, 0), (HALF_MAP * 2, 2, HALF_MAP * 2), GRASS, "Grass"),
        disc("MiddleRing", 0, 0.05, 0, MIDDLE_RING, 0.4, DIRT, "Ground", CanCollide=False),
        disc("InnerRing", 0, 0.1, 0, INNER_RING, 0.4, ASH, "Basalt", CanCollide=False),
    ]

    # Volcano: stacked rock tiers with a lava crater on top.
    volcano = []
    top = 0
    tiers = [(44, 14), (34, 14), (24, 14), (15, 12)]
    for i, (radius, height) in enumerate(tiers):
        volcano.append(part("Tier%d" % (i + 1), (0, top + height / 2, 0), (height, radius * 2, radius * 2), ROCK,
                            "Basalt", orientation=UPRIGHT, Shape="Cylinder",
                            tags=["Volcano"] if i == len(tiers) - 1 else None))
        top += height
    volcano.append(disc("Crater", 0, top + 0.3, 0, 11, 0.6, LAVA, "Neon", CanCollide=False, children=[
        {"name": "Fire", "className": "Fire", "properties": {"Size": 25, "Heat": 25}},
        {"name": "Smoke", "className": "Smoke", "properties": {"Size": 30, "RiseVelocity": 12, "Opacity": 0.15}},
        {"name": "Glow", "className": "PointLight", "properties": {"Range": 60, "Brightness": 3, "Color": [1, 0.5, 0.2]}},
    ]))
    # Lava streams down the sides.
    for i in range(6):
        angle = i * math.pi / 3 + 0.3
        for step, (radius, height) in enumerate(tiers[:-1]):
            y = sum(h for _, h in tiers[: step + 1]) - height / 2
            volcano.append(part("LavaFlow", (math.cos(angle) * (radius - 0.5), y, math.sin(angle) * (radius - 0.5)),
                                (3, height, 3), LAVA, "Neon", CanCollide=False))
    # Glowing cracks in the inner ring.
    for i in range(14):
        angle = random.uniform(0, math.pi * 2)
        radius = random.uniform(55, INNER_RING - 10)
        length = random.uniform(8, 20)
        yaw = random.uniform(0, math.pi)
        c, s = math.cos(yaw), math.sin(yaw)
        ground.append(part("LavaCrack", (math.cos(angle) * radius, 0.2, math.sin(angle) * radius), (length, 0.3, 1.2),
                           LAVA, "Neon", orientation=[[c, 0, s], [0, 1, 0], [-s, 0, c]], CanCollide=False))

    # Player bases.
    bases = []
    for index, (x, z) in enumerate(base_centers(), start=1):
        bases.append(part("Base%d" % index, (x, 0.25, z), (BASE_SIZE, 0.5, BASE_SIZE), SAND, "Sand",
                          tags=["BasePlot"], attributes={"BaseIndex": index}))
        for cx in (-1, 1):
            for cz in (-1, 1):
                bases.append(part("Post", (x + cx * BASE_SIZE / 2, 3, z + cz * BASE_SIZE / 2), (2, 6, 2), WOOD, "Wood"))

    # Decorations: jungle trees outside the field, rocks in the middle ring.
    decor = []
    placed = 0
    while placed < 70:
        x, z = random.uniform(-HALF_MAP + 10, HALF_MAP - 10), random.uniform(-HALF_MAP + 10, HALF_MAP - 10)
        distance = math.hypot(x, z)
        if distance < 200 or not far_from_bases(x, z, 14):
            continue
        height = random.uniform(10, 18)
        leaf = random.choice([LEAF, DARK_LEAF])
        decor.append(part("Trunk", (x, height / 2, z), (2.5, height, 2.5), WOOD, "Wood"))
        decor.append(part("Leaves", (x, height + 3, z), (12, 6, 12), leaf, "Grass"))
        decor.append(part("Leaves", (x, height + 7, z), (7, 4, 7), leaf, "Grass"))
        placed += 1
    for _ in range(18):
        angle = random.uniform(0, math.pi * 2)
        radius = random.uniform(INNER_RING + 15, MIDDLE_RING - 5)
        size = random.uniform(4, 9)
        decor.append(part("Rock", (math.cos(angle) * radius, size / 2 - 0.5, math.sin(angle) * radius),
                          (size, size * 0.8, size * 1.2), STONE, "Slate"))
    for _ in range(25):  # ferns (no collision)
        x, z = random.uniform(-260, 260), random.uniform(-260, 260)
        if math.hypot(x, z) < MIDDLE_RING:
            continue
        decor.append(part("Fern", (x, 1, z), (4, 2, 4), DARK_LEAF, "Grass", CanCollide=False))

    # Invisible walls around the map.
    walls = []
    for sx, sz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        size = (2, 120, HALF_MAP * 2) if sx else (HALF_MAP * 2, 120, 2)
        walls.append(part("Wall", (sx * HALF_MAP, 60, sz * HALF_MAP), size, STONE, Transparency=1))

    spawn = part("Spawn", (HALF_MAP - 30, 0.5, HALF_MAP - 30), (10, 1, 10), STONE, "Slate",
                 class_name="SpawnLocation", Neutral=True, Duration=0)

    model = folder("Map", [
        folder("Ground", ground),
        folder("Volcano", volcano),
        folder("Bases", bases),
        folder("Decor", decor),
        folder("Boundary", walls + [spawn]),
    ])
    model.pop("name")
    return model


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "map", "Map.model.json")
    model = build()
    with open(out, "w") as f:
        json.dump(model, f, indent=1)
        f.write("\n")
    print("Wrote", out)
