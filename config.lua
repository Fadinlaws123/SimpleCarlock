Config = {}

Config.Settings = {

    ExemptEmergencyVehicles = true, -- Make emergency vehicles exempt from being lockpicked.
    lockKey = 38, -- Keybind to lock your vehicle (Default = 38 (E))
    exitKey = 75, -- Keybind to exit your vehicle (Default = 75 (F))
    autolockDistance = 25.0, -- How far do you need to be from your vehicle until it auto locks.
    interactionDistance = 7.0, -- How far you can go from the vehicle and be able to lock / unlock.
    soundVolume = 0.4, -- How loud the lock / unlock sound is. 
    lockpickInitialWait = 2500, -- Time in ms before showing the lockpick menu. 
    lockpickDistance = 4.0, -- Distance between you and the vehicle to be able to lockpick. 
    pinCount = 5, -- How many pins you have for lockpicking. 
    pinAttempts = 3, -- How many fails you can lockpicking. 
    driveLockSpeed = 5.0, -- How fast your vehicle needs to go before auto-locking.
}

Config.VersionChecker = {
    Enabled = true, -- Set to true to enable version checking on server start.

    -- Do not touch these lines
    CurrentVersion = '1.0', -- Current script version.
    VersionFileUrl = 'https://raw.githubusercontent.com/Fadinlaws123/ScriptVersionChecker/refs/heads/main/SimpleCarlock.json'
}
