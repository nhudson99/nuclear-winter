"""
Decorated living room tile (room_living_room_decorated.glb) built from the
Pripyat pack. Shared helpers live in pripyat_room_base.py.

Run:  blender -b -P blender/build_living_room_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from pripyat_room_base import *

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_living_room_decorated.glb"


def build():
    clear_scene()
    bpy.ops.object.empty_add(type="PLAIN_AXES"); root = bpy.context.active_object; root.name = "LivingRoom"
    build_shell(root, subfloor_mat(), plaster_mat())
    floor_tiles(root, "SM_Floor_Parquet_2m")
    wallpaper(root, "SM_Wall_Wallpaper_B")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    LR = "LivingRoom"

    # NW: the sitting corner. Sofa bed on the north wall, carpet hung above it,
    # armchair on the west wall, coffee table on the floor rug, a floor lamp.
    P(LR, "SM_FloorLamp", "FloorLamp", 0, xmin=Wb, ymax=Nb, z=FZ)
    P(LR, "SM_SofaBed", "Sofa", 0, xmin=-4.94, ymax=Nb, z=FZ)
    P(LR, "SM_Rug_Wall", "WallRug", 0, x=-3.98, ymax=INNER - 0.002, z=1.12, scale=0.8, collide=False)
    P(LR, "SM_Armchair_Upholstered", "Armchair", 90, xmin=Wb, y=2.55, z=FZ)
    P(LR, "SM_Rug_Floor", "FloorRug", 0, x=-3.7, y=3.45, collide=False, z=FZ)
    P(LR, "SM_CoffeeTable", "CoffeeTable", 0, x=-3.75, y=3.5, z=FZ)
    P(LR, "SM_VinylRecords", "Records", 25, x=-3.35, y=2.45, collide=False, z=FZ)

    # NE: the wall unit ("stenka") along the north wall and the radiogram on
    # the east wall, figurines left on top.
    P(LR, "SM_WallUnit_Glass", "WallUnitGlass", 0, xmin=2.0, ymax=Nb, z=FZ)
    P(LR, "SM_WallUnit_Shelves", "WallUnitShelves", 0, xmin=2.94, ymax=Nb, z=FZ)
    P(LR, "SM_WallUnit_Wardrobe", "WallUnitWardrobe", 0, xmin=3.88, ymax=Nb, z=FZ)
    P(LR, "SM_Radiogram", "Radiogram", -90, xmax=Eb, y=3.1, z=FZ)
    P(LR, "SM_Figurines_Porcelain", "Figurines", -90, x=5.38, y=3.1, on_surface=True, collide=False, stack_on="Radiogram")
    P("Abandonment", "SM_Newspaper_Stack", "Newspapers", 70, x=3.2, y=2.75, collide=False, z=FZ)
    P("Hallway", "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=2.15, z=0.72, collide=False)

    # SE: upright piano on the east wall with its chair, photos on the lid,
    # a gas mask dropped on the floor.
    P(LR, "SM_Piano_Upright", "Piano", -90, xmax=Eb, y=-3.65, z=FZ)
    P(LR, "SM_DiningChair_Upholstered", "PianoChair", 90, x=4.5, y=-3.65, z=FZ)
    P(LR, "SM_PhotoFrames_Set", "PhotoFrames", -100, x=5.3, y=-3.2, on_surface=True, collide=False, stack_on="Piano")
    P(LR, "SM_SewingMachine", "SewingMachine", 180, x=3.3, ymin=Sb, z=FZ)
    P("Abandonment", "SM_GasMask", "GasMask", 140, x=3.4, y=-2.6, collide=False, z=FZ)

    # SW: the dining table, one chair knocked over, glassware still out.
    P(LR, "SM_DiningTable_Extendable", "DiningTable", 0, x=-3.75, y=-3.85, z=FZ)
    P(LR, "SM_Crystal_Glassware", "Glassware", 0, x=-3.75, y=-4.06, on_surface=True, collide=False, stack_on="DiningTable")
    P(LR, "SM_DiningChair_Upholstered", "ChairN", 0, x=-3.95, y=-2.85, z=FZ)
    P(LR, "SM_DiningChair_Upholstered", "ChairS", 180, x=-3.55, y=-4.85, z=FZ)
    P(LR, "SM_DiningChair_Upholstered", "ChairW", 90, x=-4.95, y=-3.85, z=FZ)
    P(LR, "SM_DiningChair_Upholstered", "ChairFallen", 70, tilt=(-90, 0), x=-2.55, y=-3.3, collide=False, z=FZ)
    P("Abandonment", "SM_GlassShards", "GlassShards", -30, x=-2.62, y=-4.75, collide=False, z=FZ)

    P(LR, "SM_Chandelier_3Arm", "CeilingLamp", 0, x=0.0, y=0.0, z=WALL_H - 0.667 * 0.85, scale=0.85, collide=False)
    return root


if __name__ == "__main__":
    r = build()
    check()
    export(r, OUT)
