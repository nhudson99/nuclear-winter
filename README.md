# Nuclear Winter

Post-fallout USSR game. The **full Godot flow** is title → fat aristocrat briefing → Pip-Boy map → Level 1 (3D isometric mansion). The Phaser web app still hosts a leftover title + tutorial shell.

## Godot (title, briefing, map, Level 1)

```bash
# Requires Godot 4.4+
godot --path godot
# or
/home/ubuntu/tools/godot/Godot --path /workspace/godot
```

- Map authored in Blender (`blender/build_mansion_map.py`) and exported to `godot/assets/maps/ussr_mansion_map.glb`
- Humanoid authored in Blender (`blender/build_humanoid.py`) → `godot/assets/characters/humanoid_scavenger.glb`
- Monster authored in Blender (`blender/build_monster.py`) → `godot/assets/characters/enemy_monster.glb`
- Furniture props authored in Blender (`blender/build_furniture.py`) → `godot/assets/props/{crate,wardrobe,couch}.glb`
- Flow: `TitleScreen.tscn` → `AristocratScreen.tscn` → `GameMap.tscn` (click **LEVEL 1**) → `Main.tscn`
- Level 1: `godot/scenes/Main.tscn` (isometric camera, wall/prop collision, WASD walk, E to pick up the objective, escape the south exit, monster patrol/proximity chase, health bars, walkable doorways)

### Rebuild Blender assets

```bash
/home/ubuntu/tools/blender/blender --background --python blender/build_mansion_map.py
/home/ubuntu/tools/blender/blender --background --python blender/build_monster.py
/home/ubuntu/tools/blender/blender --background --python blender/build_furniture.py
cd godot && /home/ubuntu/tools/godot/Godot --headless --import
/home/ubuntu/tools/godot/Godot --headless -s res://tools/build_main_scene.gd
```

> Note: Blender MCP is not available in this cloud environment, so meshes are authored via Blender’s Python API (headless) instead.

### Gameplay notes

- **Objective**: a glowing pickup sits in the north-west rooms. Press **E** nearby to collect it, then reach the southern exit without dying.
- **Alarm**: collecting the item halves the monster's section patrol time and doubles its proximity detection radius.
- **Win / lose**: escaping with the item shows **WIN**; dying shows **GAME OVER**.
- **Doorways**: every adjacent room is linked by an open wall gap; player and monster can walk through.
- **Monster**: patrols the mansion in equal level sections (30s each), checking every room in the current section; detects players in a close proximity radius or via FOV + line of sight; deals 100 touch damage.
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
