PRIPYAT APARTMENT - Abandoned Soviet Home Props
===============================================

101 game-ready, PBR-textured props for an abandoned Soviet apartment block
(Pripyat, 1986): kitchen, bathroom, living room, bedroom, kids' room, hallway,
stairwell & architecture pieces and abandonment clutter.


FOLDER LAYOUT
-------------
<Room>/SM_<AssetName>/
    SM_<AssetName>.fbx
    T_<AssetName>_BaseColor.png                  sRGB
    T_<AssetName>_Normal.png                     tangent space, OpenGL (Y+)  -> Blender, Godot, Unity
    T_<AssetName>_Normal_DirectX_Unreal.png      tangent space, DirectX (Y-) -> Unreal Engine
    T_<AssetName>_Roughness.png                  linear
    T_<AssetName>_Metallic.png                   linear
    T_<AssetName>_ORM_Unreal.png                 linear, R = AO (white), G = Roughness, B = Metallic
    T_<AssetName>_MetallicSmoothness_Unity.png   linear, RGB = Metallic, A = Smoothness (URP/HDRP Lit)

Preview/overview.png - every asset at a glance.


FBX DETAILS
-----------
- Units: meters (1 unit = 1 m). Real-world scale.
- Axes: Y up, -Z forward. The front of each asset faces -Y in Blender.
- One UV channel (UV0), non-overlapping (glass faces excluded), used by all textures.
- Most assets use one material slot. Glass parts (windows, mirrors, glass doors,
  bottles, glassware) are a separate material slot named M_Glass_*.
  Give it a transparent material, suggested values:
    Clear glass:  color (0.70, 0.72, 0.70), roughness 0.08, opacity 0.20
    Green glass:  color (0.45, 0.60, 0.48), roughness 0.08, opacity 0.40
- Total: about 990,352 triangles (LOD0). The pack is detailed; in Unreal Engine use
  Nanite (the UE project has it enabled), in other engines generate LODs.


UNREAL ENGINE 5.8 PROJECT (separate download)
---------------------------------------------
- 101 static meshes, 2 master materials (PBR + translucent glass), material instances.
- Nanite on (assets with glass: Nanite off + 4 LODs), simple box collision.
- Map: Overview (all assets laid out by room).
- Open PripyatApartment.uproject with Unreal Engine 5.8, or migrate the
  Content/PripyatApartment folder into your own project.


HOW THIS PACK WAS MADE
----------------------
All models and textures were generated procedurally (Blender scripts),
with the help of an AI assistant that wrote the generation code.


ASSET LIST (triangles, texture resolution)
------------------------------------------
Kitchen (18)
  SM_BreadBox                          2,056 tris    512 px
  SM_Canisters_Set                     6,712 tris   1024 px
  SM_CannedFood_Set                   11,610 tris    512 px
  SM_DishRack                         12,000 tris   1024 px
  SM_FryingPan_CastIron                1,698 tris   1024 px
  SM_GasStove_4Burner                 11,872 tris   1024 px
  SM_GasWaterHeater                    9,340 tris   1024 px
  SM_KitchenCabinet_Base               8,072 tris   1024 px   glass: clear
  SM_KitchenCabinet_Wall               9,228 tris   1024 px   glass: clear
  SM_KitchenSink_Cabinet               6,534 tris   1024 px
  SM_KitchenStool_Metal                2,188 tris   1024 px
  SM_KitchenTable_Formica              2,276 tris   1024 px
  SM_MeatGrinder_Manual                3,206 tris    512 px
  SM_MilkBottle_Glass                  1,776 tris    512 px   glass: clear
  SM_Plates_Stack                      8,836 tris    512 px
  SM_Pot_Enamel_Set                    8,780 tris   1024 px
  SM_Samovar_Electric                  6,976 tris   1024 px
  SM_Teapot_Porcelain                  3,010 tris    512 px

Bathroom (11)
  SM_BathShelf_Glass                   6,040 tris   1024 px   glass: clear
  SM_Bathtub_CastIron                  9,472 tris   2048 px
  SM_MirrorCabinet                     5,826 tris   1024 px   glass: clear
  SM_ShowerHose                        7,652 tris   1024 px
  SM_SoapDish                          2,260 tris    512 px
  SM_Toilet_HighCistern                8,822 tris   2048 px
  SM_TowelRail_Heated                  3,888 tris   1024 px
  SM_Wall_Tiled_2m                     8,276 tris   2048 px
  SM_WashTub_Zinc                      5,702 tris   1024 px
  SM_Washbasin_Pedestal               10,910 tris   1024 px
  SM_WashingMachine_Soviet             9,694 tris   1024 px

