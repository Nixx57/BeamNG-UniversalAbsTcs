-- Universal ABS/TCS: virtual driving aid
-- Limits the player's brake/throttle inputs to avoid wheel lock (braking) and wheel spin (acceleration)
-- Works on any vehicle, regardless of its native ABS/TCS/ESC configuration
-- Algorithm and tuning copied from the native AI (lua/vehicle/ai.lua, ~l.525)
local M = {}

local min, max, abs = math.min, math.max, math.abs

local absEnabled = false
local tcsEnabled = false
local smoothTcs = newTemporalSmoothingNonLinear(0.4, 0.9, 1) -- native AI tuning

local function setEnabled(absOn, tcsOn)
    absEnabled = absOn == true
    tcsEnabled = tcsOn == true
    if not absEnabled then
        electrics.values.brakeOverride = nil
    end
    if not tcsEnabled then
        electrics.values.throttleOverride = nil
    end
    smoothTcs:set(1)
end

local function updateGFX(dt)
    if not (absEnabled or tcsEnabled) then
        return
    end

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
            throttleTcsCoef = smoothTcs:get(tcsCoef, dt)
        else
            brakeABSCoef = 0
            throttleTcsCoef = 0
        end
    end
    if tcsEnabled then
        electrics.values.throttleOverride = min(input.throttle, throttleTcsCoef)
    end
    if absEnabled then
        electrics.values.brakeOverride = min(input.brake, brakeABSCoef)
    end
end

M.setEnabled = setEnabled
M.updateGFX = updateGFX

return M
