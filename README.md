# Nuclear Winter

Post-fallout USSR game. The complete title → briefing → map → playable
3D level flow lives in the **Godot** project.

## Godot 3D isometric (main play)

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
- Frontend scenes: `godot/scenes/{TitleScreen,AristocratScreen,GameMap}.tscn`
- Level scene: `godot/scenes/Main.tscn` (isometric camera, wall/prop collision, WASD walk, E to pick up the objective, escape the south exit, monster patrol/proximity chase, health bars, walkable doorways)

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

- **Start flow**: press any key on the title and briefing screens, then select the pulsing **Level 1** signal on the map.
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

The Phaser version of the title → boss CRT briefing → Pip-Boy map remains
available as a web-only prototype.

## Layout

```
godot/                     Godot 4.4 isometric game
  assets/maps/ussr_mansion_map.glb
  assets/characters/{humanoid_scavenger,enemy_monster}.glb
  assets/props/{crate,wardrobe,couch}.glb
  assets/ui/{title-screen,boss-crt,dialogue-panel,ussr-pipboy-map}.png
  scenes/{TitleScreen,AristocratScreen,GameMap,Main}.tscn
  scripts/{IntroScreen,GameMap,Main,Player,Monster,PickupItem,ExitZone}.gd
  tools/{smoke_frontend_flow,smoke_game_loop}.gd
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
