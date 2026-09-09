# Nuclear Winter

Post-fallout USSR game. The **playable 3D isometric level** lives in the **Godot** project. The Phaser web app still hosts the title + tutorial intro.

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
- Scene: `godot/scenes/Main.tscn` (isometric camera, wall/prop collision, WASD walk, monster vision chase, walkable doorways)

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
- **Monster**: hunts when the player is inside its field of view and has clear line of sight through doorways/rooms; loses interest shortly after leaving view.

## Phaser title / tutorial shell

```bash
npm install
npm run dev
```

Flow: title → boss CRT briefing → Pip-Boy map (returns to menu). The old 2D mansion walk scene has been removed.

## Layout

```
godot/                     Godot 4.4 isometric game
  assets/maps/ussr_mansion_map.glb
  assets/characters/{humanoid_scavenger,enemy_monster}.glb
  assets/props/{crate,wardrobe,couch}.glb
  scenes/Main.tscn
  scripts/{Main,Player,Monster}.gd
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
