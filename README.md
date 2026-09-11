# Nuclear Winter

Post-fallout USSR game. The **full Godot flow** is title → fat aristocrat briefing → Pip-Boy map → loading screen → Level 1 (3D isometric, procedurally generated). The Phaser web app still hosts a leftover title + tutorial shell.

## Godot (title, briefing, map, Level 1)

```bash
# Requires Godot 4.4+ (the Cloud Agent environment pins 4.4.1-stable)
godot --path godot
```

- Room modules authored in Blender (`blender/build_rooms.py`) → `godot/assets/rooms/room_{bedroom,living_room,office,storage}.glb`
- Player authored in Blender (`blender/build_prisoner.py`) → `godot/assets/characters/player_prisoner.glb`
- Monster authored in Blender (`blender/build_monster.py`) → `godot/assets/characters/enemy_monster.glb`
- Flow: `TitleScreen.tscn` → `AristocratScreen.tscn` → `GameMap.tscn` (click **LEVEL 1** or **SHOP**) → `Main.tscn`
- Level 1: `godot/scenes/Main.tscn` (10% ambient so rooms are faintly readable, hold RMB to aim the flashlight, isometric camera zoomed 50% onto the player, wall/prop collision, WASD walk, E to pick up the objective, escape through the outer doorway, monster patrol/proximity chase, health bars)
- The earlier hand-authored mansion (`blender/build_mansion_map.py` → `godot/assets/maps/ussr_mansion_map.glb`) is kept for reference but no longer loaded.

## Procedural maps

`godot/scripts/MapGenerator.gd` builds the floorplan at load time, so no two runs share a layout.

- **Room modules**: four Blender tiles — bedroom, living room, office, storage — all sharing one 12 m square footprint with a doorway centred on each wall, so any two rooms can butt together on a grid.
- **Layout**: the generator grows the map one neighbour at a time from the start cell, which keeps every room reachable without a separate connectivity pass. The footprint is capped to roughly square so the level does not sprawl into a corridor.
- **Room types**: one of each type is dealt first so every level shows all four; the remainder is random, then the whole bag is shuffled with the seeded RNG.
- **Doorways**: each module ships a removable `Plug_<side>` block filling its doorway. The generator deletes the plug where two rooms meet and keeps it where a room faces the outside, which seals the map edge without needing per-room wall variants. One outward wall of the start room is opened as the escape route.
- **Collision**: one `StaticBody3D` per room with a box per mesh, taken from mesh bounds. The modules are built from axis-aligned boxes and cylinders, so bounds are a close fit and far cheaper to cook than trimesh collision over a few hundred props. Blender names decoration `NoCol_*` to opt it out.
- **Seeding**: `Main.level_seed` defaults to `0`, which draws a fresh layout per run. Any other value replays that exact map.
- **Loading screen**: `godot/scenes/LoadingScreen.tscn` overlays the level while the generator runs, driven by the generator's `progress` signal. Generation yields a frame per room so the bar keeps moving, and the overlay eases its progress and honours `Main.min_loading_seconds` so a fast machine still shows the sweep.

### Rebuild Blender assets

```bash
# Requires Blender 4.2+ (the Cloud Agent environment pins 4.5.13 LTS)
blender --background --python blender/build_rooms.py
blender --background --python blender/build_monster.py
blender --background --python blender/build_prisoner.py
cd godot && godot --headless --import
godot --headless -s res://tools/build_main_scene.gd
```

> Note: Blender MCP is not available in this cloud environment, so meshes are authored via Blender’s Python API (headless) instead. Preview renders use Cycles on CPU because the environment has no GPU.

### Headless checks

```bash
cd godot
for t in smoke_procgen smoke_monster_doors smoke_game_loop smoke_flow_screens smoke_player_anims smoke_flashlight smoke_shop smoke_loadout; do
  godot --headless -s res://tools/$t.gd
done
```

`smoke_procgen.gd` covers the room-module contract, seed replay, layout variety, full connectivity, doorway carving and collision cooking.

### Gameplay notes

