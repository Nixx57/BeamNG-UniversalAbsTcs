local M = {}

local absEnabled = false
local tcsEnabled = false
local mode = "performance"
local parameters = {
    lowSpeedReference = 5,
    tolerance = "default",
    anticipationTime = 0.05,
    aggressivity = 2.0,
}

local function applyToVehicle(veh, absValue, tcsValue)
    if not veh or not veh.queueLuaCommand then return false end

    veh:queueLuaCommand(string.format(
        "extensions.load('universalAbsTcs'); universalAbsTcs.setEnabled(%s, %s)",
        absValue and "true" or "false", tcsValue and "true" or "false"))
    return true
end

local function applyModeToVehicle(veh, modeValue)
    if not veh or not veh.queueLuaCommand then return false end

    veh:queueLuaCommand(string.format(
        "extensions.load('universalAbsTcs'); universalAbsTcs.setMode(%q)", modeValue))
    return true
end

local function applyParametersToVehicle(veh)
    if not veh or not veh.queueLuaCommand then return false end

    local toleranceValue = parameters.tolerance == "default"
        and "\"default\""
        or string.format("%g", parameters.tolerance)
    veh:queueLuaCommand(string.format(
        "extensions.load('universalAbsTcs'); universalAbsTcs.setParameters(%g, %s, %g, %g)",
        parameters.lowSpeedReference,
        toleranceValue,
        parameters.anticipationTime,
        parameters.aggressivity))
    return true
end

local function onVehicleSwitched(oldId, newId, player)
    if player ~= 0 or newId == -1 or not scenetree or not scenetree.findObjectById then return end

    if (absEnabled or tcsEnabled) and oldId and oldId ~= -1 then
        applyToVehicle(scenetree.findObjectById(oldId), false, false)
    end

    if absEnabled or tcsEnabled then
        local newVeh = scenetree.findObjectById(newId)
        applyToVehicle(newVeh, absEnabled, tcsEnabled)
        applyModeToVehicle(newVeh, mode)
        applyParametersToVehicle(newVeh)
    end
end

local function onExtensionLoaded()
    if not (absEnabled or tcsEnabled) then return end
    if not be or not be.getPlayerVehicle then return end

    local playerVeh = be:getPlayerVehicle(0)
    applyToVehicle(playerVeh, absEnabled, tcsEnabled)
    applyModeToVehicle(playerVeh, mode)
    applyParametersToVehicle(playerVeh)
end

local function setEnabled(absOn, tcsOn)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    absEnabled = absOn == true
    tcsEnabled = tcsOn == true
    if not applyToVehicle(playerVeh, absEnabled, tcsEnabled) then return false end
    if not applyParametersToVehicle(playerVeh) then return false end

    ui_message((absEnabled and tcsEnabled) and "Universal ABS / TCS enabled." or "Universal ABS / TCS disabled.", 5, "info")
    return true
end

local function setAbsEnabled(enable)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    absEnabled = enable == true
    if not applyToVehicle(playerVeh, absEnabled, tcsEnabled) then return false end
    return applyParametersToVehicle(playerVeh)
end

local function setTcsEnabled(enable)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    tcsEnabled = enable == true
    if not applyToVehicle(playerVeh, absEnabled, tcsEnabled) then return false end
    return applyParametersToVehicle(playerVeh)
end

local function getStatus()
    return {
        absEnabled = absEnabled,
        tcsEnabled = tcsEnabled,
        mode = mode,
    }
end

local function setMode(newMode)
    if newMode ~= "grip" and newMode ~= "performance" then return false end
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    mode = newMode
    return applyModeToVehicle(playerVeh, mode)
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
    if not be or not be.getPlayerVehicle then return false end

    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    parameters.lowSpeedReference = math.max(lowSpeedReferenceValue, 0)
    parameters.tolerance = toleranceValue
    parameters.anticipationTime = math.max(anticipationTimeValue, 0)
    parameters.aggressivity = math.max(aggressivityValue, 0)
    return applyParametersToVehicle(playerVeh)
end

local function getParameters()
    return {
        lowSpeedReference = parameters.lowSpeedReference,
        tolerance = parameters.tolerance,
        anticipationTime = parameters.anticipationTime,
        aggressivity = parameters.aggressivity,
    }
end

M.onExtensionLoaded = onExtensionLoaded
M.onVehicleSwitched = onVehicleSwitched
M.setEnabled = setEnabled
M.setAbsEnabled = setAbsEnabled
M.setTcsEnabled = setTcsEnabled
M.setMode = setMode
M.setParameters = setParameters
M.getParameters = getParameters
M.getStatus = getStatus

return M
