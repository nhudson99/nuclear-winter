"""
Decorated library tile (room_library_decorated.glb): Pripyat-pack shell
(parquet, wallpaper B, baseboards) furnished with Meshy AI props from
blender/meshy_props/ (see meshy_props.py).

Bookcases line all four walls with the doorway cross left open; three
back-to-back pairs stand in the NW, NE and SW quadrants and a 2x2 quad of
bookcases (two back-to-back pairs) fills the room centre; the SE quadrant is
the reading corner: desk, desk chair, armchair, floor lamp, spare chairs.

Run:  blender -b -P blender/build_library_decorated.py
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from pripyat_room_base import *
from meshy_props import meshy

OUT = Path(__file__).resolve().parent.parent / "godot/assets/rooms/room_library_decorated.glb"
D = CLEAR + 0.05      # 1.95: bookcase ends stop just short of the doorway cross


def build():
    clear_scene()
    bpy.ops.object.empty_add(type="PLAIN_AXES"); root = bpy.context.active_object; root.name = "Library"
    build_shell(root, subfloor_mat(), plaster_mat())
    floor_tiles(root, "SM_Floor_Parquet_2m")
    wallpaper(root, "SM_Wall_Wallpaper_B")
    baseboards(root)
    P = lambda *a, **k: prop(*a, parent=root, **k)
    M = lambda *a, **k: meshy(*a, parent=root, **k)
    LR, AB, KR = "LivingRoom", "Abandonment", "KidsRoom"
    HARM, ANTQ, ELEG, MEM = "Bookshelf_Harmony", "Antiquarian_Bookcase", "Bookshelf_Elegance", "Bookcase_Memories"

    # Wall bookcases. N/S runs reach the corners; E/W runs stop 0.55 m short
    # so they never meet the N/S cases.
    for s, tag in ((1, "E"), (-1, "W")):
        edge = dict(xmin=D) if s > 0 else dict(xmax=-D)
        far = dict(xmax=E - 0.04) if s > 0 else dict(xmin=W + 0.04)
        M(HARM, f"Bookcase_N{tag}", 0, height=2.0, ymax=Nb, **edge)
        M(ANTQ, f"Antiquarian_N{tag}", 0, height=2.0, sy=0.6, ymax=Nb, **far)
        M(MEM, f"Bookcase_S{tag}", 180, height=1.5, ymin=Sb, **edge)
        M(ANTQ, f"Antiquarian_S{tag}", 180, height=2.0, sy=0.6, ymin=Sb, **far)
    for s, tag in ((1, "N"), (-1, "S")):
        edge = dict(ymin=D) if s > 0 else dict(ymax=-D)
        far = dict(ymax=5.05) if s > 0 else dict(ymin=-5.05)
        M(ELEG, f"Elegance_E{tag}", -90, front="-X", height=1.9, xmax=Eb, **edge)
        M(ANTQ, f"Antiquarian_E{tag}", -90, height=2.0, sy=0.6, xmax=Eb, **far)
        M(ELEG, f"Elegance_W{tag}", 90, front="-X", height=1.9, xmin=Wb, **edge)
        M(ANTQ, f"Antiquarian_W{tag}", 90, height=2.0, sy=0.6, xmin=Wb, **far)

    # Stacks: back-to-back pairs (two single-sided cases, backs touching).
    for tag, stem, h, cx, cy in (("NW", HARM, 2.0, -3.15, 3.55), ("NE", HARM, 2.0, 3.15, 3.55),
                                 ("SW", MEM, 1.5, -3.2, -3.6)):
        M(stem, f"Stack_{tag}_A", 0, height=h, x=cx, ymax=cy)
        M(stem, f"Stack_{tag}_B", 180, height=h, x=cx, ymin=cy)

    # Centre quad: two back-to-back Harmony pairs side by side (E-W), shelves
    # facing north and south. 1.7 m tall so it clears the bare ceiling lamp
    # (bottom 1.77 m). It sits on the doorway cross by design but leaves
    # >= 3.5 m to every doorway and >= 1.6 m to every other prop.
    for tag, cx in (("W", -0.915), ("E", 0.915)):
        M(HARM, f"Quad_{tag}_A", 0, height=1.7, x=cx, ymax=0.0)
        M(HARM, f"Quad_{tag}_B", 180, height=1.7, x=cx, ymin=0.0)

    # SE reading corner: librarian's desk facing the south wall, chair tucked
    # in, armchair + floor lamp, spare chairs.
    M("A_low_poly_large_woo", "Desk", 180, width=1.6, x=3.4, y=-4.2, z=FZ)
    M("Wooden_Chair", "DeskChair", 10, height=0.95, x=3.4, y=-3.2, z=FZ)
    M("armchair", "Armchair", -130, height=0.9, x=4.6, y=-2.65, z=FZ)
    P(LR, "SM_FloorLamp", "FloorLamp", 0, x=4.75, y=-4.6, z=FZ)
    M("Wooden_Chair", "ChairSpare", 75, height=0.95, x=2.45, y=-2.6, z=FZ)
    M("Wooden_Chair", "ChairNE", -160, height=0.95, x=2.6, y=2.45, z=FZ)
    M("Wooden_Chair", "ChairToppled", 40, height=0.95, tilt=(90, 0), x=-2.7, y=-2.45, z=FZ, collide=False)
    P(AB, "SM_Newspaper_Stack", "Papers", 20, x=3.4, y=-4.3, scale=0.6, on_surface=True, collide=False, stack_on="Desk")

    # Neglect: fallen books, paper drifts, rubble, one broken chair.
    P(KR, "SM_ChildrensBooks", "FallenBooksA", 35, x=-2.3, y=4.6, collide=False, z=FZ)
    P(KR, "SM_ChildrensBooks", "FallenBooksB", -50, x=4.6, y=4.3, collide=False, z=FZ)
    P(KR, "SM_ChildrensBooks", "FallenBooksC", 110, x=-4.6, y=-2.4, collide=False, z=FZ)
    P(AB, "SM_Newspaper_Stack", "FloorPapers", -15, x=-4.5, y=2.4, collide=False, z=FZ)
    P(AB, "SM_Debris_Pile", "Debris", 70, x=4.5, y=2.45, collide=False, z=FZ, scale=0.7)
    P(AB, "SM_GlassShards", "Glass", 10, x=-2.6, y=-4.6, collide=False, z=FZ)
    P(ARCH, "SM_CeilingLamp_Bare", "CeilingLamp", 0, x=0.0, y=0.0, z=WALL_H - 0.63, collide=False)
    return root


if __name__ == "__main__":
    r = build()
    check(cross_ok=("NoCol_CeilingLamp", "Quad_"), overlap_ok=(("Desk", "NoCol_Papers"),))
    export(r, OUT)
