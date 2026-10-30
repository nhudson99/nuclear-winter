# Nuclear Winter

Post-fallout USSR game. The **full Godot flow** is title → fat aristocrat briefing → Pip-Boy map → loading screen → Level 1 (3D isometric, procedurally generated). The Phaser web app still hosts a leftover title + tutorial shell.

## Godot (title, briefing, map, Level 1)

```bash
# Requires Godot 4.4+ (the Cloud Agent environment pins 4.4.1-stable)
godot --path godot
```

- Room modules authored in Blender (`blender/build_rooms.py`) → `godot/assets/rooms/room_{bedroom,living_room,office,storage,stairwell_up,stairwell_down,boiler,pipe_gallery}.glb`. Shell topology stays procedural; furniture and floor/wall PBR maps come from `blender/PripyatApartment_FBX_PBR/` (Pripyat Apartment pack — project license, do not redistribute the pack alone).
- Player mesh in the level is `godot/assets/characters/Meshy_AI_Gulag_Winter_Warden_All_Animations.glb` (Walking, Running, and an air squat). The older Blender prisoner (`blender/build_prisoner.py` → `godot/assets/characters/player_prisoner.glb`) is still in the repo.
- Hare mesh is `godot/assets/characters/IrradiatedHare.glb` (`Walk` and `Attack`; idle is the first walk frame). The older Blender stalker (`blender/build_monster.py` → `godot/assets/characters/enemy_monster.glb`) is still in the repo.
- Slime enemy from [Poly Pizza](https://poly.pizza/m/6O6XUMssAW) (Charlie, CC-BY) is scaled and reoriented by `blender/prepare_slime.py` → `godot/assets/characters/enemy_slime.glb`
- Tank authored in Blender (`blender/build_tank.py`) → `godot/assets/characters/enemy_tank.glb`
- Widow authored in Blender (`blender/build_widow.py`) → `godot/assets/characters/enemy_widow.glb`
- Tarantula authored in Blender (`blender/build_tarantula.py`) → `godot/assets/characters/enemy_tarantula.glb`
- Toad authored in Blender (`blender/build_toad.py`) → `godot/assets/characters/enemy_toad.glb`
- Flow: `TitleScreen.tscn` → `AristocratScreen.tscn` → `GameMap.tscn` (click **LEVEL n** or **SHOP**) → `Main.tscn`
- Levels scale from `GameProgress.current_level`. Level 1 is the current open nine-room layout with one slime and a free mission item. Higher levels add monsters in an easy → moderate → dangerous cycle (slime, hare, tank, tarantula, widow, toad), extra locked wings, and one key per locked door. The mission item is always in the last locked wing. From level 3 the wings are stacked as **floors** (max two wings per floor); stairwell rooms sit behind the next locked door and only the current floor is instantiated.
- Level 1: `godot/scenes/Main.tscn` (10% ambient so rooms are faintly readable, hold RMB or the right stick to aim the flashlight, isometric camera zoomed 50% onto the player, wall/prop collision, WASD or the left stick to walk, E / USE to pick up objectives, LMB to swing or fire, on a phone aim the right stick at an enemy to attack, escape through the outer doorway, enemies on the monster track, health bars)
- The earlier hand-authored mansion (`blender/build_mansion_map.py` → `godot/assets/maps/ussr_mansion_map.glb`) is kept for reference but no longer loaded.

## Procedural maps

`godot/scripts/MapGenerator.gd` builds the floorplan at load time, so no two runs share a layout.

- **Room modules**: eight Blender tiles — bedroom, living room, office, storage, stairwell up, stairwell down, boiler, pipe gallery — all sharing one 12 m square footprint with a doorway centred on each wall, so any two rooms can butt together on a grid. The boiler holds the steam valve (`ValveUse` / `ValveWheel`); the pipe gallery is the room the breach opens from.
- **Layout**: the generator grows the map one neighbour at a time from the start cell, which keeps every room reachable without a separate connectivity pass. The footprint is capped to roughly square so the level does not sprawl into a corridor.
- **Floors**: each storey has at most two wings. One wing is gated by a locked door; when another storey exists the stairs are behind the next key. Only the active floor is spawned, so later levels do not keep the whole building in memory. Press **E** at a stair landing to change floors.
- **Room types**: one of each livable type is dealt first so every level shows all four; the remainder is random, then the whole bag is shuffled with the seeded RNG. Stairwell rooms replace one cell in each connecting wing.
- **Doorways**: each module ships a removable `Plug_<side>` block filling its doorway. The generator deletes the plug where two rooms meet and keeps it where a room faces the outside, which seals the map edge without needing per-room wall variants. One outward wall of the start room is opened as the escape route.
- **Monster track**: the generator also builds a graph whose nodes sit on every room centre and every interior doorway centre, then instances it as `MonsterTrack` under the map. The monster patrols that graph so it never cuts through walls or furniture.
- **Collision**: one `StaticBody3D` per room with a box per mesh, taken from mesh bounds. The modules are built from axis-aligned boxes and cylinders, so bounds are a close fit and far cheaper to cook than trimesh collision over a few hundred props. Blender names decoration `NoCol_*` to opt it out.
- **Seeding**: `Main.level_seed` defaults to `0`, which draws a fresh layout per run. Any other value replays that exact map.
- **Loading screen**: `godot/scenes/LoadingScreen.tscn` overlays the level while the generator runs, driven by the generator's `progress` signal. Generation yields a frame per room so the bar keeps moving, and the overlay eases its progress and honours `Main.min_loading_seconds` so a fast machine still shows the sweep.

### Rebuild Blender assets

```bash
# Requires Blender 4.2+ (the Cloud Agent environment pins 4.5.13 LTS)
# build_rooms.py also needs blender/PripyatApartment_FBX_PBR/ present
blender --background --python blender/build_rooms.py
blender --background --python blender/build_monster.py
blender --background --python blender/build_tank.py
blender --background --python blender/build_widow.py
blender --background --python blender/build_tarantula.py
blender --background --python blender/build_toad.py
blender --background --python blender/prepare_slime.py
blender --background --python blender/build_prisoner.py
cd godot && godot --headless --import
godot --headless -s res://tools/build_main_scene.gd
```

> Note: Blender MCP is not available in this cloud environment, so meshes are authored via Blender’s Python API (headless) instead. Preview renders use Cycles on CPU because the environment has no GPU.

### Headless checks

```bash
cd godot
for t in smoke_procgen smoke_monster_doors smoke_monster_track smoke_game_loop smoke_flow_screens smoke_player_anims smoke_flashlight smoke_shop smoke_loadout smoke_enemies smoke_widow_tarantula smoke_toad_attack smoke_level_progression smoke_touch_controls; do
  godot --headless -s res://tools/$t.gd
done
```

`smoke_procgen.gd` covers the room-module contract (including both stairwells), seed replay, layout variety, full connectivity, doorway carving, collision cooking and the monster track graph. `smoke_level_progression.gd` also checks two-wing floors, locked stairs, floor-scoped instantiation, and high-level spawn scatter.

### Gameplay notes

- **Lighting**: Level 1 has no sun. Ambient is 10% so you can pick a path with the flashlight off. Hold **RMB** or deflect the **right stick** to turn on the flashlight and aim the prisoner (and the cone); WASD / the **left stick** still strafes independently. Release to go dark again. The glowing objective is the other light; collecting it lights a green exit beacon.
- **Touch**: during a level, the left stick moves (a full shove runs), the right stick aims the flashlight and the prisoner, and **USE** picks up or takes stairs. On a phone there is no attack button and no reload key: while the right stick is aimed at a monster the prisoner swings, or fires the equipped gun. An empty magazine refills from reserve on its own; a partly spent magazine stays until it is empty. The left stick does not fire. Keyboard and mouse still work beside the sticks, and **R** still reloads on a keyboard.
- **Camera**: the isometric view is zoomed 50% onto the player (ortho size 20 → 13.3).
- **Objectives**: a level has `n + 1` objectives. Level 1 is the steam valve plus the glowing mission item. Level `n>1` adds `n-1` keys; each key unlocks the next locked-door wing. The mission item is in the last wing, behind a doorway blocked by steam. Follow the glowing pipes to the boiler and press **E** to shut the valve; that clears the steam. Then press **E** to collect a key or the mission item, and reach the exit doorway of the start room without dying.
- **Alarm**: collecting the item halves every enemy's dwell timer and doubles its proximity detection radius, and turns on the green exit glow.
- **Win / lose**: escaping with the item awards **5 rations** and brings up the fat aristocrat ("Well, you survived. Good for you. Here is your ration reward"); dying brings up the fat aristocrat ("Finally, you are no longer a drain on the motherland") and returns to the title screen.
- **Shop**: the Pip-Boy map has **SHOP** in the top right. Cards are **pistol** (5 rations, fires 10 damage along the aim), **speed upgrade** (1 ration, +5% speed, stackable), and **sneak** (3 rations, hold **Ctrl** with the flashlight off to avoid sight detection). **LMB** is always attack on desktop: unarmed it is a short melee swing (10 damage); with the pistol equipped it fires the weapon. On a phone, aim the right stick at an enemy to do the same thing.
- **Doorways**: every adjacent room is linked by an open wall gap; player and enemies can walk through. Outward-facing walls are sealed.
- **Enemies**: the roster grows with the level (`n` monsters, cycling slime → hare → tank → tarantula → widow → toad). They share the generated monster track (room centres through doorway centres). Locked doors omit their track edge until the matching key is collected. At a track intersection each rolls 0–99 and turns left (0–24), right (25–49), up (50–74) or down (75–99). When one detects the player (proximity, or FOV + line of sight) it path-follows the track toward them; 5 seconds after losing detection it returns to the main track. Sneak owned + Ctrl with the light off skips sight detection.
  - **Hare** (the `Monster` body): irradiated hare, `Walk` / `Attack`. 100 HP, lethal touch (100).
  - **Slime**: Charlie's Poly Pizza slime, scaled to about a metre. Fast, 45 HP, 35 touch damage, plays `idle` / `moving` / `hit` / `attack` / `death`. Over 30 seconds it doubles in size and health, then splits into two original-sized slimes; each child repeats the cycle (capped at 16 living slimes).
  - **Tank**: Left 4 Dead-style brute in jeans. Slow, 320 HP, lethal touch, hulking knuckle-dragger silhouette.
  - **Tarantula**: medium spider. 100 HP, 50 touch damage. Spends 30 seconds webbing its current room, then moves to another unwebbed room. Finished silk cuts player speed by 75%; the tarantula itself is 25% faster on its web and will chase a seen player off it. Losing focus sends it to the nearest unwebbed room to spin a new one.
  - **Widow**: dangerous woman in a black mourning dress and veil, pale skin. 250 HP, lethal touch (100).
  - **Toad**: easy, passive scavenger. 200 HP, no touch damage. Spends 10 seconds in each room looking for the mission item; if the item is there it swallows it and keeps it until it dies, then drops it.
  - From level 2 the roster is scattered through the allowed wings instead of parking on the closest/furthest leftover cell.
- **Health**: player starts at 100 HP with a billboard bar. Enemy bars stay hidden until the flashlight cone hits them (or they take damage).

## Player character

The level instances `godot/assets/characters/Meshy_AI_Gulag_Winter_Warden_All_Animations.glb`. That mesh faces +Z, so it is turned 180° under the player. Its clips are `Walking`, `Running`, and `air_squat`; `Player.gd` maps those to `Walk`, `Run`, a held first frame named `Idle`, and the downward half of the squat named `Die`.

`blender/build_prisoner.py` still authors the older bald prisoner (`godot/assets/characters/player_prisoner.glb`) for inspection. The notes below describe that mesh, not the warden used in game.

- **Mesh**: 1.80 m tall, 3981 verts / 7696 tris, lofted from superellipse rings. The skull comes from measured width/depth profile tables rather than a deformed ellipsoid, so it has a jaw and a chin; nose, brows, eyes and ears are planted on numerically sampled surface points.
- **Texture**: wear is authored as procedural noise shaders and then Cycles-baked to one 1024² colour atlas, because glTF cannot carry shader nodes. Grime is weighted by object-space height, so dirt collects on the boots and knees. Three materials (fabric, leather, skin) share the atlas.
- **Rig**: 17 bones, skinned with inverse-distance weights restricted to a per-part bone whitelist. Bone-heat auto weights bleed across the overlapping lofted parts.
- **Clips**: `Idle` (96 f loop), `Walk` (24 f loop), `Run` (16 f loop), `Die` (34 f one-shot), exported through muted NLA tracks. The gait is phased from foot contact, with knee flex, ankle counter-rotation to keep planted feet flat, toe-off and a pelvis bob.
- **Playback**: `Player.gd` sets `LOOP_LINEAR` on the three cycles at load — the glTF importer leaves every clip one-shot — picks walk or run by ground speed, and scales the playback rate to the distance covered per cycle so the boots do not skate. WASD walks; hold **Shift** to run. Hold **RMB** to keep the flashlight on and face the cursor; movement and facing are independent while aiming. **LMB** always attacks: unarmed this is a melee swing in the facing / aim direction; if the pistol is owned it fires along that aim. On a phone the right stick does that attack while it points at a monster. Hold **Ctrl** with sneak owned and the light off to slip the monster's sight cone.

## Android APK

On-screen controls are part of the Godot level. `scripts/build_android_apk.sh` installs the matching Godot 4.4.1 Android export templates and the Android SDK command-line tools if they are missing, then exports a debug APK with the prebuilt template (no Gradle project). The debug keystore is the standard Android debug key (`androiddebugkey` / `android`) and is not committed.

```bash
npm run android:apk
# or: bash scripts/build_android_apk.sh
# writes releases/nuclear-winter.apk
adb install -r releases/nuclear-winter.apk
```

Copy `releases/nuclear-winter.apk` onto the phone and open it. Android will ask you to allow installs from unknown sources. The package id is `com.nuclearwinter.game`. The phone stays in landscape. The APK includes the arm64-v8a build, which covers current phones. Prebuilt APKs are attached to [GitHub Releases](https://github.com/nhudson99/nuclear-winter/releases) (the file is too large to keep in git).

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
  assets/characters/{Meshy_AI_Gulag_Winter_Warden_All_Animations,player_prisoner,IrradiatedHare,enemy_monster,enemy_slime,enemy_tank,enemy_widow,enemy_tarantula,enemy_toad}.glb
  assets/props/{crate,wardrobe,couch}.glb
  scenes/{TitleScreen,AristocratScreen,GameMap,Main}.tscn
  scripts/{SceneFlow,GameProgress,LevelRules,MapGenerator,LockedDoor,Stairwell,TitleScreen,AristocratScreen,GameMap,ShopMenu,Main,Player,TouchControls,Monster,Tarantula,Toad,RoomWeb,WebField,PickupItem,ExitZone,Bullet}.gd
  tools/smoke_flow_screens.gd
  tools/smoke_game_loop.gd
  tools/smoke_shop.gd
  tools/smoke_loadout.gd
  tools/smoke_enemies.gd
  tools/smoke_widow_tarantula.gd
  tools/smoke_toad_attack.gd
  tools/smoke_level_progression.gd
  tools/smoke_touch_controls.gd
blender/
  build_rooms.py          # tileable rooms; dresses shells with Pripyat props
  PripyatApartment_FBX_PBR/  # Soviet apartment PBR pack used by build_rooms.py
  build_mansion_map.py
  build_prisoner.py
  render_prisoner.py
  build_monster.py
  build_tank.py
  build_widow.py
  build_tarantula.py
  build_toad.py
  prepare_slime.py
  build_furniture.py
  ussr_mansion_map.blend
  enemy_monster.blend
  enemy_tank.blend
  SlimeEnemy.glb
  furniture_props.blend
  reference_floorplan.png
src/                       Phaser title + tutorial
public/assets/             Title / boss / pip-boy art
```
