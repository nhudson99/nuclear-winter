"""
Decorated up-stairwell tile (room_stairwell_up_decorated.glb) built from the
Pripyat pack on top of build_rooms.build_stairwell_up(): the flight, landing,
hatch, StairUse marker and signs keep their names and authored corner position
(MapGenerator._center_stair_flight moves them to the room centre at runtime).
New props stay clear of both the authored flight and the doorway cross.

Run:  blender -b -P blender/build_stairwell_up_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pripyat_room_base import *

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_stairwell_up_decorated.glb"


def build():
    root = legacy_room("build_stairwell_up")
    floor_tiles(root, "SM_Floor_Linoleum_2m")
    wallpaper(root, "SM_Wall_Wallpaper_A")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    HW, AB, KR = "Hallway", "Abandonment", "KidsRoom"

    # NW stays empty at runtime once the flight moves to the centre: only a
    # wall telephone by the old landing.
    P(HW, "SM_Telephone_Wall", "Telephone", 90, xmin=-INNER + 0.002, y=2.3, z=1.1, collide=False)

    # NE: the lift and the mailbox block, a doormat in front of the lift.
    P(ARCH, "SM_Elevator_Door", "ElevatorDoor", -90, xmax=INNER - 0.002, y=3.3, z=0.0, sz=2.36 / 2.5, collide=False)
    P(ARCH, "SM_Mailboxes_Block", "Mailboxes", 0, x=3.2, ymax=INNER - 0.002, z=0.95)
    P(ARCH, "SM_Mailboxes_Block", "Mailboxes2", 0, x=4.05, ymax=INNER - 0.002, z=0.95)
    P(HW, "SM_Doormat", "Doormat", 90, x=4.85, y=3.3, collide=False, z=FZ)
    P(AB, "SM_Newspaper_Stack", "Newspapers", 20, x=3.6, y=4.6, collide=False, z=FZ)
    P(HW, "SM_ElectricMeter_Panel", "MeterPanel", 0, x=2.3, ymax=INNER - 0.002, z=1.0, collide=False)

    # SE: a neighbour's padded front door with its mat, shoe cabinet, coat
    # hooks and an umbrella left behind.
    P(HW, "SM_Door_Entrance_Padded", "NeighbourDoor", 180, x=3.4, ymin=-INNER + 0.002, z=0.0, collide=False)
    P(HW, "SM_Doormat", "DoormatS", 0, x=3.4, y=-5.2, collide=False, z=FZ)
    P(HW, "SM_ShoeCabinet", "ShoeCabinet", -90, xmax=Eb, y=-4.5, z=FZ)
    P(HW, "SM_CoatRack_Wall", "CoatHooks", -90, xmax=INNER - 0.002, y=-3.2, z=1.1, collide=False)
    P(HW, "SM_Umbrella", "Umbrella", 60, x=4.6, y=-3.2, collide=False, z=FZ)
    P(HW, "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=-2.15, z=0.72, collide=False)

    # SW: the stairwell window, a pram parked under it, rubble and a gas mask.
    P(ARCH, "SM_Window_DoubleFrame", "Window", 90, xmin=-INNER + 0.002, y=-3.6, z=0.72, collide=False)
    P(KR, "SM_Pram_Soviet", "Pram", 120, x=-3.5, y=-3.3, z=FZ)
    P(AB, "SM_Debris_Pile", "Debris", 30, x=-3.3, y=-4.8, collide=False, z=FZ)
    P(AB, "SM_GasMask", "GasMask", -60, x=-5.0, y=-5.0, collide=False, z=FZ)

    P(ARCH, "SM_CeilingLamp_Bare", "CeilingLamp", 0, x=3.0, y=-2.9, z=WALL_H - 0.63, collide=False)
    return root


if __name__ == "__main__":
    r = build()
    check()
    export(r, OUT)
