"""
Decorated office tile (room_office_decorated.glb) built from the
Pripyat pack. Shared helpers live in pripyat_room_base.py.

Run:  blender -b -P blender/build_office_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from pripyat_room_base import *

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_office_decorated.glb"

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_office_decorated.glb"


def build():
    clear_scene()
    bpy.ops.object.empty_add(type="PLAIN_AXES"); root = bpy.context.active_object; root.name = "Office"
    build_shell(root, subfloor_mat(), plaster_mat())
    floor_tiles(root, "SM_Floor_Linoleum_2m")
    wallpaper(root, "SM_Wall_Wallpaper_A")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    LR, HW, AB = "LivingRoom", "Hallway", "Abandonment"

    # NW: the manager's desk on the north wall, chair pushed back, globe and
    # telephone; papers spilled on the floor.
    P("Kitchen", "SM_KitchenTable_Formica", "Desk", 0, x=-3.9, ymax=Nb, z=FZ)
    P(LR, "SM_DiningChair_Upholstered", "DeskChair", 160, x=-3.75, y=4.2, z=FZ)
    P("KidsRoom", "SM_Globe", "Globe", 20, x=-4.2, y=5.35, on_surface=True, collide=False, stack_on="Desk")
    P(HW, "SM_Telephone_Wall", "Telephone", 90, xmin=-INNER + 0.002, y=4.6, z=1.1, collide=False)
    P(AB, "SM_Newspaper_Stack", "Papers", 15, x=-3.0, y=3.0, collide=False, z=FZ)
    P(HW, "SM_ShoeCabinet", "LowCabinet", 90, xmin=Wb, y=2.7, z=FZ)

    # NE: bookcases and the glass-front cabinet along the north wall, low
    # cabinets on the east wall.
    P(LR, "SM_WallUnit_Shelves", "BookcaseA", 0, xmin=2.0, ymax=Nb, z=FZ)
    P(LR, "SM_WallUnit_Shelves", "BookcaseB", 0, xmin=2.94, ymax=Nb, z=FZ)
    P(LR, "SM_WallUnit_Glass", "GlassCabinet", 0, xmin=3.88, ymax=Nb, z=FZ)
    P(HW, "SM_ShoeCabinet", "FileCabinetA", -90, xmax=Eb, y=3.55, z=FZ)
    P(HW, "SM_ShoeCabinet", "FileCabinetB", -90, xmax=Eb, y=2.7, z=FZ)
    P(AB, "SM_PhotoAlbum", "Folder", 60, x=3.3, y=3.6, collide=False, z=FZ)
    P(HW, "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=2.15, z=0.72, collide=False)

    # SE: clerk's desk on the east wall, the radio set on the south wall, the
    # electric meter panel, a drawer dumped on the floor.
    P("Kitchen", "SM_KitchenTable_Formica", "ClerkDesk", -90, xmax=Eb, y=-3.6, z=FZ)
    P(LR, "SM_DiningChair_Upholstered", "ClerkChair", 100, x=4.55, y=-3.5, z=FZ)
    P(LR, "SM_SewingMachine", "Typewriter", -90, x=5.3, y=-3.9, on_surface=True, collide=False, stack_on="ClerkDesk")
    P(LR, "SM_Radiogram", "RadioSet", 180, x=3.0, ymin=Sb, z=FZ)
    P(HW, "SM_ElectricMeter_Panel", "MeterPanel", -90, xmax=INNER - 0.002, y=-2.4, z=1.15, collide=False)
    P(AB, "SM_Drawer_Fallen", "DrawerFallen", 30, x=3.4, y=-2.75, collide=False, z=FZ)

    # SW: waiting corner. Coat hooks and mirror on the south wall, armchair,
    # a broken chair, gas masks heaped where someone handed them out.
    P(HW, "SM_CoatRack_Wall", "CoatHooks", 180, x=-4.6, ymin=-INNER + 0.002, z=1.1, collide=False)
    P(HW, "SM_Mirror_Wall", "Mirror", 180, x=-3.2, ymin=-INNER + 0.002, z=1.0, collide=False)
    P(LR, "SM_Armchair_Upholstered", "Armchair", 90, xmin=Wb, y=-3.2, z=FZ)
    P(AB, "SM_Chair_Broken", "ChairBroken", -30, x=-3.0, y=-3.0, collide=False, z=FZ)
    P(AB, "SM_GasMask_Pile", "GasMaskPile", 20, x=-3.0, y=-4.85, collide=False, z=FZ, scale=0.8)
    P(AB, "SM_Debris_Pile", "Debris", 70, x=-4.6, y=-4.75, collide=False, z=FZ, scale=0.7)

    P(ARCH, "SM_CeilingLamp_Bare", "CeilingLamp", 0, x=0.0, y=0.0, z=WALL_H - 0.63, collide=False)
    return root


if __name__ == "__main__":
    r = build()
    check()
    export(r, OUT)
