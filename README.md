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
- Scene: `godot/scenes/Main.tscn` (isometric camera, wall collision, WASD walk with facing + limb swing)

### Rebuild the Blender map

```bash
/home/ubuntu/tools/blender/blender --background --python blender/build_mansion_map.py
cd godot && godot --headless --import
godot --headless -s res://tools/build_main_scene.gd
```

> Note: Blender MCP is not available in this cloud environment, so the map was authored via Blender’s Python API (headless) instead.

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
  scenes/Main.tscn
  scripts/{Main,Player}.gd
blender/
  build_mansion_map.py
  ussr_mansion_map.blend
  reference_floorplan.png
src/                       Phaser title + tutorial
public/assets/             Title / boss / pip-boy art
```
