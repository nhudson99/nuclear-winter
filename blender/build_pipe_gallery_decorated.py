"""
Decorated pipe gallery tile (room_pipe_gallery_decorated.glb) built from the
Pripyat pack on top of build_rooms.build_pipe_gallery(). Wall pipe runs,
brackets, Manifold (+cap/taps/heat), ValveCabinet, steam sign and DripTray keep
their names and positions. Tiled basement walls and linoleum floor, with a
workers' corner and abandonment clutter.

Run:  blender -b -P blender/build_pipe_gallery_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from pripyat_room_base import *

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_pipe_gallery_decorated.glb"


def build():
    root = legacy_room("build_pipe_gallery")
    floor_tiles(root, "SM_Floor_Linoleum_2m")
    wallpaper(root, "SM_Wall_Tiled_2m")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    BA, K, AB, HW = "Bathroom", "Kitchen", "Abandonment", "Hallway"

    # NW: the leak. Zinc tub catching drips beside the legacy drip tray,
    # gas-mask pile and wallpaper-less rubble.
    P(BA, "SM_WashTub_Zinc", "WashTub", 20, x=-4.6, y=2.7, z=FZ)
    P(AB, "SM_GasMask_Pile", "GasMaskPile", 25, x=-4.4, y=4.7, collide=False, z=FZ, scale=0.7)
    P(AB, "SM_GlassShards", "Shards", 0, x=-3.0, y=3.0, collide=False, z=FZ)

    # NE: maintenance crew corner: wall coat rack, stool, newspapers, meter.
    P("Bedroom", "SM_CoatRack_Standing", "CoatRack", 0, x=4.6, y=4.0, z=FZ)
    P(HW, "SM_ElectricMeter_Panel", "MeterPanel", -90, xmax=INNER - 0.002, y=3.2, z=0.45, collide=False)
    P(K, "SM_KitchenStool_Metal", "Stool", 15, x=3.6, y=4.6, z=FZ)
    P(AB, "SM_Newspaper_Stack", "Newspapers", -20, x=4.6, y=4.7, collide=False, z=FZ)
    P(AB, "SM_Debris_Pile", "Debris", -55, x=2.6, y=3.6, collide=False, z=FZ)

    # SE: around the manifold: fallen drawer of fittings, gas mask.
    P(AB, "SM_Drawer_Fallen", "DrawerFallen", 30, x=2.9, y=-3.0, collide=False, z=FZ, scale=0.9)
    P(AB, "SM_GasMask", "GasMask", 70, x=4.9, y=-2.6, collide=False, z=FZ)

    # SW: by the valve cabinet: broken chair and a second debris heap.
    P(AB, "SM_Chair_Broken", "ChairBroken", -30, x=-2.8, y=-4.6, collide=False, z=FZ)
    P(AB, "SM_Debris_Pile", "Debris2", 120, x=-4.7, y=-2.9, collide=False, z=FZ, scale=0.7)
    P(HW, "SM_LightSwitch_Socket", "LightSwitch", 180, x=-2.6, ymin=-INNER, z=0.72, collide=False)
    return root


if __name__ == "__main__":
    r = build()
    check()
    export(r, OUT)
