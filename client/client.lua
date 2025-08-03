-- File: client.lua
-- Description: Client-side logic for SimpleCarlock.

-- ========== LOCAL STATE ==========
local playerKeys = {} -- Stores plates of vehicles the player has keys for.
local isLockpicking = false
local vehicleBeingPicked = nil
local nuiReady = false
local canAutolock = true -- Flag to temporarily disable autolocking.
local helpMenuOpen = false
local shownHelpForVehicle = {} -- Tracks if help message has been shown for a vehicle.

-- ========== LOCAL FUNCTIONS ==========
function ShowNotification(msg)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(msg)
    DrawNotification(false, true)
end

-- Finds the closest vehicle to a given position.
function GetClosestVehicle(pos)
    local closestVeh, closestDist = nil, -1
    local handle, veh = FindFirstVehicle()
    local success
    repeat
        if DoesEntityExist(veh) then
            local vehPos = GetEntityCoords(veh)
            local dist = #(pos - vehPos)
            if closestDist == -1 or dist < closestDist then
                closestVeh, closestDist = veh, dist
            end
        end
        success, veh = FindNextVehicle(handle)
    until not success
    EndFindVehicle(handle)
    return closestVeh, closestDist
end

-- ========== NUI CALLBACKS ==========
RegisterNuiCallback('nuiReady', function(data, cb) nuiReady = true; cb('ok'); end)

RegisterNuiCallback('minigameResult', function(data, cb)
    SetNuiFocus(false, false)
    isLockpicking = false
    ClearPedTasks(PlayerPedId())
    
    if data.success then
        ShowNotification("~g~Lock successfully picked!")
        if DoesEntityExist(vehicleBeingPicked) then
            SetVehicleDoorsLocked(vehicleBeingPicked, 1) -- 1 = Unlocked but not forced open
            ShowNotification("~g~The door is now unlocked.")
        end
    else
        ShowNotification("~r~You broke your pick! Lockpicking failed.")
    end
    vehicleBeingPicked = nil
    cb('ok')
end)

