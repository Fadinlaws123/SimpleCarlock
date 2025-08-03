-- File: server.lua
-- Description: Server-side logic for SimpleCarlock.

-- vehicleStates: Stores the state (locked, owner) for each vehicle, keyed by license plate.
local vehicleStates = {}
-- playerVehicles: Tracks vehicles owned by each player for efficient cleanup on disconnect. Keyed by player source ID.
local playerVehicles = {}

-- Sends a notification to a specific client.
local function notify(player, msg)
    TriggerClientEvent('carLock:showNotification', player, msg)
end

-- Toggles the lock state of a vehicle.
RegisterNetEvent('carLock:toggleLock')
AddEventHandler('carLock:toggleLock', function(netId, isAutolock)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(vehicle) then return end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate or plate:gsub("%s*", "") == "" then return end

    -- Check if the vehicle is in the system and if the player is the owner.
    if vehicleStates[plate] and vehicleStates[plate].owner == source then
        local currentState = vehicleStates[plate].locked
        vehicleStates[plate].locked = not currentState

        -- Notify all clients about the new lock status to sync animations/sounds.
        TriggerClientEvent('carLock:updateLockStatus', -1, netId, not currentState)
        
        local action = not currentState and "~r~locked" or "~g~unlocked"
        local message = isAutolock and "Your vehicle has been auto-" .. action .. "." or "You have " .. action .. " your vehicle."
        notify(source, message)
    end
end)

-- Command to get keys for the current vehicle.
RegisterCommand('getkeys', function(source, args, rawCommand)
    local playerPed = GetPlayerPed(source)
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if vehicle == 0 then
        notify(source, "~r~You must be in a vehicle.")
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate or plate:gsub("%s*", "") == "" then
        notify(source, "~r~This vehicle has no license plate.")
        return
    end

    if vehicleStates[plate] then
        if vehicleStates[plate].owner == source then
            notify(source, "~y~You already have the keys for this vehicle.")
        else
            notify(source, "~r~This vehicle is already owned by someone else.")
        end
    else
        -- Assign new ownership.
        vehicleStates[plate] = { locked = false, owner = source }
        
        -- Add vehicle to the player's owned list for fast lookups.
        playerVehicles[source] = playerVehicles[source] or {}
        table.insert(playerVehicles[source], plate)
        
        TriggerClientEvent('carLock:setVehicleKey', source, plate)
        notify(source, "~g~You have received the keys for this vehicle.")
    end
end, false)

-- Command to give keys to another player.
RegisterCommand('givekeys', function(source, args, rawCommand)
    local targetId = tonumber(args[1])
    if not targetId or not GetPlayerName(targetId) then
        notify(source, "~r~Player not found. Usage: /givekeys <Player ID>")
        return
    end
    if targetId == source then
        notify(source, "~r~You cannot give keys to yourself.")
        return
    end

    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
    if vehicle == 0 then
        notify(source, "~r~You must be in the vehicle to give its keys.")
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not vehicleStates[plate] or vehicleStates[plate].owner ~= source then
        notify(source, "~r~You do not own the keys for this vehicle.")
        return
    end

    -- Transfer ownership.
    vehicleStates[plate].owner = targetId

    -- Remove vehicle from the old owner's list.
    if playerVehicles[source] then
        for i, p in ipairs(playerVehicles[source]) do
            if p == plate then
                table.remove(playerVehicles[source], i)
                break
            end
        end
    end
    
    -- Add vehicle to the new owner's list.
    playerVehicles[targetId] = playerVehicles[targetId] or {}
    table.insert(playerVehicles[targetId], plate)

    -- Update clients.
    TriggerClientEvent('carLock:removeVehicleKey', source, plate)
    TriggerClientEvent('carLock:setVehicleKey', targetId, plate)
    notify(source, "~g~You gave your vehicle keys to " .. GetPlayerName(targetId) .. ".")
    notify(targetId, "~g~You received vehicle keys from " .. GetPlayerName(source) .. ".")
end, false)

