# Hatchling's Weapon Wheel

A customizable weapon wheel for Queen's Domain.

Hold **Alt**, move the mouse over a weapon, and release Alt to equip it. The world runs at **10% speed** while the wheel is open. Music and effects are pitched down and filtered, returning to normal when you release Alt.

## Controls

- **Left Alt / Right Alt:** hold to open; release to select.
- **Mouse wheel:** change pages.
- **Escape / right click:** cancel.
- **F10:** open or close customization.

Releasing Alt with the cursor in the center or outside the ring keeps your current weapon. The center shows the hovered weapon's icon, or your equipped weapon when nothing is hovered.

## Customization

In F10, click owned weapons to add or remove them. Select a weapon in the ordered list and use **Move Up**, **Move Down**, or **Remove**. **Add All** adds every owned primary weapon. Changes save automatically.

Favorites can span multiple pages, with eight weapons per page by default. Selecting an unequipped weapon replaces the active equipped slot; the normal three-slot cycling still works. Throwing weapons are not included. The F10 menu also slows the world to 10%; it does not pause combat.

## Installation

Tested on **Queen's Domain 1.01.03** with **UE4SS 3.0.1-1194-ge84db30c**.

1. Close the game. If UE4SS is not installed, download the [tested UE4SS build](https://github.com/derlocke-ng/queens-maiden-save-mod/releases/download/ue4ss-e84db30c/zDEV-UE4SS_v3.0.1-1194-ge84db30c.zip) and extract `dwmapi.dll` and the `ue4ss` folder into `QueensDomain\Binaries\Win64`.
2. In `ue4ss\UE4SS-settings.ini`, set `EnableAutoReloadingLuaMods = 0` under `[General]`. To hide the loader's debug windows, set `ConsoleEnabled = 0`, `GuiConsoleEnabled = 0`, and `GuiConsoleVisible = 0` under `[Debug]`.
3. Download the mod ZIP from [Releases](https://github.com/Ethan0429/queens-domain-weapon-wheel/releases/latest) and extract it. Copy `Mods\QueensWeaponWheel` into `QueensDomain\Binaries\Win64\ue4ss\Mods`.
4. Add this line to `ue4ss\Mods\mods.txt`, then start the game:

```text
QueensWeaponWheel : 1
```

Alternatively, after installing UE4SS, run the included installer from the extracted mod folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -GameDirectory "C:\path\to\game"
```

Use the folder containing `QueensDomain.exe`. The installer backs up an existing copy of the mod and preserves other mods. Always close the game before updating mod files.

## Configuration

Favorites are stored separately from game saves:

```text
%LOCALAPPDATA%\QueensDomain\Saved\WeaponWheel\config.lua
```

F10 edits apply immediately. To change `slots_per_page` manually (4–12), close the game, edit this file, and restart.

## Removal

Close the game, delete `ue4ss\Mods\QueensWeaponWheel`, and remove its line from `mods.txt`. Or run `Uninstall.ps1` with the same `-GameDirectory` argument. Saves and wheel configuration are retained.
