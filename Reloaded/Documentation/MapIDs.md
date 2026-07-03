#======================================================
# Reloaded Map IDs
# Author: Stonewall
#======================================================
# Reference list of RPG Maker map IDs used by Hoenn Reloaded.
#
# Responsibilities:
#   - Record map IDs from Data/MapInfos.rxdata.
#   - Help modders write encounter patches against the correct map IDs.
#   - Provide the <map_id>_<version> format used by encounter data patches.
#
#======================================================

This file lists map IDs from:

```text
Data/MapInfos.rxdata
```

Encounter data patch IDs use:

```text
<map_id>_<version>
```

Example:

```text
5_0
```

This means map ID `5`, encounter version `0`.

## How To Use This File

Use the `Map ID` column when writing encounter patches. For example, Route 101
is map ID `5`, so the default Route 101 encounter entry is:

```text
5_0
```

Do not use the `Parent ID` as the encounter map ID. Parent IDs are only the RPG
Maker editor hierarchy. They explain where a map sits in the map tree, such as
`Routes`, `Cities`, `Dungeons`, or another route folder.

Map names are editor labels and can repeat. The numeric map ID is the stable
value the game uses at runtime. If two rows have similar names, use the row for
the actual map the player is standing on.

## Encounter Versions

Encounter versions are not stored in `MapInfos.rxdata`. They come from the
encounter data and from `$PokemonGlobal.encounter_version` at runtime.

Reloaded encounter patch IDs combine both values:

```text
<map_id>_<version>
```

Common examples:

```text
5_0   # Route 101, default encounters
10_0  # Route 102, default encounters
77_0  # Route 111 (South), default encounters
```

Most maps use version `0`. Use another version only when the base game has an
alternate encounter table for that same map.

To know whether a map has another encounter version, check the compiled
encounter data for the same map ID with a different version number. The entry
ID will be the same map ID with a different suffix, such as:

```text
5_0
5_1
5_2
```

At the time this reference was generated, the base Hoenn Reloaded encounter
data only contained version `0` entries for classic, remix, and randomized
encounters. That means modders should normally use `<map_id>_0` unless a future
base update or another Reloaded system adds alternate versions.

The active encounter version is read from:

```text
$PokemonGlobal.encounter_version
```

The base game defaults this value to `0`. The debug menu can change it for
testing, but changing it does not matter unless encounter data exists for that
version.

## Encounter Targets

The encounter target decides which game mode receives the patch:

- `encounters.classic` - normal/classic encounter data.
- `encounters.remix` - modern/remix encounter data.
- `encounters.randomized` - randomized encounter data.

If the game is currently using modern/remix encounters, a patch to
`encounters.classic` may not affect the active encounter table. Patch the target
that matches the mode you want to change.

## Replacing Or Adding Encounters

Use `add_types` when adding entries to an existing table. The `chance` value is
a weight, not a guaranteed percent.

Use `types` when replacing the full encounter table. For example, this makes
Route 101 land encounters choose Treecko from the only available slot:

```json
{
  "target": "encounters.classic",
  "operation": "merge",
  "id": "5_0",
  "data": {
    "types": {
      "Land": [
        {
          "chance": 100,
          "species": "treecko",
          "min_level": 5,
          "max_level": 5
        }
      ]
    }
  }
}
```

## Common Encounter Maps

| Map ID | Parent ID | Name |
| ---: | ---: | --- |
| 5 | 4 | Route 101 |
| 10 | 4 | Route 102 |
| 11 | 4 | Route 103 |
| 12 | 4 | Route 104 (South) |
| 20 | 4 | Route 104 (North) |
| 28 | 29 | Rusturf Tunnel |
| 30 | 29 | Petalburg Woods |
| 31 | 4 | Route 116 |
| 32 | 29 | Granite Cave 1F |
| 34 | 32 | Granite Cave B1F |
| 35 | 32 | Granite Cave B2F |
| 37 | 4 | Route 107 |
| 38 | 4 | Route 108 |
| 39 | 4 | Route 109 |
| 40 | 71 | Route 110 |
| 49 | 4 | Route 106 |
| 50 | 4 | Route 105 |
| 65 | 4 | Route 115 |
| 70 | 29 | Altering Cave |
| 71 | 4 | Route 110 |
| 74 | 4 | Route 117 |
| 76 | 4 | Route 118 |
| 77 | 4 | Route 111 (South) |
| 104 | 77 | Route 111 |
| 106 | 29 | New Mauville |

## All Map IDs

