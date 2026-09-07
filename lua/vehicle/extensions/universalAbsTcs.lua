-- Universal ABS/TCS: virtual driving aid
-- Limits the player's brake/throttle inputs to avoid wheel lock (braking) and wheel spin (acceleration)
-- Works on any vehicle, regardless of its native ABS/TCS/ESC configuration
-- Algorithm and tuning copied from the native AI (lua/vehicle/ai.lua, ~l.525)

local M = {}

local min, max, abs = math.min, math.max, math.abs

local absEnabled = false
local tcsEnabled = false
local wroteBrake = false
local wroteThrottle = false
-- local smoothTcs = newTemporalSmoothingNonLinear(0.4, 0.9, 1) -- native AI tuning
local smoothTcs = newTemporalSmoothing(2, 2, nil, 1) -- better -> non-asymptotic

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
  smoothTcs:set(1)
end

local function updateGFX(dt)
  if not (absEnabled or tcsEnabled) then return end

  -- longitudinal vehicle speed, same source as ai.lua (refactored)
  local vx, vy, vz = obj:getSmoothRefVelocityXYZ()
  local dx, dy, dz = obj:getDirectionVectorXYZ()
  local speed = max(abs(vx * dx + vy * dy + vz * dz), 3)

  -- if loose ground -> reduce grip and adjust TCS behavior
  local looseGround = obj:getStaticFrictionCoef() < 0.9

  -- wheel scan
  local totalSlip = 0
  local totalPeakSlip = 0
  local propSlip = 0
  local totalDownForce = 0
  local lwheels = wheels.wheels
  for i = 0, tableSizeC(lwheels) - 1 do
    local wd = lwheels[i]
    if not wd.isBroken then
      local lastSlip = wd.lastSlip
      local downForce = wd.downForceRaw
      totalSlip = totalSlip + lastSlip * downForce
      -- ride the tire's own peak-grip slip point instead of clamping to zero slip
      totalPeakSlip = totalPeakSlip + (wd.slipRatioTarget or 0.18) * speed * downForce
      totalDownForce = totalDownForce + downForce
      if wd.isPropulsed then
        -- propSlip = max(propSlip, wd.lastSlip)
        local peakSlip = (wd.slipRatioTarget or 0.18) * speed
        propSlip = max(propSlip, lastSlip - peakSlip)
      end
    end
  end
  totalSlip = totalSlip / (totalDownForce + 1e-25)
  -- totalPeakSlip weighted the same way as totalSlip so they can be compared directly
  totalPeakSlip = totalPeakSlip / (totalDownForce + 1e-25)

  if speed <= 0.05 then
    if wroteBrake then
      electrics.values.brakeOverride = nil
      wroteBrake = false
    end
    if wroteThrottle then
      electrics.values.throttleOverride = nil
      wroteThrottle = false
    end
    return
  end

  -- ABS
  if absEnabled and input.brake > 0 then
    -- local brakeCoef = min(1, 1.5 * square(square(square(max(0, speed - totalSlip) / speed))))
    local slipExcess = max(0, totalSlip - totalPeakSlip)
    local brakeCoef = min(1, 1.5 * square(square(square(max(0, speed - slipExcess) / speed))))
    electrics.values.brakeOverride = input.brake * smoothTcs:get(brakeCoef, dt)
    wroteBrake = true
  elseif wroteBrake then
    electrics.values.brakeOverride = nil
    wroteBrake = false
  end

  -- TCS
  if tcsEnabled and input.throttle > 0 then
    -- propSlip = propSlip * (looseGround and 0.8 or 1)
    -- local tcsCoef = max(0.05, speed - propSlip * propSlip) / speed
    local slipExcess = propSlip * (looseGround and 0.8 or 1)
    local tcsCoef = max(0.05, speed - slipExcess * slipExcess) / speed
    electrics.values.throttleOverride = input.throttle * smoothTcs:get(tcsCoef, dt)
    -- electrics.values.throttleOverride = input.throttle * tcsCoef
    wroteThrottle = true
  elseif wroteThrottle then
    electrics.values.throttleOverride = nil
    wroteThrottle = false
  end
end

M.setEnabled = setEnabled
M.updateGFX = updateGFX

return M
