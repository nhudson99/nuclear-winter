# Nuclear Winter

Post-fallout USSR game. The whole game — title, briefing, world map and the 3D isometric level — runs from the **Godot** project. The Phaser web app is the older browser shell for the same intro.

## Godot (main game)

```bash
# Requires Godot 4.4+
godot --path godot
# or
/home/ubuntu/tools/godot/Godot --path /workspace/godot
```

### Flow

`TitleScreen` → `BossBriefing` → `WorldMap` → `Main` (level 1), with fades between each step driven by the `SceneFlow` autoload (`godot/scripts/SceneFlow.gd`).

- **Title** (`scenes/TitleScreen.tscn`): title art, falling ash, "Press Any Button" — any key/click/pad button advances.
- **Briefing** (`scenes/BossBriefing.tscn`): the aristocrat on the CRT; "You want to eat? Then get to work" types out. Input skips the typing, then advances.
- **World map** (`scenes/WorldMap.tscn`): pip-boy map with a clickable `LEVEL 1 // MANSION` button pinned to the mansion's map marker. Esc returns to the title.
- **Level 1** (`scenes/Main.tscn`): the isometric mansion. Esc returns to the world map.

### Assets

- Map authored in Blender (`blender/build_mansion_map.py`) and exported to `godot/assets/maps/ussr_mansion_map.glb`
- Humanoid authored in Blender (`blender/build_humanoid.py`) → `godot/assets/characters/humanoid_scavenger.glb`
- Monster authored in Blender (`blender/build_monster.py`) → `godot/assets/characters/enemy_monster.glb`
- Furniture props authored in Blender (`blender/build_furniture.py`) → `godot/assets/props/{crate,wardrobe,couch}.glb`
- Scene: `godot/scenes/Main.tscn` (isometric camera, wall/prop collision, WASD walk, monster patrol/proximity chase, health bars, walkable doorways)
- UI art in `godot/assets/ui/` (copied from `public/assets/`, plus a generated `ash_flake.png` for the title particles)

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

- **Doorways**: every adjacent room is linked by an open wall gap; player and monster can walk through.
- **Monster**: patrols the mansion in equal level sections (30s each), checking every room in the current section; detects players in a close proximity radius or via FOV + line of sight; deals 100 touch damage.
- **Health**: player and monster both start at 100 HP with billboard health bars above their heads.

## Phaser title / tutorial shell (legacy web build)

```bash
npm install
npm run dev
```

Same intro beats in the browser: title → boss CRT briefing → Pip-Boy map (returns to menu). The Godot project is the one that continues into playable levels.

## Layout

```
godot/                     Godot 4.4 game (title → briefing → map → level)
  assets/maps/ussr_mansion_map.glb
  assets/characters/{humanoid_scavenger,enemy_monster}.glb
  assets/props/{crate,wardrobe,couch}.glb
  assets/ui/{title_screen,boss_crt,dialogue_panel,pipboy_map,ash_flake}.png
  scenes/{TitleScreen,BossBriefing,WorldMap,Main}.tscn
  scripts/{SceneFlow,TitleScreen,BossBriefing,WorldMap,Scanlines}.gd
  scripts/{Main,Player,Monster,HealthBar3D}.gd
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
