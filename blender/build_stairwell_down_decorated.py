"""
Decorated down-stairwell tile (room_stairwell_down_decorated.glb) built from
the Pripyat pack on top of build_rooms.build_stairwell_down(). The flight,
well walls, lip and StairUse keep their names and authored NW position;
MapGenerator moves them to the room centre and rebuilds the floor slabs
around the hole at runtime.

Floor dressing is laid for the runtime layout: the centre 4 x 4 m is cut into
strips that stop at the runtime hole (x -1.44..1.44, y -1.0..1.75 in Blender
axes), and the piece covering the hole is named NoCol_DebrisTile so
_clear_debris_in_hole deletes it. The tiles over the authored NW well stay:
the runtime floor covers that corner once the well has moved.

Run:  blender -b -P blender/build_stairwell_down_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pripyat_room_base import *

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_stairwell_down_decorated.glb"
HOLE = (-1.44, 1.44, -1.0, 1.75)   # runtime well opening (x0, x1, y0, y1)
LINO = "SM_Floor_Linoleum_2m"


def piece(root, name, x0, x1, y0, y1):
    prop(ARCH, LINO, name, 0, x=(x0 + x1) / 2, y=(y0 + y1) / 2, z=0.002, raw=True, collide=False,
         sx=(x1 - x0) / 2, sy=(y1 - y0) / 2, strip_above=0.028, parent=root)


def centre_floor(root):
    hx0, hx1, hy0, hy1 = HOLE
    for k, x in enumerate((-2, -1, 0, 1)):
        piece(root, f"FloorTile_CS{k}", x, x + 1, -2, hy0)
        piece(root, f"FloorTile_CN{k}", x, x + 1, hy1, 2)
    for k in range(3):
        y0 = hy0 + (hy1 - hy0) * k / 3; y1 = hy0 + (hy1 - hy0) * (k + 1) / 3
        piece(root, f"FloorTile_CW{k}", -2, hx0, y0, y1)
        piece(root, f"FloorTile_CE{k}", hx1, 2, y0, y1)
    piece(root, "DebrisTile_Hole", hx0, hx1, hy0, hy1)


def build():
    root = legacy_room("build_stairwell_down")
    floor_tiles(root, LINO, skip=lambda x, y: abs(x) < 2 and abs(y) < 2)
    centre_floor(root)
    wallpaper(root, "SM_Wall_Wallpaper_A")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    HW, AB = "Hallway", "Abandonment"

    # NE: lift on the north wall, mailbox blocks on the east wall.
    P(ARCH, "SM_Elevator_Door", "ElevatorDoor", 0, x=3.6, ymax=INNER - 0.002, z=0.0, sz=2.36 / 2.5, collide=False)
    P(HW, "SM_Doormat", "Doormat", 0, x=3.6, y=4.85, collide=False, z=FZ)
    P(ARCH, "SM_Mailboxes_Block", "Mailboxes", -90, xmax=INNER - 0.002, y=2.9, z=0.95)
    P(ARCH, "SM_Mailboxes_Block", "Mailboxes2", -90, xmax=INNER - 0.002, y=3.75, z=0.95)
    P(AB, "SM_Newspaper_Stack", "Newspapers", -30, x=4.6, y=2.6, collide=False, z=FZ)

    # SE: a flat's glazed door on the south wall, shoe cabinet and umbrella.
    P(HW, "SM_Door_Interior_Glass", "FlatDoor", 180, x=3.6, ymin=-INNER + 0.002, z=0.0, collide=False)
    P(HW, "SM_Doormat", "DoormatS", 0, x=3.6, y=-4.95, collide=False, z=FZ)
    P(HW, "SM_ShoeCabinet", "ShoeCabinet", -90, xmax=Eb, y=-4.4, z=FZ)
    P(HW, "SM_Umbrella", "Umbrella", -20, x=4.6, y=-3.2, collide=False, z=FZ)
    P(HW, "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=-2.15, z=0.72, collide=False)

    # SW: stairwell window, meter panel, the gas masks somebody dumped, rubble.
    P(ARCH, "SM_Window_DoubleFrame", "Window", 90, xmin=-INNER + 0.002, y=-3.6, z=0.72, collide=False)
    P(HW, "SM_ElectricMeter_Panel", "MeterPanel", 180, x=-2.4, ymin=-INNER + 0.002, z=1.0, collide=False)
    P(AB, "SM_GasMask_Pile", "GasMaskPile", 30, x=-3.6, y=-3.5, collide=False, z=FZ, scale=0.8)
    P(AB, "SM_Debris_Pile", "DebrisPile", -15, x=-4.6, y=-5.0, collide=False, z=FZ, scale=0.8)
    P(AB, "SM_Chair_Broken", "ChairBroken", 80, x=-2.8, y=-4.8, collide=False, z=FZ)

    P(ARCH, "SM_CeilingLamp_Bare", "CeilingLamp", 0, x=3.0, y=-2.9, z=WALL_H - 0.63, collide=False)
    return root


if __name__ == "__main__":
    r = build()
    check()
    export(r, OUT)
