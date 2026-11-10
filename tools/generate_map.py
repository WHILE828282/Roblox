"""
generate_map.py
Generates map/Map.model.json: the whole 10-level obby course as a Rojo model.

Run from the repository root after changing the layout:
    python tools/generate_map.py

The game logic finds map objects by CollectionService tags, so every special
part below gets the same tags you would add by hand in Studio:
  Checkpoint (+ Stage attribute), Finish, Coin, KillPart, Spinner, FadingPlatform

The course runs forward along -Z (the direction a character faces by default).
"""

import json
import os

COURSE_HEIGHT = 30  # top surface height of the start pad
THICKNESS = 1  # platform thickness

# Colors (RGB 0-255)
WHITE = (235, 235, 240)
STONE = (120, 125, 140)
GREEN = (80, 205, 120)
GOLD = (255, 200, 40)
RED = (230, 50, 50)
LAVA = (255, 110, 20)
BLUE = (88, 140, 255)
PURPLE = (160, 100, 255)
CYAN = (60, 200, 230)
PINK = (255, 105, 180)
ORANGE = (255, 150, 50)

LEVEL_COLORS = [BLUE, CYAN, PURPLE, ORANGE, PINK, BLUE, CYAN, PURPLE, ORANGE, PINK]


def cframe(x, y, z):
    return {"CFrame": {"position": [x, y, z], "orientation": [[1, 0, 0], [0, 1, 0], [0, 0, 1]]}}