LivingRoom (19)
  SM_Armchair_Upholstered              3,840 tris   1024 px
  SM_Chandelier_3Arm                   6,084 tris   1024 px   glass: clear
  SM_CoffeeTable                       1,528 tris   1024 px   glass: clear
  SM_Crystal_Glassware                 2,684 tris   1024 px   glass: clear
  SM_DiningChair_Upholstered           6,548 tris   1024 px
  SM_DiningTable_Extendable            6,472 tris   1024 px   glass: clear
  SM_Figurines_Porcelain              27,060 tris   1024 px
  SM_FloorLamp                         3,644 tris   2048 px
  SM_PhotoFrames_Set                   1,634 tris    512 px   glass: clear
  SM_Piano_Upright                    15,490 tris   1024 px
  SM_Radiogram                         8,510 tris   1024 px   glass: clear
  SM_Rug_Floor                        11,568 tris   2048 px
  SM_Rug_Wall                          8,116 tris   2048 px
  SM_SewingMachine                     2,644 tris   1024 px
  SM_SofaBed                           9,944 tris   2048 px
  SM_VinylRecords                      5,478 tris   1024 px
  SM_WallUnit_Glass                   11,668 tris   2048 px   glass: clear
  SM_WallUnit_Shelves                  7,648 tris   2048 px   glass: clear
  SM_WallUnit_Wardrobe                13,080 tris   2048 px

Bedroom (11)
  SM_AlarmClock_TwinBell               7,276 tris    512 px
  SM_Bed_Double_Wooden                 3,740 tris   2048 px
  SM_CoatRack_Standing                19,068 tris   2048 px
  SM_Dresser_Mirror                   13,268 tris   2048 px   glass: clear
  SM_Hanger_Wire                       2,780 tris   1024 px
  SM_Iron_Electric                     1,764 tris   1024 px
  SM_IroningBoard                      1,114 tris   1024 px
  SM_Mattress_Stained                  7,512 tris   2048 px
  SM_Nightstand                        3,912 tris   1024 px   glass: clear
  SM_Suitcase_Old                      4,114 tris   1024 px
  SM_Suitcase_Open                     5,936 tris   1024 px

KidsRoom (11)
  SM_Ball_Rubber                       3,312 tris    512 px
  SM_ChildrensBooks                    8,890 tris   1024 px
  SM_Crib_Wooden                      18,182 tris   1024 px
  SM_Doll_Plastic                     42,100 tris    512 px
  SM_Globe                             5,204 tris    512 px
  SM_Pram_Soviet                      31,448 tris   1024 px
  SM_RockingHorse                     36,392 tris   1024 px
  SM_SchoolBackpack                    4,506 tris    512 px   glass: clear
  SM_ToyBlocks_Set                     8,242 tris    512 px
  SM_ToyPyramid                        6,370 tris    512 px
  SM_ToyTruck_Metal                    6,734 tris   1024 px

Hallway (10)
  SM_CoatRack_Wall                    17,820 tris   1024 px   glass: clear
  SM_Door_Entrance_Padded             28,778 tris   2048 px   glass: clear
  SM_Door_Interior_Glass               4,048 tris   2048 px   glass: clear
  SM_Doormat                           2,016 tris   1024 px
  SM_ElectricMeter_Panel               5,778 tris   1024 px   glass: clear
  SM_LightSwitch_Socket               21,464 tris   1024 px
  SM_Mirror_Wall                       3,004 tris   1024 px
  SM_ShoeCabinet                      21,920 tris   1024 px
  SM_Telephone_Wall                   12,478 tris   1024 px
  SM_Umbrella                          1,432 tris   1024 px

Stairwell & Architecture (12)
  SM_BalconyDoor                       4,160 tris   2048 px   glass: clear
  SM_BalconyRailing                   12,700 tris   2048 px
  SM_Baseboard_2m                      1,028 tris   2048 px
  SM_CeilingLamp_Bare                  7,348 tris   1024 px   glass: clear
  SM_Elevator_Door                     9,544 tris   2048 px
  SM_Floor_Linoleum_2m                10,724 tris   2048 px
  SM_Floor_Parquet_2m                 12,118 tris   2048 px
  SM_Mailboxes_Block                  10,298 tris   1024 px
  SM_Stairs_Segment                    7,072 tris   2048 px   glass: green
  SM_Wall_Wallpaper_A                  9,394 tris   2048 px
  SM_Wall_Wallpaper_B                  8,548 tris   2048 px
  SM_Window_DoubleFrame               18,098 tris   2048 px   glass: clear

Abandonment (9)
  SM_Chair_Broken                     12,604 tris   1024 px
  SM_Debris_Pile                      17,268 tris   1024 px
  SM_Drawer_Fallen                    21,996 tris   1024 px   glass: clear
  SM_GasMask                           9,462 tris    512 px   glass: clear
  SM_GasMask_Pile                     50,108 tris   1024 px   glass: clear
  SM_GlassShards                       1,518 tris   1024 px   glass: clear, green
  SM_Newspaper_Stack                  24,486 tris   1024 px
  SM_PhotoAlbum                       23,078 tris   1024 px
  SM_Wallpaper_Strips                  9,846 tris   2048 px
