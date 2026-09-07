local M = {}

local absEnabled = false
local tcsEnabled = false

local function applyToVehicle(veh, absValue, tcsValue)
    if not veh or not veh.queueLuaCommand then return false end

    veh:queueLuaCommand(string.format(
        "extensions.load('universalAbsTcs'); universalAbsTcs.setEnabled(%s, %s)",
        absValue and "true" or "false", tcsValue and "true" or "false"))
    return true
end

local function onVehicleSwitched(oldId, newId, player)
    if player ~= 0 or newId == -1 or not scenetree or not scenetree.findObjectById then return end

    if (absEnabled or tcsEnabled) and oldId and oldId ~= -1 then
        applyToVehicle(scenetree.findObjectById(oldId), false, false)
    end

    if absEnabled or tcsEnabled then
        applyToVehicle(scenetree.findObjectById(newId), absEnabled, tcsEnabled)
    end
end

local function onExtensionLoaded()
    if not (absEnabled or tcsEnabled) then return end
    if not be or not be.getPlayerVehicle then return end

    applyToVehicle(be:getPlayerVehicle(0), absEnabled, tcsEnabled)
end

local function setEnabled(absOn, tcsOn)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    absEnabled = absOn == true
    tcsEnabled = tcsOn == true
    if not applyToVehicle(playerVeh, absEnabled, tcsEnabled) then return false end

    ui_message((absEnabled and tcsEnabled) and "Universal ABS / TCS enabled." or "Universal ABS / TCS disabled.", 5, "info")
    return true
end

local function setAbsEnabled(enable)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    absEnabled = enable == true
    return applyToVehicle(playerVeh, absEnabled, tcsEnabled)
end

local function setTcsEnabled(enable)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    tcsEnabled = enable == true
    return applyToVehicle(playerVeh, absEnabled, tcsEnabled)
end

local function getStatus()
    return {
        absEnabled = absEnabled,
        tcsEnabled = tcsEnabled,
    }
end

M.onExtensionLoaded = onExtensionLoaded
M.onVehicleSwitched = onVehicleSwitched
M.setEnabled = setEnabled
M.setAbsEnabled = setAbsEnabled
M.setTcsEnabled = setTcsEnabled
M.getStatus = getStatus

return M
