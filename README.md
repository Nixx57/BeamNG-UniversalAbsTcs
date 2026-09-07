# Universal ABS/TCS

Virtual ABS/TCS driving aid that works on **any vehicle**, regardless of its native
ABS/TCS/ESC configuration. It caps the player's brake/throttle input to limit wheel
lock and wheel spin.
**This is a mod with a minimal implementation (POC)**, the basic logic is copied from **ai.lua**. 
It's imperfect, but works fairly well in most situations.

## Usage
- Open the "Universal ABS/TCS" app (GuiApp) from the app menu and toggle ABS/TCS.
- Or from the console / another mod:
  ```lua
  extensions.load('universalAbsTcs')
  universalAbsTcs.setAbsEnabled(true)
  universalAbsTcs.setTcsEnabled(true)
  -- or both at once
  universalAbsTcs.setEnabled(true, true)
  ```

## How it works
- `lua/ge/extensions/universalAbsTcs.lua`: tracks the enabled state and (re)applies it
  to the player's current vehicle, including across vehicle switches/respawns.
- `lua/vehicle/extensions/universalAbsTcs.lua`: runs at graphics rate on the vehicle,
  reading per-wheel slip/downforce and writing `electrics.values.brakeOverride` /
  `throttleOverride` (the same override mechanism used by cruise control), only while
  the player is actively braking/accelerating.
- Automatically loosens the assist on low-grip/off-road surfaces
  (`obj:getStaticFrictionCoef()`), mirroring the native AI's off-road driving style.

## Standalone mod
This folder is self-contained (`lua/` + `ui/`) and independent from any other mod.
