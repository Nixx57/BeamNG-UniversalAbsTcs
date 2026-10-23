local M = {}

local absEnabled = false
local tcsEnabled = false
local mode = "performance"
local parameters = {
    lowSpeedReference = 5,
    tolerance = "default",
    increaseMultiplier = 0.5,
    decreaseMultiplier = 1,
    forceGearboxAggression = false,
}

local function isNonNegativeFinite(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end

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
        "extensions.load('universalAbsTcs'); universalAbsTcs.setParameters(%g, %s, %g, %g, %s)",
        parameters.lowSpeedReference,
        toleranceValue,
        parameters.increaseMultiplier,
        parameters.decreaseMultiplier,
        parameters.forceGearboxAggression and "true" or "false"))
    return true
end

local function applyConfigurationToVehicle(veh)
    return applyToVehicle(veh, absEnabled, tcsEnabled)
        and applyModeToVehicle(veh, mode)
        and applyParametersToVehicle(veh)
end

local function onVehicleSwitched(oldId, newId, player)
    if player ~= 0 or newId == -1 or not scenetree or not scenetree.findObjectById then return end

    if (absEnabled or tcsEnabled or parameters.forceGearboxAggression) and oldId and oldId ~= -1 then
        local oldVeh = scenetree.findObjectById(oldId)
        if applyToVehicle(oldVeh, false, false) then
            oldVeh:queueLuaCommand(
                "universalAbsTcs.setForceGearboxAggression(false)")
        end
    end

    if absEnabled or tcsEnabled or parameters.forceGearboxAggression then
        applyConfigurationToVehicle(scenetree.findObjectById(newId))
    end
end

local function setEnabled(absOn, tcsOn)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    absEnabled = absOn == true
    tcsEnabled = tcsOn == true
    return applyConfigurationToVehicle(playerVeh)
end

local function setAbsEnabled(enable)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end
    absEnabled = enable == true
    return applyConfigurationToVehicle(playerVeh)
end

local function setTcsEnabled(enable)
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end
    tcsEnabled = enable == true
    return applyConfigurationToVehicle(playerVeh)
end

local function getStatus()
    return {
        absEnabled = absEnabled,
        tcsEnabled = tcsEnabled,
        mode = mode,
    }
end

local function setMode(newMode)
    if newMode ~= "grip" and newMode ~= "performance" and newMode ~= "legacy" then return false end
    if not be or not be.getPlayerVehicle then return false end
    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    mode = newMode
    return applyModeToVehicle(playerVeh, mode)
end

local function setParameters(lowSpeedReferenceValue, toleranceValue, increaseMultiplierValue, decreaseMultiplierValue, forceGearboxAggressionValue)
    if not isNonNegativeFinite(lowSpeedReferenceValue) then
        return false
    end
    if toleranceValue ~= "default" and not isNonNegativeFinite(toleranceValue) then
        return false
    end
    if increaseMultiplierValue ~= nil and
        (not isNonNegativeFinite(increaseMultiplierValue) or increaseMultiplierValue == 0) then
        return false
    end
    if decreaseMultiplierValue ~= nil and not isNonNegativeFinite(decreaseMultiplierValue) then
        return false
    end
    if forceGearboxAggressionValue ~= nil and type(forceGearboxAggressionValue) ~= "boolean" then
        return false
    end
    if not be or not be.getPlayerVehicle then return false end

    local playerVeh = be:getPlayerVehicle(0)
    if not playerVeh then return false end

    parameters.lowSpeedReference = lowSpeedReferenceValue
    parameters.tolerance = toleranceValue
    if increaseMultiplierValue ~= nil then
        parameters.increaseMultiplier = increaseMultiplierValue
    end
    if decreaseMultiplierValue ~= nil then
        parameters.decreaseMultiplier = decreaseMultiplierValue
    end
    if forceGearboxAggressionValue ~= nil then
        parameters.forceGearboxAggression = forceGearboxAggressionValue
    end
    return applyParametersToVehicle(playerVeh)
end

local function getParameters()
    return {
        lowSpeedReference = parameters.lowSpeedReference,
        tolerance = parameters.tolerance,
        increaseMultiplier = parameters.increaseMultiplier,
        decreaseMultiplier = parameters.decreaseMultiplier,
        forceGearboxAggression = parameters.forceGearboxAggression,
    }
end

local function applyToPlayerVehicle()
    if not be or not be.getPlayerVehicle then return false end
    return applyConfigurationToVehicle(be:getPlayerVehicle(0))
end

M.onVehicleSwitched = onVehicleSwitched
M.applyToPlayerVehicle = applyToPlayerVehicle
M.setEnabled = setEnabled
M.setAbsEnabled = setAbsEnabled
M.setTcsEnabled = setTcsEnabled
M.setMode = setMode
M.setParameters = setParameters
M.getParameters = getParameters
M.getStatus = getStatus

return M