-- Event to handle a lockpick request from a client.
RegisterNetEvent('carLock:requestLockpick')
AddEventHandler('carLock:requestLockpick', function(netId)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(vehicle) then return end
    if GetVehicleDoorLockStatus(vehicle) == 1 then
        notify(source, "~y~The vehicle is already unlocked.")
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if vehicleStates[plate] and vehicleStates[plate].owner == source then
        notify(source, "~y~You have the keys for this vehicle.")
        return
    end

    -- Check for emergency vehicle exemption.
    if Config.Settings.ExemptEmergencyVehicles then
        local model = GetEntityModel(vehicle)
        local emergencyModels = {
            GetHashKey("police"), GetHashKey("police2"), GetHashKey("police3"),
            GetHashKey("ambulance"), GetHashKey("firetruk")
        }
        for _, hash in ipairs(emergencyModels) do
            if model == hash then
                notify(source, "~r~This vehicle cannot be lockpicked.")
                return
            end
        end
    end

    TriggerClientEvent('carLock:startLockpickMinigame', source, netId)
end)

-- Clean up a player's vehicles when they disconnect.
-- This is much faster than iterating through the entire vehicleStates table.
AddEventHandler('playerDropped', function(reason)
    local source = source
    if playerVehicles[source] then
        for _, plate in ipairs(playerVehicles[source]) do
            vehicleStates[plate] = nil
        end
        playerVehicles[source] = nil -- Clear the player's vehicle list from memory.
    end
end)


-- ----- VERSION CHECKER (No changes, runs on start-up) ----- 
if not Config.VersionChecker or not Config.VersionChecker.Enabled then
    return
end

