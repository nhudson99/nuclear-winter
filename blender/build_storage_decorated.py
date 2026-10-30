"""
Decorated storage tile (kitchen pantry) (room_storage_decorated.glb) built from the
Pripyat pack. Shared helpers live in pripyat_room_base.py.

Run:  blender -b -P blender/build_storage_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from pripyat_room_base import *

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_storage_decorated.glb"

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_storage_decorated.glb"


def build():
    clear_scene()
    bpy.ops.object.empty_add(type="PLAIN_AXES"); root = bpy.context.active_object; root.name = "Storage"
    build_shell(root, subfloor_mat(), plaster_mat())
    floor_tiles(root, "SM_Floor_Linoleum_2m")
    wallpaper(root, "SM_Wall_Wallpaper_B")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    K, LR, AB = "Kitchen", "LivingRoom", "Abandonment"
    WALLCAB_Z = 1.45

    # NW: the kitchen run on the north wall: stove, cabinets, sink, wall
    # cupboards, the gas water heater on the west wall.
    P(K, "SM_GasStove_4Burner", "Stove", 0, xmin=Wb, ymax=Nb, z=FZ)
    P(K, "SM_KitchenCabinet_Base", "CabinetA", 0, xmin=-5.08, ymax=Nb, z=FZ)
    P(K, "SM_KitchenSink_Cabinet", "Sink", 0, xmin=-4.44, ymax=Nb, z=FZ)
    P(K, "SM_KitchenCabinet_Base", "CabinetB", 0, xmin=-3.6, ymax=Nb, z=FZ)
    P(K, "SM_KitchenCabinet_Wall", "WallCabA", 0, xmin=-5.08, ymax=Nb, z=WALLCAB_Z)
    P(K, "SM_KitchenCabinet_Wall", "WallCabB", 0, xmin=-3.6, ymax=Nb, z=WALLCAB_Z)
    P(K, "SM_Plates_Stack", "Plates", 0, x=-4.78, y=5.3, z=0.88, collide=False, stack_on="CabinetA")
    P(K, "SM_DishRack", "DishRack", 0, x=-3.28, y=5.35, z=0.88, collide=False, stack_on="CabinetB")
    P(K, "SM_GasWaterHeater", "WaterHeater", 90, xmin=-INNER + 0.002, y=3.9, z=0.95, collide=False)
    P(K, "SM_FryingPan_CastIron", "FryingPan", 40, x=-4.3, y=3.9, collide=False, z=FZ)

    # NE: the kitchen table with stools, samovar and teapot still out; pantry
    # shelves and the dish cupboard on the north wall. One stool knocked over.
    P(LR, "SM_WallUnit_Shelves", "PantryShelfA", 0, xmin=2.0, ymax=Nb, z=FZ)
    P(LR, "SM_WallUnit_Shelves", "PantryShelfB", 0, xmin=2.94, ymax=Nb, z=FZ)
    P(LR, "SM_WallUnit_Glass", "DishCupboard", 0, xmin=3.88, ymax=Nb, z=FZ)
    P(K, "SM_KitchenTable_Formica", "Table", 0, x=3.8, y=3.0, z=FZ)
    P(K, "SM_Samovar_Electric", "Samovar", 0, x=3.55, y=3.05, on_surface=True, collide=False, stack_on="Table")
    P(K, "SM_Teapot_Porcelain", "Teapot", 30, x=4.1, y=2.95, on_surface=True, collide=False, stack_on="Table")
    P(K, "SM_KitchenStool_Metal", "StoolA", 0, x=3.7, y=2.2, z=FZ)
    P(K, "SM_KitchenStool_Metal", "StoolB", 0, x=4.75, y=3.0, z=FZ)
    P(K, "SM_KitchenStool_Metal", "StoolFallen", 20, tilt=(90, 0), x=2.55, y=3.4, collide=False, z=FZ)
    P(K, "SM_MilkBottle_Glass", "MilkBottle", 0, x=5.2, y=2.3, collide=False, z=FZ)
    P("Hallway", "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=2.15, z=0.72, collide=False)

    # SE: storage counters on the east wall with the food stores on top; the
    # meat grinder clamped on, spilled tins on the floor.
    for k, y in enumerate((-2.25, -2.9, -3.55, -4.2)):
        P(K, "SM_KitchenCabinet_Base", f"Counter{k}", -90, xmax=Eb, y=y, z=FZ)
    P(K, "SM_CannedFood_Set", "Tins", -90, x=5.35, y=-2.25, on_surface=True, collide=False, stack_on="Counter0")
    P(K, "SM_BreadBox", "BreadBox", -90, x=5.35, y=-2.9, on_surface=True, collide=False, stack_on="Counter1")
    P(K, "SM_Canisters_Set", "Canisters", -90, x=5.38, y=-3.55, on_surface=True, collide=False, stack_on="Counter2")
    P(K, "SM_MeatGrinder_Manual", "MeatGrinder", -90, x=5.25, y=-4.2, on_surface=True, collide=False, stack_on="Counter3")
    P(K, "SM_CannedFood_Set", "TinsSpilled", 35, x=4.2, y=-3.0, collide=False, z=FZ)
    P(AB, "SM_GlassShards", "GlassShards", 0, x=3.6, y=-4.6, collide=False, z=FZ)

    # SW: emergency supplies dumped by the south wall: gas masks, newspapers,
    # a fallen drawer, rubble from the ceiling.
    P(K, "SM_KitchenCabinet_Base", "CabinetS0", 180, x=-4.9, ymin=Sb, z=FZ)
    P(K, "SM_KitchenCabinet_Base", "CabinetS1", 180, x=-4.26, ymin=Sb, z=FZ)
    P(K, "SM_KitchenCabinet_Wall", "WallCabS", 180, x=-4.58, ymin=Sb, z=WALLCAB_Z)
    P(K, "SM_Pot_Enamel_Set", "Pots", 180, x=-4.58, y=-5.35, z=0.88, collide=False, stack_on="CabinetS")
    P(AB, "SM_GasMask_Pile", "GasMaskPile", -20, x=-3.0, y=-4.6, collide=False, z=FZ, scale=0.8)
    P(AB, "SM_Newspaper_Stack", "Newspapers", 80, x=-5.0, y=-3.0, collide=False, z=FZ)
    P(AB, "SM_Drawer_Fallen", "DrawerFallen", 15, x=-3.2, y=-2.8, collide=False, z=FZ)
    P(AB, "SM_Debris_Pile", "Debris", -40, x=-4.2, y=-3.9, collide=False, z=FZ, scale=0.7)

    P(ARCH, "SM_CeilingLamp_Bare", "CeilingLamp", 0, x=0.0, y=0.0, z=WALL_H - 0.63, collide=False)
    return root


if __name__ == "__main__":
    r = build()
    check()
    export(r, OUT)
