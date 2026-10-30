"""
Decorated boiler tile (room_boiler_decorated.glb) built from the Pripyat pack
on top of build_rooms.build_boiler(). The tank, ValveWheel (spokes and hub
parented to it), NoCol_ValveLamp, ValveUse marker, header pipes, gauge board
and tool chest keep their names and positions; the ValveUse standing spot
(-2.35, 2.55) stays clear. Tiled utility-room walls, linoleum floor, and a
laundry corner from the Bathroom / Kitchen folders.

Run:  blender -b -P blender/build_boiler_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pripyat_room_base import *

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_boiler_decorated.glb"


def build():
    root = legacy_room("build_boiler")
    floor_tiles(root, "SM_Floor_Linoleum_2m")
    wallpaper(root, "SM_Wall_Tiled_2m")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    BA, K, AB, HW = "Bathroom", "Kitchen", "Abandonment", "Hallway"

    # NE: laundry. Soviet washing machine and zinc tub on the north wall, the
    # gas water heater above them; legacy tool chest stays on the east wall.
    P(BA, "SM_WashingMachine_Soviet", "WashingMachine", 0, xmin=2.0, ymax=Nb, z=FZ)
    P(BA, "SM_WashTub_Zinc", "WashTub", 0, xmin=2.85, ymax=Nb, z=FZ)
    P(K, "SM_GasWaterHeater", "WaterHeater", -90, xmax=INNER - 0.002, y=4.8, z=0.95, collide=False)
    P(BA, "SM_ShowerHose", "Hose", 0, x=4.2, ymax=INNER - 0.002, z=0.9, collide=False)
    P(HW, "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=2.15, z=0.72, collide=False)

    # SE: the caretaker's wash-up: pedestal basin, mirror cabinet, heated
    # towel rail and soap dish on the south wall.
    P(BA, "SM_Washbasin_Pedestal", "Washbasin", 180, x=3.4, ymin=Sb, z=FZ)
    P(BA, "SM_MirrorCabinet", "MirrorCabinet", 180, x=3.4, ymin=-INNER + 0.002, z=1.25, collide=False)
    P(BA, "SM_TowelRail_Heated", "TowelRail", 180, x=4.6, ymin=-INNER + 0.002, z=0.9, collide=False)
    P(BA, "SM_SoapDish", "SoapDish", 180, x=2.6, ymin=-INNER + 0.002, z=0.95, collide=False)
    P(BA, "SM_BathShelf_Glass", "BathShelf", 180, x=2.6, ymin=-INNER + 0.002, z=1.3, collide=False)
    P(K, "SM_KitchenStool_Metal", "Stool", 20, x=4.6, y=-4.2, z=FZ)

    # SW: by the gauge board: meter panel, newspapers, a gas mask and rubble.
    P(HW, "SM_ElectricMeter_Panel", "MeterPanel", 180, x=-3.0, ymin=-INNER + 0.002, z=1.0, collide=False)
    P(AB, "SM_Newspaper_Stack", "Newspapers", 10, x=-3.0, y=-4.9, collide=False, z=FZ)
    P(AB, "SM_GasMask", "GasMask", -40, x=-3.4, y=-2.6, collide=False, z=FZ)
    P(AB, "SM_Debris_Pile", "DebrisPile", 35, x=-2.9, y=-3.7, collide=False, z=FZ, scale=0.8)

    # NW stays the boiler's: only a fallen drawer of tools behind the tank.
    P(AB, "SM_Drawer_Fallen", "DrawerFallen", 15, x=-5.0, y=2.4, collide=False, z=FZ, scale=0.9)
    return root


if __name__ == "__main__":
    r = build()
    check()
    export(r, OUT)