RegisterNuiCallback('closeHelpMenu', function(data, cb)
    helpMenuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

-- ========== NET EVENTS ==========
RegisterNetEvent('carLock:setVehicleKey'); AddEventHandler('carLock:setVehicleKey', function(plate) if plate then playerKeys[plate] = true; end; end)
RegisterNetEvent('carLock:removeVehicleKey'); AddEventHandler('carLock:removeVehicleKey', function(plate) if plate then playerKeys[plate] = nil; end; end)
RegisterNetEvent('carLock:showNotification'); AddEventHandler('carLock:showNotification', function(msg) ShowNotification(msg); end)

RegisterNetEvent('carLock:updateLockStatus')
AddEventHandler('carLock:updateLockStatus', function(netId, locked)
    local veh = NetToVeh(netId)
    if DoesEntityExist(veh) then
        SetVehicleDoorsLocked(veh, locked and 2 or 1) -- 2 = Locked, 1 = Unlocked
        if nuiReady then
            local soundName = locked and "lock" or "unlock"
            SendNuiMessage(json.encode({action = 'playSound', sound = soundName, volume = Config.Settings.soundVolume}))
        end
        -- Animate vehicle lights to give feedback.
        SetVehicleLights(veh, 2); Wait(150); SetVehicleLights(veh, 0); Wait(150); SetVehicleLights(veh, 2); Wait(150); SetVehicleLights(veh, 0)
    end
end)

RegisterNetEvent('carLock:startLockpickMinigame')
AddEventHandler('carLock:startLockpickMinigame', function(netId)
    isLockpicking = true
    vehicleBeingPicked = NetToVeh(netId)
    local ply = PlayerPedId()

    ShowNotification("~b~You begin to pick the lock...")
    local anim = "mini@repair"
    RequestAnimDict(anim)
    while not HasAnimDictLoaded(anim) do Wait(100) end
    
    TaskPlayAnim(ply, anim, "fixing_a_ped", 8.0, -8.0, -1, 49, 0, false, false, false)

    -- Wait before showing the minigame NUI.
    CreateThread(function()
        Wait(Config.Settings.lockpickInitialWait)
        if not isLockpicking or not DoesEntityExist(vehicleBeingPicked) then 
            isLockpicking = false
            ClearPedTasks(PlayerPedId())
            return
        end
        SetNuiFocus(true, true)
        SendNuiMessage(json.encode({action = 'startMinigame', pins = Config.Settings.pinCount, attempts = Config.Settings.pinAttempts}))
    end)
end)

-- ========== COMMANDS ==========
RegisterCommand('lockpick', function()
    if isLockpicking then return end
    if not nuiReady then ShowNotification("~y~Lockpick kit is not ready yet."); return; end
    
    local ply = PlayerPedId()
    if IsPedInAnyVehicle(ply, false) then
        ShowNotification("~r~You cannot do this from inside a vehicle.")
        return
    end

    local closestVeh, closestDist = GetClosestVehicle(GetEntityCoords(ply))
    if closestVeh and closestDist <= Config.Settings.lockpickDistance then
        TriggerServerEvent('carLock:requestLockpick', VehToNet(closestVeh))
    else
        ShowNotification("~y~No vehicle close enough to lockpick.")
    end
end, false)

RegisterCommand('carhelp', function()
    helpMenuOpen = not helpMenuOpen
    SetNuiFocus(helpMenuOpen, helpMenuOpen)
    SendNuiMessage(json.encode({ action = 'toggleHelpMenu' }))
end, false)


-- ========== CORE THREADS ==========

-- This thread handles player input for locking/unlocking.
-- It runs every frame (Wait(0)) to ensure inputs are captured instantly.
CreateThread(function()
    while true do
        Wait(0) -- Run every game tick for responsiveness.
        if isLockpicking then goto continue end

        local ply = PlayerPedId()
        
        -- Manual lock/unlock while on foot.
        if not IsPedInAnyVehicle(ply, false) and IsControlJustReleased(0, Config.Settings.lockKey) then
            local veh, dist = GetClosestVehicle(GetEntityCoords(ply))
            if veh and dist <= Config.Settings.interactionDistance then
                local plate = GetVehicleNumberPlateText(veh)
                if plate and playerKeys[plate] then
                    TriggerServerEvent('carLock:toggleLock', VehToNet(veh))
                end
            end
        end
        
        -- Auto-unlock just before exiting vehicle.
        if IsPedInAnyVehicle(ply, false) and IsControlJustPressed(0, Config.Settings.exitKey) then
            local veh = GetVehiclePedIsIn(ply, false)
            local plate = GetVehicleNumberPlateText(veh)
            -- If player has keys and car is locked, unlock it to allow exit.
            if plate and playerKeys[plate] and GetVehicleDoorLockStatus(veh) ~= 1 then
                TriggerServerEvent('carLock:toggleLock', VehToNet(veh))
                TriggerEvent('carLock:pauseAutolock')
            end
        end
        ::continue::
    end
end)

-- This thread handles automatic features like drive-lock and walk-away lock.
-- It runs on a 500ms interval as it doesn't need to be instant.
CreateThread(function()
    local lastUsedVehicle = 0
    while true do
        Wait(500)
        if isLockpicking then goto continue end

        local ply = PlayerPedId()
        local currentVehicle = GetVehiclePedIsIn(ply, false)

        if currentVehicle ~= 0 then -- Player is in a vehicle
            lastUsedVehicle = currentVehicle
            if not canAutolock then canAutolock = true end
            
            local plate = GetVehicleNumberPlateText(currentVehicle)
            if plate and not shownHelpForVehicle[plate] then
                -- Show help message once per vehicle.
                TriggerEvent('chat:addMessage', {
                    color = { 30, 144, 255 },
                    args = { "[SimpleCarlock]", "Type /carhelp to see commands and features." }
                })
                shownHelpForVehicle[plate] = true
            end

            -- Auto-lock when driving.
            if GetPedInVehicleSeat(currentVehicle, -1) == ply then -- Player is the driver
                if playerKeys[plate] and GetVehicleDoorLockStatus(currentVehicle) == 1 and GetEntitySpeed(currentVehicle) * 2.236936 > Config.Settings.driveLockSpeed then
                    TriggerServerEvent('carLock:toggleLock', VehToNet(currentVehicle))
                end
            end
        else -- Player is on foot
            if canAutolock and DoesEntityExist(lastUsedVehicle) then 
                local dist = #(GetEntityCoords(ply) - GetEntityCoords(lastUsedVehicle))
                if dist > Config.Settings.autolockDistance then
                    local plate = GetVehicleNumberPlateText(lastUsedVehicle)
                    if plate and playerKeys[plate] and GetVehicleDoorLockStatus(lastUsedVehicle) == 1 then
                        TriggerServerEvent('carLock:toggleLock', VehToNet(lastUsedVehicle), true) -- isAutolock = true
                        lastUsedVehicle = 0 -- Reset to prevent re-locking.
                    end
                end
            end
        end
        ::continue::
    end
end)

-- Temporarily disables autolocking to prevent the car from locking right after you exit.
AddEventHandler('carLock:pauseAutolock', function()
    canAutolock = false
    SetTimeout(3000, function()
        canAutolock = true
    end)
end)