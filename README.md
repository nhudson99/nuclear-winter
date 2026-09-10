# Nuclear Winter

Post-fallout USSR game. The **full Godot flow** is title → fat aristocrat briefing → Pip-Boy map → loading screen → Level 1 (3D isometric, procedurally generated). The Phaser web app still hosts a leftover title + tutorial shell.

## Godot (title, briefing, map, Level 1)

```bash
# Requires Godot 4.4+
godot --path godot
# or
/home/ubuntu/tools/godot/Godot --path /workspace/godot
```

- Room modules authored in Blender (`blender/build_rooms.py`) → `godot/assets/rooms/room_{bedroom,living_room,office,storage}.glb`
- Humanoid authored in Blender (`blender/build_humanoid.py`) → `godot/assets/characters/humanoid_scavenger.glb`
- Monster authored in Blender (`blender/build_monster.py`) → `godot/assets/characters/enemy_monster.glb`
- Flow: `TitleScreen.tscn` → `AristocratScreen.tscn` → `GameMap.tscn` (click **LEVEL 1**) → `Main.tscn`
- Level 1: `godot/scenes/Main.tscn` (isometric camera, wall/prop collision, WASD walk, E to pick up the objective, escape through the outer doorway, monster patrol/proximity chase, health bars)
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
/home/ubuntu/tools/blender/blender --background --python blender/build_rooms.py
/home/ubuntu/tools/blender/blender --background --python blender/build_monster.py
cd godot && /home/ubuntu/tools/godot/Godot --headless --import
/home/ubuntu/tools/godot/Godot --headless -s res://tools/build_main_scene.gd
```

> Note: Blender MCP is not available in this cloud environment, so meshes are authored via Blender’s Python API (headless) instead.

### Headless checks

```bash
cd godot
for t in smoke_procgen smoke_monster_doors smoke_game_loop smoke_flow_screens; do
  /home/ubuntu/tools/godot/Godot --headless -s res://tools/$t.gd
done
```

`smoke_procgen.gd` covers the room-module contract, seed replay, layout variety, full connectivity, doorway carving and collision cooking.

### Gameplay notes

- **Objective**: a glowing pickup sits in the room furthest from where you start. Press **E** nearby to collect it, then reach the exit doorway of the start room without dying.
- **Alarm**: collecting the item halves the monster's section patrol time and doubles its proximity detection radius.
- **Win / lose**: escaping with the item shows **WIN**; dying shows **GAME OVER**.
- **Doorways**: every adjacent room is linked by an open wall gap; player and monster can walk through. Outward-facing walls are sealed.
- **Monster**: patrols the generated rooms in equal level sections (30s each), checking every room in the current section; detects players in a close proximity radius or via FOV + line of sight; deals 100 touch damage.
- **Health**: player and monster both start at 100 HP with billboard health bars above their heads.

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
  assets/characters/{humanoid_scavenger,enemy_monster}.glb
  assets/props/{crate,wardrobe,couch}.glb
  scenes/{TitleScreen,AristocratScreen,GameMap,Main}.tscn
  scripts/{SceneFlow,TitleScreen,AristocratScreen,GameMap,Main,Player,Monster,PickupItem,ExitZone}.gd
  tools/smoke_flow_screens.gd
  tools/smoke_game_loop.gd
blender/
  build_mansion_map.py
  build_humanoid.py
  build_monster.py
  build_furniture.py
  ussr_mansion_map.blend
  enemy_monster.blend
  furniture_props.blend
  reference_floorplan.png
src/                       Phaser title + tutorial
public/assets/             Title / boss / pip-boy art
```