def part(name, center, size, color, material="SmoothPlastic", tags=None, attributes=None,
         class_name="Part", children=None, **extra):
    props = {
        "Anchored": True,
        "Size": list(size),
        "CFrame": cframe(*center),
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


def sign(text, color, height=4):
    """Floating text above a pad (BillboardGui)."""
    return {
        "name": "Sign",
        "className": "BillboardGui",
        "properties": {
            "Size": {"UDim2": [[0, 220], [0, 60]]},
            "StudsOffset": [0, height, 0],
            "MaxDistance": 150,
        },
        "children": [{
            "name": "Text",
            "className": "TextLabel",
            "properties": {
                "Size": {"UDim2": [[1, 0], [1, 0]]},
                "BackgroundTransparency": 1,
                "Text": text,
                "TextScaled": True,
                "Font": "GothamBold",
                "TextColor3": [c / 255 for c in color],
                "TextStrokeTransparency": 0.3,
            },
        }],
    }


class Course:
    def __init__(self):
        self.edge = 0.0  # z of the far edge of the last thing placed
        self.top = COURSE_HEIGHT  # top surface height of the last platform
        self.folders = []
        self.items = None
        self.count = 0

    def folder(self, name):
        self.items = []
        self.folders.append({"name": name, "className": "Folder", "children": self.items})

    def add(self, node):
        self.count += 1
        self.items.append(node)
        return node

    def platform(self, depth, width, gap, x=0.0, dy=0.0, color=WHITE, name="Platform", **kw):
        """Places a platform `gap` studs after the previous one; returns its center."""
        self.top += dy
        cz = self.edge - gap - depth / 2
        cy = self.top - THICKNESS / 2
        self.add(part(name, (x, cy, cz), (width, THICKNESS, depth), color, **kw))
        self.edge = cz - depth / 2
        return x, self.top, cz

    def coin(self, x, top, z, value=1):
        attrs = {"Value": value} if value != 1 else None
        self.add(part("Coin", (x, top + 3, z), (0.4, 2.5, 2.5), GOLD, material="Neon",
                      tags=["Coin"], attributes=attrs, Shape="Cylinder", CanCollide=False))

    def checkpoint(self, stage, gap=5):
        x, top, z = self.platform(12, 12, gap, color=GREEN, name="Checkpoint%d" % stage,
                                  tags=["Checkpoint"], attributes={"Stage": stage},
                                  children=[sign("Level %d" % (stage + 1), GREEN)])
        return x, top, z


def build():
    c = Course()

    # Start: a SpawnLocation that is also checkpoint Stage 0.
    c.folder("Start")
    c.add(part("Start", (0, COURSE_HEIGHT - 0.5, -6), (14, 1, 14), GREEN,
               class_name="SpawnLocation", tags=["Checkpoint"], attributes={"Stage": 0},
               children=[sign("Level 1", GREEN, 5)], Duration=0, Neutral=True))
    c.edge = -13

    # Level 1: easy jumps
    c.folder("Level01")
    for i in range(5):
        x, top, z = c.platform(7, 7, 5, x=[0, 2, -2, 0, 2][i], color=LEVEL_COLORS[0])
        if i % 2 == 1:
            c.coin(x, top, z)
    c.checkpoint(1)

    # Level 2: staircase up
    c.folder("Level02")
    for i in range(6):
        x, top, z = c.platform(6, 6, 5, x=[0, 3, 0, -3, 0, 3][i], dy=2.5, color=LEVEL_COLORS[1])
        if i in (2, 5):
            c.coin(x, top, z)
    c.checkpoint(2)

    # Level 3: zig-zag narrow beams
    c.folder("Level03")
    for i in range(5):
        x, top, z = c.platform(14, 2, 2, x=3 if i % 2 == 0 else -3, color=LEVEL_COLORS[2], name="Beam")
        if i % 2 == 0:
            c.coin(x, top, z)
    c.checkpoint(3)

    # Level 4: long floor with lava strips to jump over
    c.folder("Level04")
    x, top, z = c.platform(70, 10, 4, color=LEVEL_COLORS[3], name="Floor")
    start = z + 35
    for i in range(6):
        sz = start - 10 - i * 10
        c.add(part("LavaStrip", (0, top + 0.6, sz), (10, 1.2, 1.5), RED, material="Neon", tags=["KillPart"]))
        c.coin(0, top, sz - 5)
    c.checkpoint(4)

    # Level 5: small pillars
    c.folder("Level05")
    for i in range(7):
        x, top, z = c.platform(3.5, 3.5, 6, x=[0, 3, -3, 0, 4, -2, 0][i], dy=[0, 1, -1, 1, 0, 1, -1][i],
                               color=LEVEL_COLORS[4], name="Pillar")
        if i in (3, 6):
            c.coin(x, top, z, value=2)
    c.checkpoint(5)

    # Level 6: spinning lava bars
    c.folder("Level06")
    for speed in (70, -90):
        x, top, z = c.platform(26, 26, 5, color=LEVEL_COLORS[5], name="SpinnerFloor")
        c.add(part("SpinnerBar", (0, top + 1.5, z), (24, 1, 1), RED, material="Neon",
                   tags=["Spinner", "KillPart"], attributes={"Speed": speed}, CanCollide=False))
        c.coin(8, top, z - 8)
    c.checkpoint(6)

    # Level 7: platforms that fade away after you step on them
    c.folder("Level07")
    for i in range(6):
        x, top, z = c.platform(6, 6, 5, x=[0, 4, -4, 0, 4, -4][i], color=LEVEL_COLORS[6],
                               name="FadingPlatform", tags=["FadingPlatform"])
        if i == 3:
            c.coin(x, top, z, value=3)
    c.checkpoint(7)

    # Level 8: climb a tower with a truss, then drop down
    c.folder("Level08")
    x, top, z = c.platform(12, 12, 5, color=LEVEL_COLORS[7], name="Base")
    tower_height = 16
    tower_depth = 10
    tower_z = c.edge - tower_depth / 2
    c.add(part("Tower", (0, top + tower_height / 2, tower_z), (12, tower_height, tower_depth), STONE, material="Slate"))
    c.add(part("ClimbTruss", (0, top + tower_height / 2, c.edge + 1), (2, tower_height, 2), STONE,
               class_name="TrussPart", material="DiamondPlate"))
    c.coin(0, top + tower_height, tower_z)
    c.edge -= tower_depth
    c.top = top + tower_height
    for i in range(4):
        c.platform(6, 6, 5, x=[2, -2, 2, 0][i], dy=-3, color=LEVEL_COLORS[7])
    c.checkpoint(8)

    # Level 9: narrow bridge guarded by fast spinners
    c.folder("Level09")
    x, top, z = c.platform(66, 3, 4, color=LEVEL_COLORS[8], name="Bridge")
    for i, speed in enumerate((90, -110, 130)):
        sz = z + 33 - 15 - i * 18
        c.add(part("SpinnerBar", (0, top + 1.5, sz), (10, 1, 1), RED, material="Neon",
                   tags=["Spinner", "KillPart"], attributes={"Speed": speed}, CanCollide=False))
        c.coin(0, top, sz - 9, value=2)
    c.checkpoint(9)

    # Level 10: final climb mixing fading and solid steps, then the finish
    c.folder("Level10")
    for i in range(8):
        fading = i % 2 == 1
        x, top, z = c.platform(5, 5, 6, x=[0, 3, -3, 3, -3, 3, -3, 0][i], dy=1.5,
                               color=LEVEL_COLORS[9] if not fading else WHITE,
                               name="FadingPlatform" if fading else "Step",
                               tags=["FadingPlatform"] if fading else None)
        if i == 7:
            c.coin(x, top, z, value=5)
    x, top, z = c.platform(16, 16, 6, color=GOLD, material="Neon", name="Finish", tags=["Finish"],
                           children=[sign("FINISH", GOLD, 6)])

    # Lava floor under the whole course: falling = respawn at your checkpoint.
    length = -c.edge + 80
    lava = part("LavaFloor", (0, 5, c.edge / 2), (260, 1, length), LAVA, material="CrackedLava", tags=["KillPart"])
    c.folders.insert(0, {"name": "Hazards", "className": "Folder", "children": [lava]})

    return {"className": "Folder", "children": c.folders}, c.count + 1


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    model, count = build()
    out = os.path.join(root, "map", "Map.model.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump(model, f, indent=1)
        f.write("\n")
    print("Wrote %s (%d parts)" % (out, count))
