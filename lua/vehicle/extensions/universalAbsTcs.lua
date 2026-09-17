-- Universal ABS/TCS: virtual driving aid
-- Limits the player's brake/throttle inputs to avoid wheel lock (braking) and wheel spin (acceleration)
-- Works on any vehicle, regardless of its native ABS/TCS/ESC configuration
-- Global reference-slip controller: one pedal command, load-weighted wheel feedback.

local M = {}

local min, max, abs = math.min, math.max, math.abs
local mode = "performance" -- "performance" (load-weighted average, maximizes braking/traction) or "grip" (worst wheel, maximizes stability)
local lowSpeedReference = 5
local tolerance = "default"
local anticipationTime = 0.05 -- default: 50ms
local aggressivity = 2.0 -- 1.5 à 2.5

local function getSlipCoef(slipRatio, targetSlipRatio, aggressivity)
  targetSlipRatio = targetSlipRatio * ((tolerance == "default" and (obj:getStaticFrictionCoef() < 0.9 and 120 or 100) or tolerance) / 100)
  if targetSlipRatio <= 0 then return slipRatio <= 0 and 1 or 0 end
  if slipRatio <= targetSlipRatio then return 1 end

  aggressivity = aggressivity or 2.0
  local ratio = targetSlipRatio / slipRatio
  return ratio ^ aggressivity
end

local absEnabled = false
local tcsEnabled = false
local wroteBrake = false
local wroteThrottle = false
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

local function setParameters(lowSpeedReferenceValue, toleranceValue, anticipationTimeValue, aggressivityValue)
  if type(lowSpeedReferenceValue) ~= "number"
      or type(anticipationTimeValue) ~= "number"
      or type(aggressivityValue) ~= "number" then
    return false
  end
  if toleranceValue ~= "default" and type(toleranceValue) ~= "number" then
    return false
  end

  lowSpeedReference = max(lowSpeedReferenceValue, 0)
  tolerance = toleranceValue
  anticipationTime = max(anticipationTimeValue, 0)
  aggressivity = max(aggressivityValue, 0)
  return true
end

local function getParameters()
  return {
    lowSpeedReference = lowSpeedReference,
    tolerance = tolerance,
    anticipationTime = anticipationTime,
    aggressivity = aggressivity,
  }
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
  local dtInv = dt > 0 and (1 / dt) or 0
  local lwheels = wheels.wheels
  for i = 0, tableSizeC(lwheels) - 1 do
    local wd = lwheels[i]
    if not wd.isBroken then
      local downForce = max(wd.downForceRaw or 0, 0)
      local wheelSpeed = abs(wd.wheelSpeed or 0)
      local peakSlipRatio = min(max(wd.slipRatioTarget or 0.18, 0), 1)
      local radius = wd.radius or wd.dynamicRadius
      local lastAngVel = wd.lastAngularVelocity or wd.angularVelocity or 0
      local angAccel = (wd.angularVelocity - lastAngVel) * dtInv
      local wheelAccel = angAccel * radius -- m/s²
      local predictedWheelSpeed = max(0, wheelSpeed + wheelAccel * anticipationTime)
      local brakeSlipRatio = max(0, (speed - predictedWheelSpeed) / slipReferenceSpeed)
      local driveSlipRatio = max(0, (predictedWheelSpeed - speed) / slipReferenceSpeed)
      local driveTargetSlipRatio = min(peakSlipRatio, 1)
      local brakeCoef = getSlipCoef(brakeSlipRatio, peakSlipRatio, aggressivity)
      local propCoef = getSlipCoef(driveSlipRatio, driveTargetSlipRatio, aggressivity)

      if wd.brakeTorque > 0 then
        brakeCoefWeighted = brakeCoefWeighted + brakeCoef * downForce
        totalDownForce = totalDownForce + downForce
        brakeCoefGrip = min(brakeCoefGrip, brakeCoef)
      end

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
M.setParameters = setParameters
M.getParameters = getParameters
M.updateGFX = updateGFX

return M
