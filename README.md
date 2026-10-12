# Smart Throttle & Brake Assistant

Smart throttle and brake assistance that works on **any vehicle**, regardless of its native
ABS/TCS/ESC configuration. It caps the player's brake/throttle input to limit wheel
lock and wheel spin.
**This is a mod with a minimal implementation (POC)**, the basic logic is copied from **ai.lua**. 
It's imperfect, but works fairly well in most situations.

## Usage
- Open the "Smart Throttle & Brake Assistant" app (GuiApp) from the app menu and toggle ABS/TCS.
- Use the right arrow for the next mode and the left arrow for the previous mode.
  Modes cycle through `performance`, `grip`, and `legacy`, wrapping at either end.
- The default mode is `legacy`.
- The parameters app exposes minimum reference speed and tolerance for `performance`
  and `grip`; the minimum coefficient step is fixed at `0.01`, not configurable.
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
- `lua/vehicle/extensions/universalAbsTcs.lua`: runs on each graphics update on the vehicle,
  reading per-wheel slip/downforce and writing `electrics.values.brakeOverride` /
  `throttleOverride` (the same override mechanism used by cruise control), only while
  the player is actively braking/accelerating. The standard vehicle controller reads
  these overrides on its next graphics update.
- In `performance` and `grip` modes, the slip ratio of each wheel is computed from the
  current wheel speed magnitude versus the longitudinal vehicle speed, without
  prediction or additional wheel speed smoothing.
- Each wheel owns an integrator coefficient clamped to `[0, 1]`: it is raised below
  its target slip, lowered above it, and held at the target. For a positive target,
  the step is `0.01 * (1 + abs(target - slip) / target)`: it has a minimum of `0.01`
  and increases with relative error without a step ceiling. There is no deadband.
  `performance` uses a load-weighted average; `grip` uses the smallest coefficient.
  The target comes from the wheel's ABS slip setting, not a measured grip optimum.
  The step applies per graphics update, so the reaction rate follows the graphics rate.
- The computed coefficient is applied directly to the pedal input, without additional
  smoothing. Integrator states restart at `1` after the assist is disabled, modes
  change, AI takes control, or the vehicle is reset.
- Automatically loosens the assist on low-grip/off-road surfaces
  (`obj:getStaticFrictionCoef()`) when tolerance is `default`. This is a friction-based
  heuristic, not a per-wheel loose-surface detector.

## Standalone mod
This folder is self-contained (`lua/` + `ui/`) and independent from any other mod.
