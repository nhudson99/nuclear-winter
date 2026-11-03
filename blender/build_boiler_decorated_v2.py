"""
Boiler tile v2 (room_boiler_decorated_v2.glb): the functional parts of
build_rooms.build_boiler() (ValveRiser/Body, ValveWheel with spokes + hub,
NoCol_ValveLamp, ValveUse marker at (-2.35, 2.55), return pipe (header re-routed, see below),
ceiling lamp) keep their names and positions; the procedural tank, gauge
board and tool chest are replaced by Meshy AI industrial props from
blender/meshy_props/ (see meshy_props.py). Pripyat-pack linoleum / tiled
walls / baseboards as in v1. The v1 script and glb are untouched.

Run:  blender -b -P blender/build_boiler_decorated_v2.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from pripyat_room_base import *
import pripyat_room_base as B
from meshy_props import meshy

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_boiler_decorated_v2.glb"
REPLACED = ("BoilerTank", "BoilerLeg_", "BoilerSoot", "GaugeBoard", "NoCol_Gauge", "ToolChest",
            "NoCol_ChestHandle", "NoCol_HazardStripe")


def build():
    root = legacy_room("build_boiler")
    for o in list(root.children):
        if o.name.startswith(REPLACED):
            if o in B.OBSTACLES: B.OBSTACLES.remove(o)
            bpy.data.objects.remove(o)
    # v1's NoCol_BoilerHeader ran diagonally to the room centre, which the
    # axis-aligned legacy pipe_seg turned into a 3 x 3.7 m slab at 2 m.
    # Re-route it as a round pipe from the valve riser into the north wall.
    old = bpy.data.objects["NoCol_BoilerHeader"]; pm = old.data.materials[0]
    if old in B.OBSTACLES: B.OBSTACLES.remove(old)
    bpy.data.objects.remove(old)
    run = INNER - 3.75
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.07, depth=run + 0.1,
                                        location=(-3.15, 3.75 + run / 2 + 0.05, 2.02), rotation=(1.5708, 0, 0))
    hp = bpy.context.active_object; hp.name = "NoCol_BoilerHeader"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    box_uv(hp, 0.5); hp.data.materials.append(pm); hp.parent = root
    floor_tiles(root, "SM_Floor_Linoleum_2m")
    wallpaper(root, "SM_Wall_Tiled_2m")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    M = lambda *a, **k: meshy(*a, parent=root, **k)
    AB, HW = "Abandonment", "Hallway"

    # NW: the riveted steam boiler swallows the old return pipe end; a
    # wall-hung boiler manifold sits on the north wall beside the valve.
    M("Rusted_Steam_Boiler", "SteamBoiler", 0, height=2.2, x=-4.5, y=4.0, z=FZ)
    M("Wall_Boiler_07", "WallBoiler", 0, height=1.5, x=-2.8, ymax=INNER - 0.002, z=0.45)
    P(AB, "SM_Drawer_Fallen", "DrawerFallen", 15, x=-5.0, y=2.4, collide=False, z=FZ, scale=0.9)

    # NE: horizontal boiler module along the north wall, elbow pipe + gate
    # valve coming out of the east wall.
    M("Industrial_Boiler_Mod", "BoilerModule", 0, width=3.0, xmax=Eb, ymax=Nb, z=FZ)
    M("Industrial_Pipe_Valve", "PipeElbow", -90, height=1.7, xmax=INNER - 0.002, y=2.9, z=FZ)
    P(HW, "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=4.3, z=1.2, collide=False)

    # SE: rusted storage tank in the corner, twin pressure vessels on the
    # east wall, a stand-mounted pressure gauge by the south wall.
    M("Rusted_Industrial_Tan", "StorageTank", 0, height=2.0, xmax=Eb, ymin=Sb, z=FZ)
    M("Rusty_Industrial_Stor", "PressureVessels", 0, height=0.8, xmax=Eb, ymax=-2.0, z=FZ)
    M("Pressure_Gauge", "PressureGauge", 180, height=1.3, x=2.7, ymin=Sb, z=FZ)
    P(AB, "SM_Newspaper_Stack", "Newspapers", 10, x=2.9, y=-4.3, collide=False, z=FZ)

    # SW: control panel on the west wall, meter panel, gas mask, rubble.
    M("Control_Panel", "ControlPanel", 90, height=0.9, xmin=-INNER + 0.002, y=-3.6, z=1.0, collide=False)
    P(HW, "SM_ElectricMeter_Panel", "MeterPanel", 180, x=-3.0, ymin=-INNER + 0.002, z=1.0, collide=False)
    P(AB, "SM_GasMask", "GasMask", -40, x=-3.4, y=-2.6, collide=False, z=FZ)
    P(AB, "SM_Debris_Pile", "DebrisPile", 35, x=-4.4, y=-4.6, collide=False, z=FZ, scale=0.8)
    P(AB, "SM_GlassShards", "Glass", 60, x=-2.6, y=-4.5, collide=False, z=FZ)
    return root


if __name__ == "__main__":
    r = build()
    check(overlap_ok=(("SteamBoiler", "NoCol_BoilerReturn"),))
    export(r, OUT)