| Map ID | Parent ID | Name |
| ---: | ---: | --- |
| 1 | 0 | Hoenn |
| 2 | 7 | Petalburg Town_diveTest |
| 3 | 1 | Cities |
| 4 | 1 | Routes |
| 5 | 4 | Route 101 |
| 6 | 3 | Slateport City |
| 7 | 3 | Petalburg Town |
| 8 | 3 | Oldale Town |
| 9 | 3 | Littleroot Town |
| 10 | 4 | Route 102 |
| 11 | 4 | Route 103 |
| 12 | 4 | Route 104 (South) |
| 13 | 9 | Littleroot Interiors |
| 14 | 9 | Truck |
| 15 | 0 | New maps |
| 16 | 15 | Kiwi |
| 17 | 15 | Paya |
| 18 | 9 | Professor Birch's Lab |
| 19 | 12 | Route 104 (South) |
| 20 | 4 | Route 104 (North) |
| 21 | 175 | EVENT_TEMPLATES |
| 22 | 175 | Cinematics |
| 23 | 175 | Common Maps |
| 24 | 23 | PokeMart |
| 25 | 23 | Pokemon Center |
| 26 | 23 | Wonder Trade Center |
| 27 | 23 | Happy Birthday! |
| 28 | 29 | Rusturf Tunnel |
| 29 | 1 | Dungeons |
| 30 | 29 | Petalburg Woods |
| 31 | 4 | Route 116 |
| 32 | 29 | Granite Cave 1F |
| 33 | 32 | Granite Cave 1F-2_alt |
| 34 | 32 | Granite Cave B1F |
| 35 | 32 | Granite Cave B2F |
| 36 | 32 | Granite Cave 1F-2 |
| 37 | 4 | Route 107 |
| 38 | 4 | Route 108 |
| 39 | 4 | Route 109 |
| 40 | 71 | Route 110 |
| 41 | 17 | quest_route 104N |
| 42 | 17 | Orre Desert |
| 43 | 17 | MAP043 |
| 44 | 17 | MAP044 |
| 45 | 17 | MAP045 |
| 46 | 17 | MAP046 |
| 47 | 3 | Rustboro City |
| 48 | 47 | Rustboro Interiors |
| 49 | 4 | Route 106 |
| 50 | 4 | Route 105 |
| 51 | 3 | Dewford Town |
| 52 | 16 | MAP052 |
| 53 | 16 | MAP053 |
| 54 | 16 | MAP054 |
| 55 | 16 | MAP055 |
| 56 | 16 | MAP056 |
| 57 | 8 | PokeMart |
| 58 | 12 | Seaside Cottage |
| 59 | 8 | Oldale Interiors |
| 60 | 7 | Petalburg Interiors |
| 61 | 7 | Petalburg Gym |
| 62 | 30 | Hidden Clearing |
| 63 | 20 | Flower Shop |
| 64 | 175 | Secret Base |
| 65 | 4 | Route 115 |
| 66 | 65 | Secret Base |
| 67 | 22 | On the road! |
| 68 | 6 | Slateport Interiors |
| 69 | 49 | Hidden Cove |
| 70 | 29 | Altering Cave |
| 71 | 4 | Route 110 |
| 72 | 103 | testing |
| 73 | 3 | Mauville City |
| 74 | 4 | Route 117 |
| 75 | 73 | Mauville City Interiors |
| 76 | 4 | Route 118 |
| 77 | 4 | Route 111 (South) |
| 78 | 47 | Rustboro Gym |
| 79 | 51 | Dewford Gym |
| 80 | 51 | Dewford Gym |
| 81 | 51 | Dewford Town Interiors |
| 82 | 39 | Seashore House |
| 83 | 3 | Verdanturf Town |
| 84 | 83 | Verdanturf Interiors |
| 85 | 22 | Space Station |
| 86 | 31 | Route 116 |
| 87 | 6 | Oceanic Museum |
| 88 | 6 | Stern's Shipyard |
| 89 | 6 | Slateport Harbor |
| 90 | 11 | Magma Camp |
| 91 | 87 | cutscene_1 |
| 92 | 105 | PokeMart_Kanto |
| 93 | 175 | QUEST_TEMPLATES |
| 94 | 23 | Clothing Boutique |
| 95 | 105 | PokeMart_combined |
| 96 | 73 | Game Corner |
| 97 | 30 | Illusion Grove |
| 98 | 97 | Illusion Grove |
| 99 | 71 | Trick House |
| 100 | 103 | Clothes testing |
| 101 | 74 | Pokemon Day Care |
| 102 | 73 | Mauville Gym |
| 103 | 175 | DEBUG |
| 104 | 77 | Route 111 |
| 105 | 23 | archive |
| 106 | 29 | New Mauville |
| 107 | 99 | Trick House 2 |
| 108 | 99 | Trick House 1 |
| 109 | 11 | Cliffside Sanctuary |
| 110 | 23 | Contest Hall |
| 111 | 109 | Cliffside Sanctuary |
| 112 | 50 | Underwater |
| 175 | 0 | COMMON |
| 295 | 22 | Intro |
| 751 | 22 | Credits |