- **Lighting**: Level 1 has no sun. Ambient is 10% so you can pick a path with the flashlight off. Hold **RMB** to turn on the flashlight and aim the prisoner (and the cone) at the cursor; WASD still strafes independently. Release to go dark again. The glowing objective is the other light; collecting it lights a green exit beacon.
- **Camera**: the isometric view is zoomed 50% onto the player (ortho size 20 → 13.3).
- **Objective**: a glowing pickup sits in the room furthest from where you start. Press **E** nearby to collect it, then reach the exit doorway of the start room without dying.
- **Alarm**: collecting the item halves the monster's section patrol time and doubles its proximity detection radius, and turns on the green exit glow.
- **Win / lose**: escaping with the item awards **5 rations** and brings up the fat aristocrat ("Well, you survived. Good for you. Here is your ration reward"); dying shows **GAME OVER**.
- **Shop**: the Pip-Boy map has **SHOP** in the top right. Cards are **pistol** (5 rations, LMB fires 10 damage along the flashlight), **speed upgrade** (1 ration, +5% speed, stackable), and **sneak** (3 rations, hold **Ctrl** with the flashlight off to avoid sight detection).
- **Doorways**: every adjacent room is linked by an open wall gap; player and monster can walk through. Outward-facing walls are sealed.
- **Monster**: patrols the generated rooms in equal level sections (30s each), checking every room in the current section; detects players in a close proximity radius or via FOV + line of sight; deals 100 touch damage.
- **Health**: player starts at 100 HP with a billboard bar. The monster's bar stays hidden until the flashlight cone hits it (or it takes damage).

## Player character

`blender/build_prisoner.py` authors the whole player headlessly — a bald prisoner in a worn jumpsuit and boots — and writes `godot/assets/characters/player_prisoner.glb` plus a `.blend` for inspection.

- **Mesh**: 1.80 m tall, 3981 verts / 7696 tris, lofted from superellipse rings. The skull comes from measured width/depth profile tables rather than a deformed ellipsoid, so it has a jaw and a chin; nose, brows, eyes and ears are planted on numerically sampled surface points.
- **Texture**: wear is authored as procedural noise shaders and then Cycles-baked to one 1024² colour atlas, because glTF cannot carry shader nodes. Grime is weighted by object-space height, so dirt collects on the boots and knees. Three materials (fabric, leather, skin) share the atlas.
- **Rig**: 17 bones, skinned with inverse-distance weights restricted to a per-part bone whitelist. Bone-heat auto weights bleed across the overlapping lofted parts.
- **Clips**: `Idle` (96 f loop), `Walk` (24 f loop), `Run` (16 f loop), `Die` (34 f one-shot), exported through muted NLA tracks. The gait is phased from foot contact, with knee flex, ankle counter-rotation to keep planted feet flat, toe-off and a pelvis bob.
- **Playback**: `Player.gd` sets `LOOP_LINEAR` on the three cycles at load — the glTF importer leaves every clip one-shot — picks walk or run by ground speed, and scales the playback rate to the distance covered per cycle so the boots do not skate. WASD walks; hold **Shift** to run. Hold **RMB** to keep the flashlight on and face the cursor; movement and facing are independent while aiming. If the pistol is owned, **LMB** fires along that aim. Hold **Ctrl** with sneak owned and the light off to slip the monster's sight cone.

```bash
# Preview renders (views | head | turntable | anim <Clip> | poses <Clip> <angle> <frames...>)
blender --background --python blender/render_prisoner.py -- views
# Check what actually landed in the GLB
python3 blender/inspect_glb.py godot/assets/characters/player_prisoner.glb
```

## Phaser title / tutorial shell

```bash
npm install
npm run dev
```

Leftover web shell: title → boss CRT briefing → Pip-Boy map (returns to menu). The playable path lives in Godot.

## Layout

```
godot/                     Godot 4.4 game (menus + Level 1)
  assets/ui/               Title, aristocrat CRT, dialogue panel, Pip-Boy map
  assets/maps/ussr_mansion_map.glb
  assets/characters/{player_prisoner,enemy_monster}.glb
  assets/props/{crate,wardrobe,couch}.glb
  scenes/{TitleScreen,AristocratScreen,GameMap,Main}.tscn
  scripts/{SceneFlow,GameProgress,TitleScreen,AristocratScreen,GameMap,ShopMenu,Main,Player,Monster,PickupItem,ExitZone,Bullet}.gd
  tools/smoke_flow_screens.gd
  tools/smoke_game_loop.gd
  tools/smoke_shop.gd
  tools/smoke_loadout.gd
blender/
  build_mansion_map.py
  build_prisoner.py
  render_prisoner.py
  build_monster.py
  build_furniture.py
  ussr_mansion_map.blend
  enemy_monster.blend
  furniture_props.blend
  reference_floorplan.png
src/                       Phaser title + tutorial
public/assets/             Title / boss / pip-boy art
```