Citizen.CreateThread(function()
    Citizen.Wait(2000) 


    local function compareVersions(v1, v2)
        local parts1 = {}
        for part in string.gmatch(v1, "[^%.]+") do table.insert(parts1, tonumber(part)) end
        local parts2 = {}
        for part in string.gmatch(v2, "[^%.]+") do table.insert(parts2, tonumber(part)) end
        for i = 1, math.max(#parts1, #parts2) do
            local p1 = parts1[i] or 0
            local p2 = parts2[i] or 0
            if p1 > p2 then return 1 end
            if p1 < p2 then return -1 end
        end
        return 0
    end

    local boxWidth = 86
    local function printTop() print('^5╔' .. ('═'):rep(boxWidth - 2) .. '╗^7') end
    local function printBottom() print('^5╚' .. ('═'):rep(boxWidth - 2) .. '╝^7') end
    local function printEmpty() print('^5║' .. (' '):rep(boxWidth - 2) .. '║^7') end

    local function printDivider(text)
        local stripped = text:gsub('%^%d', '')
        local paddingTotal = boxWidth - 2 - #stripped - 4 
        local paddingLeft = math.floor(paddingTotal / 2)
        local paddingRight = paddingTotal - paddingLeft
        print('^5╠' .. ('═'):rep(paddingLeft) .. '[ ^6' .. text .. ' ^5]' .. ('═'):rep(paddingRight) .. '╣^7')
    end

    local function printCenter(text)
        local stripped = text:gsub('%^%d', '')
        local paddingTotal = boxWidth - 2 - #stripped
        local paddingLeft = math.floor(paddingTotal / 2)
        local paddingRight = paddingTotal - paddingLeft
        print('^5║' .. (' '):rep(paddingLeft) .. text .. (' '):rep(paddingRight) .. '║^7')
    end

    local function printLeft(text)
        local stripped = text:gsub('%^%d', '')
        local paddingRight = boxWidth - 2 - #stripped - 7
        if paddingRight < 0 then paddingRight = 0 end
        print('^5║      ' .. text .. (' '):rep(paddingRight) .. '║^7')
    end
    
    local function printVersionLine(current, latest, comparison)
        local currentText = "Your Version:   ^7[^2" .. current .. "^7]^5"
        
        local latestColor = (comparison < 0 and '^1' or '^2')
        local latestText = "^3Latest Version:   ^7[" .. latestColor .. latest .. "^7]^5"

        local strippedLeft = currentText:gsub('%^%d', '')
        local strippedRight = latestText:gsub('%^%d', '')

        local padding = boxWidth - 2 - #strippedLeft - #strippedRight - 6 
        if padding < 0 then padding = 0 end

        print('^5║   ' .. currentText .. (' '):rep(padding) .. latestText .. '   ║^7')
    end


    PerformHttpRequest(Config.VersionChecker.VersionFileUrl, function(errorCode, resultData, resultHeaders)
        local scriptNameArt = {
            " ____  _                 _       ____           _            _    ",
            "/ ___|(_)_ __ ___  _ __ | | ___ / ___|__ _ _ __| | ___   ___| | __",
            "\\___ \\| | '_ ` _ \\| '_ \\| |/ _ \\ |   / _` | '__| |/ _ \\ / __| |/ /",
            " ___) | | | | | | | |_) | |  __/ |__| (_| | |  | | (_) | (__|   < ",
            "|____/|_|_| |_| |_| .__/|_|\\___|\\____\\__,_|_|  |_|\\___/ \\___|_|\\_\\",
            "                  |_|                                             "
        }

        local function printErrorBox(title, ...)
            printTop()
            printEmpty()
            printCenter('^1'..title)
            printEmpty()
            printDivider('Error Details')
            printEmpty()
            for _, line in ipairs({...}) do
                printCenter(line)
            end
            printEmpty()
            printBottom()
        end

        if errorCode ~= 200 then
            printErrorBox('VERSION CHECK FAILED', '^1Could not connect to GitHub to check for updates.', '^1HTTP Error Code: ' .. errorCode .. '^7')
            return
        end
        
        local success, data = pcall(json.decode, resultData)
        if not success or not data then
            printErrorBox('VERSION CHECK FAILED', '^1Could not parse version information from the JSON file.^7')
            return
        end

        local currentVersion = Config.VersionChecker.CurrentVersion
        local latestVersion = data.latest_version
        local comparison = compareVersions(currentVersion, latestVersion)

        printTop()
        printEmpty()
        for _, line in ipairs(scriptNameArt) do printCenter('^2' .. line .. '^5') end
        printEmpty()
        printDivider('Version Status')
        printEmpty()

        printVersionLine(currentVersion, latestVersion, comparison)

        printEmpty()
        printDivider('Script Health')
        printEmpty()

        if comparison < 0 then
            printCenter('^3A NEW UPDATE IS AVAILABLE!^5')
            printCenter('^7Download at:^5 ' .. (data.download_url or 'Not specified'))
            
            if data.changelog and #data.changelog > 0 then
                printEmpty()
                printDivider('Latest Changes')
                printEmpty()
                local entry = data.changelog[1]
                printCenter('^6v' .. entry.version .. '^7 (^5' .. (entry.date or 'N/A') .. '^7)^5')
                printEmpty()
                for _, change in ipairs(entry.changes) do
                    printCenter('^7- ' .. change .. '^5')
                end
            end

        elseif comparison == 0 then
            printCenter('^2YOUR SCRIPT IS UP-TO-DATE!^5')
        else
            printCenter('^3You are running a pre-release or development version.^5')
        end
        
        printEmpty()
        printDivider('Community & Support')
        printEmpty()
        printCenter('^7Join our Discord:^5 https://discord.gg/UwcwpquY9K')
        printCenter('^7Find more scripts at:^5 http://simpledevelopments.org/')
        printCenter('^7Find our script docs at:^5 http://docs.simpledevelopments.org/')
        printEmpty()
        printBottom()
    end)
end)