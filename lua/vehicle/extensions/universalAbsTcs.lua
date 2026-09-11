-- Universal ABS/TCS: virtual driving aid
-- Limits the player's brake/throttle inputs to avoid wheel lock (braking) and wheel spin (acceleration)
-- Works on any vehicle, regardless of its native ABS/TCS/ESC configuration
-- Global reference-slip controller: one pedal command, load-weighted wheel feedback.

local M = {}

local min, max, abs = math.min, math.max, math.abs
local lowSpeedReference = 1.5

local function getSlipCoef(slipRatio, targetSlipRatio)
  if targetSlipRatio <= 0 then return slipRatio <= 0 and 1 or 0 end
  return slipRatio > targetSlipRatio and targetSlipRatio / slipRatio or 1
end

local absEnabled = false
local tcsEnabled = false
local wroteBrake = false
local wroteThrottle = false
local mode = "performance" -- "performance" (load-weighted average, maximizes braking/traction) or "grip" (worst wheel, maximizes stability)
-- local smoothTcs = newTemporalSmoothingNonLinear(0.4, 0.9, 1) -- native AI tuning
local smoothAbs = newTemporalSmoothing(math.huge, 2, nil, 1) -- instant cut, progressive recovery
local smoothTcs = newTemporalSmoothing(math.huge, 2, nil, 1) -- instant cut, progressive recovery

local function setEnabled(absOn, tcsOn)
  absEnabled = absOn == true
  tcsEnabled = tcsOn == true
  if not absEnabled and wroteBrake then
    electrics.values.brakeOverride = nil
    wroteBrake = false
  end
  if not tcsEnabled and wroteThrottle then
    electrics.values.throttleOverride = nil
    wroteThrottle = false
  end
  smoothAbs:set(1)
  smoothTcs:set(1)
end

local function setMode(newMode)
  if newMode == "grip" or newMode == "performance" then
    mode = newMode
  end
end

local function updateGFX(dt)
  if not (absEnabled or tcsEnabled) then return end

  -- longitudinal vehicle speed, same source as ai.lua (refactored)
  local vx, vy, vz = obj:getSmoothRefVelocityXYZ()
  local dx, dy, dz = obj:getDirectionVectorXYZ()
  local speed = abs(vx * dx + vy * dy + vz * dz)
  local slipReferenceSpeed = max(speed, lowSpeedReference)

  -- wheel scan
  local brakeCoefWeighted = 0
  local totalDownForce = 0
  local brakeCoefGrip = 1
  local propCoefWeighted = 0
  local propCoefSum = 0
  local propCoefGrip = 1
  local propDownForce = 0
  local propWheelCount = 0
  local lwheels = wheels.wheels
  for i = 0, tableSizeC(lwheels) - 1 do
    local wd = lwheels[i]
    if not wd.isBroken then
      local downForce = max(wd.downForceRaw or 0, 0)
      local wheelSpeed = abs(wd.wheelSpeed or 0)
      local peakSlipRatio = min(max(wd.slipRatioTarget or 0.18, 0), 1)
      local brakeSlipRatio = max(0, (speed - wheelSpeed) / slipReferenceSpeed)
      local driveSlipRatio = max(0, (wheelSpeed - speed) / slipReferenceSpeed)
      local driveTargetSlipRatio = min(peakSlipRatio, 1)
      local brakeCoef = getSlipCoef(brakeSlipRatio, peakSlipRatio)
      local propCoef = getSlipCoef(driveSlipRatio, driveTargetSlipRatio)

      brakeCoefWeighted = brakeCoefWeighted + brakeCoef * downForce
      totalDownForce = totalDownForce + downForce
      brakeCoefGrip = min(brakeCoefGrip, brakeCoef)

      if wd.isPropulsed then
        propCoefWeighted = propCoefWeighted + propCoef * downForce
        propCoefSum = propCoefSum + propCoef
        propDownForce = propDownForce + downForce
        propWheelCount = propWheelCount + 1
        propCoefGrip = min(propCoefGrip, propCoef)
      end
    end
  end
  local brakeModelCoef = totalDownForce > 0 and (mode == "grip" and brakeCoefGrip or brakeCoefWeighted / totalDownForce) or 0
  local propNoLoadCoef = propWheelCount > 0 and (mode == "grip" and propCoefGrip or propCoefSum / propWheelCount) or 1
  local propModelCoef = propDownForce > 0 and (mode == "grip" and propCoefGrip or propCoefWeighted / propDownForce) or propNoLoadCoef

  -- ABS
  if absEnabled and input.brake > 0 then
    electrics.values.brakeOverride = input.brake * smoothAbs:get(brakeModelCoef, dt)
    wroteBrake = true
  elseif wroteBrake then
    electrics.values.brakeOverride = nil
    wroteBrake = false
  end

  -- TCS
  if tcsEnabled and input.throttle > 0 then
    electrics.values.throttleOverride = input.throttle * smoothTcs:get(propModelCoef, dt)
    wroteThrottle = true
  elseif wroteThrottle then
    electrics.values.throttleOverride = nil
    wroteThrottle = false
  end
end

M.setEnabled = setEnabled
M.setMode = setMode
M.updateGFX = updateGFX

return M
