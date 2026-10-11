-- Smart Throttle & Brake Assistant: virtual driving aid
-- Limits the player's brake/throttle inputs to avoid wheel lock (braking) and wheel spin (acceleration)
-- Works on any vehicle, regardless of its native ABS/TCS/ESC configuration
-- Global reference-slip controller: one pedal command, load-weighted wheel feedback.

local M = {}

local min, max, abs = math.min, math.max, math.abs
local mode = "performance" -- "performance" (load-weighted average), "grip" (worst wheel), or "legacy" (native AI controller)
local lowSpeedReference = 5
local tolerance = "default"
local anticipationTime = 0.05 -- default: 50ms
local aggressivity = 2.0 -- 1.5 à 2.5

local function getSlipCoef(slipRatio, targetSlipRatio, aggressivity)
  targetSlipRatio = targetSlipRatio * ((tolerance == "default" and (obj:getStaticFrictionCoef() < 0.9 and 120 or 100) or tolerance) / 100)
  if targetSlipRatio <= 0 then return slipRatio <= 0 and 1 or 0 end
  if slipRatio <= targetSlipRatio then return 1 end

  aggressivity = aggressivity or 2.0
  --   -- native revLimiterSoftMethod: linear ramp to 0 over a fixed overshoot range, no exponent
  -- local overshootRange = targetSlipRatio * aggressivity
  -- return 1 - min(slipRatio - targetSlipRatio, overshootRange) / overshootRange
  local ratio = targetSlipRatio / slipRatio
  return ratio ^ aggressivity
end

local absEnabled = false
local tcsEnabled = false
local wroteBrake = false
local wroteThrottle = false
local legacyTcs = newTemporalSmoothingHybrid(0.4, 0.9, 1, 0.01) -- native AI tuning + minimum rate
local smoothAbs = newTemporalSmoothing(math.huge, 2, nil, 1) -- instant cut, progressive recovery
local smoothTcs = newTemporalSmoothing(math.huge, 2, nil, 1) -- instant cut, progressive recovery
local previousAngularVelocities = {}
local legacy

local function clearOverrides()
  if wroteBrake then
    electrics.values.brakeOverride = nil
    wroteBrake = false
  end
  if wroteThrottle then
    electrics.values.throttleOverride = nil
    wroteThrottle = false
  end
  smoothAbs:set(1)
  smoothTcs:set(1)
  legacyTcs:set(1)
  previousAngularVelocities = {}
end

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
  legacyTcs:set(1)
  previousAngularVelocities = {}
end

local function setMode(newMode)
  if newMode == "grip" or newMode == "performance" or newMode == "legacy" then
    mode = newMode
    clearOverrides()
    return true
  end
  return false
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

  if not absEnabled or input.brake <= 0 then
    smoothAbs:set(1)
  end
  if not tcsEnabled or input.throttle <= 0 then
    smoothTcs:set(1)
    legacyTcs:set(1)
  end

  if extensions.ai and extensions.ai.mode and extensions.ai.mode ~= "disabled" then
    clearOverrides()
    return
  end

  if mode == "legacy" then
    legacy(dt)
    return
  end

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
      local downForce = max(wd.downForce or 0, 0)
      local wheelSpeed = wd.wheelSpeed or 0
      local peakSlipRatio = min(max(wd.slipRatioTarget or 0.18, 0), 1)
      local radius = wd.dynamicRadius or wd.radius
      local lastAngVel = previousAngularVelocities[wd] or wd.angularVelocity
      local angAccel = (wd.angularVelocity - lastAngVel) * dtInv
      previousAngularVelocities[wd] = wd.angularVelocity
      local wheelAccel = angAccel * wd.wheelDir * radius -- m/s²
      local wheelAccelMagnitude = wheelSpeed < 0 and -wheelAccel or wheelAccel
      -- Stop at zero instead of predicting a reversal during wheel lock.
      local predictedWheelSpeed = max(0, abs(wheelSpeed) + wheelAccelMagnitude * anticipationTime)
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
    else
      previousAngularVelocities[wd] = nil
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

legacy = function(dt)
    local ego = {
        dirVec = obj:getDirectionVector(),
        vel = vec3(obj:getSmoothRefVelocityXYZ()),
    }

    local dirVel = ego.vel:dot(ego.dirVec)
    local absegoSpeed = abs(dirVel)

    -- wheel speed
    local throttleTcsCoef = 1
    local brakeABSCoef = 1
    if absegoSpeed > 0.05 then
        if sensors.gz <= 0.1 then
            local totalSlip = 0
            local propSlip = 0
            local totalDownForce = 0
            local lwheels = wheels.wheels
            for i = 0, tableSizeC(lwheels) - 1 do
                local wd = lwheels[i]
                if not wd.isBroken then
                    local lastSlip = wd.lastSlip
                    local downForce = wd.downForceRaw
                    totalSlip = totalSlip + lastSlip * downForce
                    totalDownForce = totalDownForce + downForce
                    if wd.isPropulsed then
                        propSlip = max(propSlip, lastSlip)
                    end
                end
            end

            absegoSpeed = max(absegoSpeed, 3)

            totalSlip = totalSlip / (totalDownForce + 1e-25)

            -- abs
            brakeABSCoef = min(1, 1.5 * square(square(square(max(0, absegoSpeed - totalSlip) / absegoSpeed))))

            -- tcs
            propSlip = propSlip * ((obj:getStaticFrictionCoef() < 0.9) and 0.8 or 1)
            local tcsCoef = max(0.05, absegoSpeed - propSlip * propSlip) / absegoSpeed
            if tcsCoef > 0.95 then tcsCoef = 1.0 end -- avoid asymptote value
            throttleTcsCoef = legacyTcs:get(tcsCoef, dt)
        else
            brakeABSCoef = 0
            throttleTcsCoef = 0
        end
    end
    if tcsEnabled and input.throttle > 0 then
        electrics.values.throttleOverride = min(input.throttle, throttleTcsCoef)
        wroteThrottle = true
    elseif wroteThrottle then
        electrics.values.throttleOverride = nil
        wroteThrottle = false
    end
    if absEnabled and input.brake > 0 then
        electrics.values.brakeOverride = min(input.brake, brakeABSCoef)
        wroteBrake = true
    elseif wroteBrake then
        electrics.values.brakeOverride = nil
        wroteBrake = false
    end
end

M.onReset = clearOverrides
M.setEnabled = setEnabled
M.setMode = setMode
M.setParameters = setParameters
M.getParameters = getParameters
M.updateGFX = updateGFX

return M
