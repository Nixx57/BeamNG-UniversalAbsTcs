-- Smart Throttle & Brake Assistant: virtual driving aid
-- Limits the player's brake/throttle inputs to avoid wheel lock (braking) and wheel spin (acceleration)
-- Works on any vehicle, regardless of its native ABS/TCS/ESC configuration
-- Global reference-slip controller: one pedal command, load-weighted wheel feedback.

local M = {}

local min, max, abs = math.min, math.max, math.abs
local mode = "legacy" -- "performance" (load-weighted average), "grip" (worst wheel), or "legacy" (native AI controller)
local lowSpeedReference = 5
local tolerance = "default"

local function isNonNegativeFinite(value)
  return type(value) == "number" and value >= 0 and value < math.huge
end

-- Per-wheel integrator states: the coefficient creeps up while the wheel stays
-- below its target slip and creeps down as soon as it exceeds it.
local brakeCoefState = {}
local propCoefState = {}

local function resetCoefStates()
  for k in pairs(brakeCoefState) do brakeCoefState[k] = nil end
  for k in pairs(propCoefState) do propCoefState[k] = nil end
end

local function stepSlipCoef(state, index, slipRatio, targetSlipRatio, dt)
  targetSlipRatio = targetSlipRatio * ((tolerance == "default" and (obj:getStaticFrictionCoef() < 0.9 and 120 or 100) or tolerance) / 100)
  local coef = state[index] or 1
  
  if targetSlipRatio <= 0 then
    coef = slipRatio <= 0 and 1 or 0
  else
    local error = targetSlipRatio - slipRatio
    local step = --[[ 0.01 *]] dt * (1 + abs(error) / targetSlipRatio)
    if slipRatio < targetSlipRatio * 0.5 then
      coef = min(1, coef + step)
    elseif slipRatio > targetSlipRatio then
      coef = max(0, coef - step)
    end
  end

  state[index] = coef
  return coef
end

local absEnabled = false
local tcsEnabled = false
local wroteBrake = false
local wroteThrottle = false
local legacyTcs = newTemporalSmoothingHybrid(0.4, 0.9, 1, 0.01) -- native AI tuning + minimum rate
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
  legacyTcs:set(1)
  resetCoefStates()
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
  legacyTcs:set(1)
  resetCoefStates()
end

local function setMode(newMode)
  if newMode == "grip" or newMode == "performance" or newMode == "legacy" then
    mode = newMode
    clearOverrides()
    return true
  end
  return false
end

local function setParameters(lowSpeedReferenceValue, toleranceValue)
  if not isNonNegativeFinite(lowSpeedReferenceValue) then
    return false
  end
  if toleranceValue ~= "default" and not isNonNegativeFinite(toleranceValue) then
    return false
  end
  lowSpeedReference = lowSpeedReferenceValue
  tolerance = toleranceValue
  return true
end

local function getParameters()
  return {
    lowSpeedReference = lowSpeedReference,
    tolerance = tolerance,
  }
end

local function updateGFX(dt)
  if not (absEnabled or tcsEnabled) then return end

  if mode == "legacy" then
    legacy(dt)
    return
  end

  -- longitudinal vehicle speed, same source as ai.lua (refactored)
  local vx, vy, vz = obj:getSmoothRefVelocityXYZ()
  local dx, dy, dz = obj:getDirectionVectorXYZ()
  local speed = abs(vx * dx + vy * dy + vz * dz)
  local slipReferenceSpeed = max(speed, lowSpeedReference, 1e-6)

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
      local downForce = max(wd.downForce or 0, 0)
      local wheelSpeed = wd.wheelSpeed or 0
      local peakSlipRatio = min(max(wd.slipRatioTarget or 0.18, 0), 1)
      local wheelSpeedMagnitude = abs(wheelSpeed)
      local brakeSlipRatio = max(0, (speed - wheelSpeedMagnitude) / slipReferenceSpeed)
      local driveSlipRatio = max(0, (wheelSpeedMagnitude - speed) / slipReferenceSpeed)
      local driveTargetSlipRatio = min(peakSlipRatio, 1)
      local brakeCoef = stepSlipCoef(brakeCoefState, i, brakeSlipRatio, peakSlipRatio, dt)
      local propCoef = stepSlipCoef(propCoefState, i, driveSlipRatio, driveTargetSlipRatio, dt)

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
    electrics.values.brakeOverride = min(input.brake, brakeModelCoef)
    wroteBrake = true
  elseif wroteBrake then
    electrics.values.brakeOverride = nil
    wroteBrake = false
  end

  -- TCS
  if tcsEnabled and input.throttle > 0 then
    electrics.values.throttleOverride = min(input.throttle, propModelCoef)
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
