# Smart Throttle & Brake Assistant

Smart throttle and brake assistance that works on **any vehicle**, regardless of its native
ABS/TCS/ESC configuration. It caps the player's brake/throttle input to limit wheel
lock and wheel spin.
**This is a mod with a minimal implementation (POC)**, the basic logic is copied from **ai.lua**. 
It's imperfect, but works fairly well in most situations.

## Usage
- Open the "Smart Throttle & Brake Assistant" app (GuiApp) from the app menu and toggle ABS/TCS.
- Use the arrows in the app to choose `performance`, `grip`, or `legacy` mode.
- Or from the console / another mod:
  ```lua
  extensions.load('universalAbsTcs')
  universalAbsTcs.setAbsEnabled(true)
  universalAbsTcs.setTcsEnabled(true)
  universalAbsTcs.setMode("grip") -- "performance", "grip", or "legacy"
  -- or both at once
  universalAbsTcs.setEnabled(true, true)
  ```

## How it works
- `lua/ge/extensions/universalAbsTcs.lua`: tracks the enabled state and (re)applies it
  to the player's current vehicle, including across vehicle switches/respawns.
- `lua/vehicle/extensions/universalAbsTcs.lua`: runs at graphics rate on the vehicle,
  reading per-wheel slip/downforce and writing `electrics.values.brakeOverride` /
  `throttleOverride` (the same override mechanism used by cruise control), only while
  the player is actively braking/accelerating. The extension's `updateGFX` hook runs
  after the standard vehicle controller, which reads these overrides on its next
  graphics update.
- In `performance` and `grip` modes, wheel speed is predicted using angular
  acceleration, wheel direction, dynamic radius, and the anticipation horizon.
  Predicted speed magnitude is clamped at zero during deceleration to avoid a false
  speed increase after a predicted wheel lock. Angular acceleration uses consecutive
  graphics samples and their elapsed simulation time, not the previous physics-step
  velocity. The first sample after enabling, changing modes, AI control, or a vehicle
  reset uses zero acceleration.
- Above the target slip, the pedal coefficient is `(target / slip)^aggressivity`.
  `performance` uses a load-weighted average; `grip` uses the smallest coefficient.
  The target comes from the wheel's ABS slip setting, not a measured grip optimum.
- Pedal reduction is immediate and recovery is progressive. Smoothing starts fresh
  after the pedal is released, the assist is disabled, AI takes control, or the
  vehicle is reset.
- Automatically loosens the assist on low-grip/off-road surfaces
  (`obj:getStaticFrictionCoef()`) when tolerance is `default`. This is a friction-based
  heuristic, not a per-wheel loose-surface detector.

## Standalone mod
This folder is self-contained (`lua/` + `ui/`) and independent from any other mod.
