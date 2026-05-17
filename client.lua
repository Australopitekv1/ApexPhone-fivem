-- ============================================================
--  ApexPhone — client.lua
--  All client-side logic: phone open/close, NUI bridge,
--  voice integration, battery, GPS, signal zones, animations.
-- ============================================================

local QBCore   = exports['qb-core']:GetCoreObject()
local phoneOpen   = false
local phoneData   = {}          -- cached phone state
local activeCall  = nil         -- { number, source, speaker, startTime }
local callTimer   = nil         -- Citizen thread for call duration
local batteryTick = nil         -- Citizen thread for battery drain
local gpsThread   = nil         -- Citizen thread for live GPS shares
local currentSignal = Config.DefaultSignal
local airplaneMode  = false
local isCharging    = false
local pingCheckThread = nil

-- ──────────────────────────────────────────────────────────────
--  Utility helpers
-- ──────────────────────────────────────────────────────────────

--- Returns the player's current coordinates.
local function GetCoords()
    local ped = PlayerPedId()
    return GetEntityCoords(ped)
end

--- Sends a message to the NUI frame.
local function SendNUI(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end

--- Shows a brief NUI toast notification.
local function Notify(msg, ntype)
    SendNUI('notify', { message = msg, type = ntype or 'info' })
end

--- Checks if the player currently owns a phone item and returns its metadata.
local function GetPhoneItem()
    for _, model in pairs({ Config.Items.PhoneFlagship, Config.Items.PhoneSamsung, Config.Items.PhoneBurner }) do
        local item = exports['qb-inventory']:GetItemByName(model)
        if item then return item, model end
    end
    return nil, nil
end

--- Returns the signal level at the current player location.
local function CalculateSignal()
    if airplaneMode then return 0 end
    local coords = GetCoords()
    for _, zone in ipairs(Config.SignalZones) do
        if #(coords - zone.coords) < zone.radius then
            return zone.signal
        end
    end
    return Config.DefaultSignal
end

-- ──────────────────────────────────────────────────────────────
--  Phone open / close
-- ──────────────────────────────────────────────────────────────

--- Requests full phone data from server and opens the NUI.
local function OpenPhone()
    if phoneOpen then return end

    local item, model = GetPhoneItem()
    if not item then
        QBCore.Functions.Notify('You don\'t have a phone.', 'error', 3000)
        return
    end

    -- Check battery
    local meta = item.info or {}
    if (meta.battery or 100) <= 0 then
        QBCore.Functions.Notify('Your phone is dead. Charge it first.', 'error', 3000)
        return
    end

    -- Request all phone data (lazy-loaded per app on demand to save bandwidth)
    TriggerServerEvent('apexphone:server:requestPhoneData')

    -- Show NUI
    phoneOpen = true
    SetNuiFocus(true, true)
    SendNUI('open', {
        model   = model,
        meta    = meta,
        signal  = currentSignal,
        battery = meta.battery or 100,
        theme   = meta.theme or Config.UI.DefaultTheme,
        wallpaper = meta.wallpaper or Config.UI.DefaultWallpaper,
        airplaneMode = airplaneMode,
        dynamicIsland = Config.UI.DynamicIsland,
    })

    -- Begin battery drain while open
    StartBatteryDrain(model)
    TriggerEvent('apexphone:client:phoneOpened')
end

--- Closes the phone NUI and saves state.
local function ClosePhone()
    if not phoneOpen then return end
    phoneOpen = false
    SetNuiFocus(false, false)
    SendNUI('close', {})
    StopBatteryDrain()
    TriggerServerEvent('apexphone:server:phoneClosed', phoneData.battery)
    TriggerEvent('apexphone:client:phoneClosed')
end

-- ──────────────────────────────────────────────────────────────
--  Battery system
-- ──────────────────────────────────────────────────────────────

--- Starts a per-second battery drain tick while the phone is open.
function StartBatteryDrain(model)
    if batteryTick then return end
    local modelCfg = Config.PhoneModels[model] or Config.PhoneModels[Config.Items.PhoneFlagship]
    batteryTick = Citizen.CreateThread(function()
        while phoneOpen do
            Citizen.Wait(1000)
            if not phoneOpen then break end

            -- Charging check
            local coords = GetCoords()
            isCharging = false
            for _, zone in ipairs(Config.Battery.ChargingZones) do
                if #(coords - zone) < Config.Battery.ChargingRadius then
                    isCharging = true
                    break
                end
            end

            local delta = isCharging and Config.Battery.ChargeRate or -modelCfg.batteryDrain
            phoneData.battery = math.max(0, math.min(100, (phoneData.battery or 100) + delta))

            SendNUI('batteryUpdate', { battery = phoneData.battery, charging = isCharging })

            if phoneData.battery <= Config.Battery.CriticalWarning then
                SendNUI('notify', { message = 'Critical battery: ' .. math.floor(phoneData.battery) .. '%', type = 'error' })
            elseif phoneData.battery <= Config.Battery.LowWarning then
                SendNUI('notify', { message = 'Low battery: ' .. math.floor(phoneData.battery) .. '%', type = 'warning' })
            end

            if phoneData.battery <= 0 then
                ClosePhone()
                QBCore.Functions.Notify('Your phone died.', 'error', 3000)
                break
            end
        end
        batteryTick = nil
    end)
end

--- Stops the battery drain tick.
function StopBatteryDrain()
    batteryTick = nil
end

-- ──────────────────────────────────────────────────────────────
--  Signal zone polling  (only polls every 5 s to save CPU)
-- ──────────────────────────────────────────────────────────────

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        local sig = CalculateSignal()
        if sig ~= currentSignal then
            currentSignal = sig
            if phoneOpen then
                SendNUI('signalUpdate', { signal = currentSignal })
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────────
--  Background battery drain (very slow) when phone is closed
-- ──────────────────────────────────────────────────────────────

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000) -- every 60 s
        if not phoneOpen and phoneData.battery then
            phoneData.battery = math.max(0, phoneData.battery - (Config.Battery.DrainWhileClosed * 60))
        end
    end
end)

-- ──────────────────────────────────────────────────────────────
--  Voice call integration (pma-voice / mumble-voip)
-- ──────────────────────────────────────────────────────────────

--- Joins a dedicated voice channel for the call.
local function JoinCallChannel(channel)
    if Config.VoiceScript == 'pma-voice' then
        TriggerEvent('pma-voice:setCallChannel', channel)
    elseif Config.VoiceScript == 'mumble-voip' then
        TriggerEvent('mumble-voip:setCallChannel', channel)
    end
end

--- Leaves the call voice channel and returns to proximity voice.
local function LeaveCallChannel()
    if Config.VoiceScript == 'pma-voice' then
        TriggerEvent('pma-voice:setCallChannel', nil)
    elseif Config.VoiceScript == 'mumble-voip' then
        TriggerEvent('mumble-voip:setCallChannel', nil)
    end
end

--- Enables or disables the speaker mode (nearby players hear the call).
local function SetSpeaker(enabled)
    if not activeCall then return end
    activeCall.speaker = enabled
    if Config.VoiceScript == 'pma-voice' then
        TriggerEvent('pma-voice:setSpeaker', enabled)
    end
    SendNUI('callUpdate', { speaker = enabled })
end

-- Incoming call received from server
RegisterNetEvent('apexphone:client:incomingCall', function(callerNumber, callerName, callId, channel)
    if currentSignal == 0 then return end  -- no signal
    activeCall = { callId = callId, number = callerNumber, name = callerName, channel = channel, speaker = false, startTime = nil }
    SendNUI('incomingCall', { callId = callId, number = callerNumber, name = callerName })

    -- Ring timeout — auto decline after Config.Calls.RingTimeout seconds
    SetTimeout(Config.Calls.RingTimeout * 1000, function()
        if activeCall and activeCall.callId == callId and not activeCall.startTime then
            TriggerServerEvent('apexphone:server:declineCall', callId)
            activeCall = nil
            SendNUI('callEnded', { reason = 'missed' })
        end
    end)
end)

-- Call was answered (both sides confirmed)
RegisterNetEvent('apexphone:client:callConnected', function(callId, channel)
    if not activeCall or activeCall.callId ~= callId then return end
    activeCall.startTime = GetGameTimer()
    JoinCallChannel(channel)
    SendNUI('callConnected', { callId = callId, channel = channel })

    -- Enforce max call duration
    if Config.Calls.MaxCallDuration > 0 then
        SetTimeout(Config.Calls.MaxCallDuration * 1000, function()
            if activeCall and activeCall.callId == callId then
                TriggerServerEvent('apexphone:server:endCall', callId)
            end
        end)
    end
end)

-- Remote party ended / declined the call
RegisterNetEvent('apexphone:client:callEnded', function(callId, reason)
    if not activeCall or activeCall.callId ~= callId then return end
    LeaveCallChannel()
    activeCall = nil
    SendNUI('callEnded', { reason = reason or 'ended' })
end)

-- ──────────────────────────────────────────────────────────────
--  GPS & Live location sharing
-- ──────────────────────────────────────────────────────────────

--- Starts periodically broadcasting the player's coords to all
--- contacts that have been granted live-location access.
local function StartLiveGPS()
    if gpsThread then return end
    gpsThread = Citizen.CreateThread(function()
        while phoneData.sharingGPS do
            Citizen.Wait(Config.GPS.ShareUpdateInterval * 1000)
            if not phoneData.sharingGPS then break end
            local c = GetCoords()
            TriggerServerEvent('apexphone:server:updateGPSShare', c.x, c.y, c.z)
        end
        gpsThread = nil
    end)
end

--- Sets or clears a map waypoint when the player taps a GPS coordinate.
RegisterNetEvent('apexphone:client:setWaypoint', function(x, y)
    SetNewWaypoint(x, y)
    Notify('Waypoint set.', 'success')
end)

-- Received another player's live location
RegisterNetEvent('apexphone:client:receiveLiveLocation', function(number, name, x, y, z)
    SendNUI('liveLocation', { number = number, name = name, x = x, y = y, z = z })
end)

-- ──────────────────────────────────────────────────────────────
--  Camera / Photo system
-- ──────────────────────────────────────────────────────────────

--- Triggers NUI camera overlay. The JS side uses getUserMedia or a canvas
--- screenshot approach for taking the "photo" (base64 thumbnail).
local function OpenCamera()
    local item, model = GetPhoneItem()
    if not item then return end
    local cfg = Config.PhoneModels[model]
    if not cfg or not cfg.camera then
        Notify('This phone has no camera.', 'error')
        return
    end
    SendNUI('openCamera', {})
end

-- ──────────────────────────────────────────────────────────────
--  Fingerprint authentication (NUI-side animation bridge)
-- ──────────────────────────────────────────────────────────────

-- Server responds with fingerprint check result
RegisterNetEvent('apexphone:client:fingerprintResult', function(success)
    SendNUI('fingerprintResult', { success = success })
end)

-- ──────────────────────────────────────────────────────────────
--  IMEI clone minigame (dark web feature)
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:client:startIMEIClone', function()
    SendNUI('startMinigame', {
        type       = 'imei_clone',
        difficulty = Config.IMEI.CloneDifficulty or 3,
        duration   = Config.IMEI.CloneMinigameDuration,
    })
end)

-- ──────────────────────────────────────────────────────────────
--  Duress PIN — received from NUI after PIN verification
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:client:duressTriggered', function()
    -- Wipe local cache so nothing is visible in this session
    phoneData = {}
    SendNUI('duressWipe', {})
    -- Server already sent the police alert
end)

-- ──────────────────────────────────────────────────────────────
--  Phone destruction on death
-- ──────────────────────────────────────────────────────────────

AddEventHandler('baseevents:onPlayerDied', function()
    if phoneOpen then ClosePhone() end
    -- Visual cracked-screen effect persists until repaired (stored in meta)
    TriggerServerEvent('apexphone:server:phoneDamaged', 'died')
    SendNUI('phoneDamaged', { reason = 'died' })
end)

-- ──────────────────────────────────────────────────────────────
--  Proximity-based AirShare (contact sharing)
-- ──────────────────────────────────────────────────────────────

--- Finds nearby players within AirShare radius and returns their server IDs.
local function GetNearbyPlayers()
    local coords  = GetCoords()
    local nearby  = {}
    local players = GetActivePlayers()
    for _, pid in ipairs(players) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            if DoesEntityExist(ped) then
                local pcoords = GetEntityCoords(ped)
                if #(coords - pcoords) <= Config.Messages.AirShareRadius then
                    table.insert(nearby, { id = GetPlayerServerId(pid), name = GetPlayerName(pid) })
                end
            end
        end
    end
    return nearby
end

RegisterNetEvent('apexphone:client:requestNearby', function()
    local nearby = GetNearbyPlayers()
    SendNUI('nearbyPlayers', { players = nearby })
end)

-- ──────────────────────────────────────────────────────────────
--  Data transfer (phone-to-phone)
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:client:dataTransferRequest', function(fromName, fromNumber, transferId)
    SendNUI('dataTransferRequest', { fromName = fromName, fromNumber = fromNumber, transferId = transferId })
end)

RegisterNetEvent('apexphone:client:dataTransferProgress', function(transferId, progress)
    SendNUI('dataTransferProgress', { transferId = transferId, progress = progress })
end)

RegisterNetEvent('apexphone:client:dataTransferComplete', function(transferId)
    SendNUI('dataTransferComplete', { transferId = transferId })
    Notify('Data transfer complete.', 'success')
end)

-- ──────────────────────────────────────────────────────────────
--  Remote lock / Find-my-phone
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:client:remoteLock', function()
    if phoneOpen then ClosePhone() end
    phoneData.locked = true
    Notify('Your phone has been locked remotely.', 'warning')
end)

RegisterNetEvent('apexphone:client:findMyPhone', function(requesterId)
    -- Respond with current location to the server (server relays to requester)
    local c = GetCoords()
    TriggerServerEvent('apexphone:server:findMyPhoneResponse', requesterId, c.x, c.y, c.z)
end)

-- ──────────────────────────────────────────────────────────────
--  Dynamic Island helpers
-- ──────────────────────────────────────────────────────────────

--- Pushes a dynamic-island notification (call, music, nav) to the NUI.
local function DynamicIsland(type, data)
    if not Config.UI.DynamicIsland then return end
    SendNUI('dynamicIsland', { type = type, data = data })
end

-- Expose for other resources
exports('DynamicIsland', DynamicIsland)

-- ──────────────────────────────────────────────────────────────
--  Server → Client: full phone data delivered
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:client:phoneData', function(data)
    phoneData = data
    SendNUI('phoneData', data)
end)

RegisterNetEvent('apexphone:client:appData', function(app, data)
    SendNUI('appData', { app = app, data = data })
end)

-- ──────────────────────────────────────────────────────────────
--  Notifications pushed from server (SMS, missed call, etc.)
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:client:pushNotification', function(notif)
    -- Show even if phone is closed — small overlay
    SendNUI('pushNotification', notif)
    DynamicIsland('notification', notif)
end)

-- ──────────────────────────────────────────────────────────────
--  NUI Callbacks — JS → Lua bridge
-- ──────────────────────────────────────────────────────────────

-- Phone close button
RegisterNUICallback('closePhone', function(_, cb)
    ClosePhone()
    cb('ok')
end)

-- ── Authentication ───────────────────────────────────────────

RegisterNUICallback('verifyFingerprint', function(data, cb)
    TriggerServerEvent('apexphone:server:verifyFingerprint')
    cb('ok')
end)

RegisterNUICallback('verifyPIN', function(data, cb)
    if not data.pin then cb({ success = false }) return end
    TriggerServerEvent('apexphone:server:verifyPIN', tostring(data.pin))
    cb('ok')
end)

-- ── Calls ────────────────────────────────────────────────────

RegisterNUICallback('makeCall', function(data, cb)
    if currentSignal == 0 then cb({ error = 'No signal' }) return end
    if airplaneMode     then cb({ error = 'Airplane mode is on' }) return end
    if not data.number  then cb({ error = 'Invalid number' }) return end
    TriggerServerEvent('apexphone:server:makeCall', tostring(data.number))
    cb('ok')
end)

RegisterNUICallback('answerCall', function(data, cb)
    if not activeCall then cb('ok') return end
    TriggerServerEvent('apexphone:server:answerCall', activeCall.callId)
    cb('ok')
end)

RegisterNUICallback('declineCall', function(data, cb)
    if not activeCall then cb('ok') return end
    TriggerServerEvent('apexphone:server:declineCall', activeCall.callId)
    activeCall = nil
    SendNUI('callEnded', { reason = 'declined' })
    cb('ok')
end)

RegisterNUICallback('endCall', function(data, cb)
    if not activeCall then cb('ok') return end
    TriggerServerEvent('apexphone:server:endCall', activeCall.callId)
    cb('ok')
end)

RegisterNUICallback('setSpeaker', function(data, cb)
    SetSpeaker(data.enabled == true)
    cb('ok')
end)

-- ── Messages ─────────────────────────────────────────────────

RegisterNUICallback('sendMessage', function(data, cb)
    if currentSignal == 0 then cb({ error = 'No signal' }) return end
    if not data.to or not data.message then cb({ error = 'Invalid data' }) return end
    TriggerServerEvent('apexphone:server:sendMessage', {
        to      = tostring(data.to),
        message = tostring(data.message):sub(1, 500),
        type    = data.type or 'sms',
        media   = data.media,   -- base64 image or GPS coords table
    })
    cb('ok')
end)

RegisterNUICallback('createGroup', function(data, cb)
    if not data.name or not data.members then cb({ error = 'Invalid data' }) return end
    TriggerServerEvent('apexphone:server:createGroup', {
        name    = tostring(data.name):sub(1, 50),
        members = data.members,
    })
    cb('ok')
end)

RegisterNUICallback('sendGroupMessage', function(data, cb)
    if not data.groupId or not data.message then cb({ error = 'Invalid data' }) return end
    TriggerServerEvent('apexphone:server:sendGroupMessage', {
        groupId = data.groupId,
        message = tostring(data.message):sub(1, 500),
        media   = data.media,
    })
    cb('ok')
end)

RegisterNUICallback('shareContact', function(data, cb)
    if not data.targetServerId or not data.contactNumber then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:shareContact', tonumber(data.targetServerId), tostring(data.contactNumber))
    cb('ok')
end)

-- ── Contacts ─────────────────────────────────────────────────

RegisterNUICallback('saveContact', function(data, cb)
    if not data.name or not data.number then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:saveContact', {
        name   = tostring(data.name):sub(1, 50),
        number = tostring(data.number):sub(1, 20),
        avatar = data.avatar,
    })
    cb('ok')
end)

RegisterNUICallback('deleteContact', function(data, cb)
    if not data.id then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:deleteContact', tonumber(data.id))
    cb('ok')
end)

RegisterNUICallback('loadContacts', function(_, cb)
    TriggerServerEvent('apexphone:server:loadApp', 'contacts')
    cb('ok')
end)

-- ── Banking ──────────────────────────────────────────────────

RegisterNUICallback('getBankData', function(_, cb)
    TriggerServerEvent('apexphone:server:loadApp', 'bank')
    cb('ok')
end)

RegisterNUICallback('bankTransfer', function(data, cb)
    if not data.target or not data.amount then cb({ error = 'Invalid' }) return end
    local amount = tonumber(data.amount)
    if not amount or amount <= 0 then cb({ error = 'Invalid amount' }) return end
    TriggerServerEvent('apexphone:server:bankTransfer', {
        target = tostring(data.target),
        amount = amount,
        note   = tostring(data.note or ''):sub(1, 100),
    })
    cb('ok')
end)

RegisterNUICallback('payInvoice', function(data, cb)
    if not data.invoiceId then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:payInvoice', tonumber(data.invoiceId))
    cb('ok')
end)

-- ── Crypto ───────────────────────────────────────────────────

RegisterNUICallback('buyCrypto', function(data, cb)
    if not data.coin or not data.amount then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:buyCrypto', { coin = data.coin, amount = tonumber(data.amount) })
    cb('ok')
end)

RegisterNUICallback('sellCrypto', function(data, cb)
    if not data.coin or not data.amount then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:sellCrypto', { coin = data.coin, amount = tonumber(data.amount) })
    cb('ok')
end)

-- ── Social Media ─────────────────────────────────────────────

RegisterNUICallback('postTweet', function(data, cb)
    if not data.content then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:postSocial', { app = 'catiter', content = tostring(data.content):sub(1, 280), media = data.media })
    cb('ok')
end)

RegisterNUICallback('postInstaPic', function(data, cb)
    if not data.caption then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:postSocial', { app = 'instapic', content = tostring(data.caption):sub(1, 300), media = data.media })
    cb('ok')
end)

RegisterNUICallback('likeSocialPost', function(data, cb)
    if not data.postId then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:likeSocialPost', tonumber(data.postId), data.app)
    cb('ok')
end)

RegisterNUICallback('deleteSocialPost', function(data, cb)
    if not data.postId then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:deleteSocialPost', tonumber(data.postId), data.app)
    cb('ok')
end)

-- ── GPS ──────────────────────────────────────────────────────

RegisterNUICallback('setWaypoint', function(data, cb)
    if not data.x or not data.y then cb({ error = 'Invalid' }) return end
    SetNewWaypoint(tonumber(data.x), tonumber(data.y))
    cb('ok')
end)

RegisterNUICallback('shareLiveLocation', function(data, cb)
    if not data.target then cb({ error = 'Invalid' }) return end
    phoneData.sharingGPS = true
    TriggerServerEvent('apexphone:server:startGPSShare', tostring(data.target))
    StartLiveGPS()
    cb('ok')
end)

RegisterNUICallback('stopLiveLocation', function(_, cb)
    phoneData.sharingGPS = false
    TriggerServerEvent('apexphone:server:stopGPSShare')
    cb('ok')
end)

RegisterNUICallback('sendLocationSMS', function(data, cb)
    local c = GetCoords()
    TriggerServerEvent('apexphone:server:sendMessage', {
        to      = tostring(data.to),
        message = '📍 My location',
        type    = 'location',
        media   = { x = c.x, y = c.y, z = c.z },
    })
    cb('ok')
end)

-- ── Camera / Gallery ─────────────────────────────────────────

RegisterNUICallback('openCamera', function(_, cb)
    OpenCamera()
    cb('ok')
end)

RegisterNUICallback('savePhoto', function(data, cb)
    if not data.base64 then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:savePhoto', {
        data    = data.base64:sub(1, 1024 * 1024 * 5), -- 5 MB max
        caption = tostring(data.caption or ''):sub(1, 200),
    })
    cb('ok')
end)

RegisterNUICallback('deletePhoto', function(data, cb)
    if not data.id then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:deletePhoto', tonumber(data.id))
    cb('ok')
end)

-- ── Marketplace ──────────────────────────────────────────────

RegisterNUICallback('createListing', function(data, cb)
    if not data.title or not data.price then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:createListing', {
        title       = tostring(data.title):sub(1, 80),
        description = tostring(data.description or ''):sub(1, 500),
        price       = tonumber(data.price),
        category    = data.category or 'Other',
        images      = data.images or {},
    })
    cb('ok')
end)

RegisterNUICallback('deleteListing', function(data, cb)
    if not data.id then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:deleteListing', tonumber(data.id))
    cb('ok')
end)

RegisterNUICallback('contactSeller', function(data, cb)
    if not data.sellerNumber then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:sendMessage', {
        to      = tostring(data.sellerNumber),
        message = 'Hi, I\'m interested in your listing: ' .. tostring(data.title or ''),
        type    = 'sms',
    })
    cb('ok')
end)

-- ── Dark Web ─────────────────────────────────────────────────

RegisterNUICallback('darkWebBuy', function(data, cb)
    if not data.itemId then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:darkWebBuy', tonumber(data.itemId))
    cb('ok')
end)

RegisterNUICallback('darkWebSell', function(data, cb)
    if not data.itemName or not data.price then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:darkWebSell', {
        itemName = tostring(data.itemName),
        price    = tonumber(data.price),
    })
    cb('ok')
end)

RegisterNUICallback('sendDarkChat', function(data, cb)
    if not data.to or not data.message then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:sendDarkChat', {
        to      = tostring(data.to):sub(1, 50),
        message = tostring(data.message):sub(1, 500),
    })
    cb('ok')
end)

RegisterNUICallback('startIMEIClone', function(_, cb)
    TriggerServerEvent('apexphone:server:requestIMEIClone')
    cb('ok')
end)

RegisterNUICallback('imeiCloneResult', function(data, cb)
    TriggerServerEvent('apexphone:server:imeiCloneResult', data.success == true)
    cb('ok')
end)

-- ── Settings ─────────────────────────────────────────────────

RegisterNUICallback('saveSettings', function(data, cb)
    TriggerServerEvent('apexphone:server:saveSettings', {
        theme      = data.theme,
        wallpaper  = data.wallpaper,
        ringtone   = data.ringtone,
        darkMode   = data.darkMode,
        pin        = data.pin and tostring(data.pin):sub(1, 6) or nil,
        duressPin  = data.duressPin and tostring(data.duressPin):sub(1, 6) or nil,
    })
    cb('ok')
end)

RegisterNUICallback('toggleAirplaneMode', function(data, cb)
    airplaneMode = data.enabled == true
    currentSignal = CalculateSignal()
    SendNUI('signalUpdate', { signal = currentSignal, airplaneMode = airplaneMode })
    cb('ok')
end)

RegisterNUICallback('remoteWipe', function(data, cb)
    if not data.targetNumber then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:remoteWipe', tostring(data.targetNumber))
    cb('ok')
end)

RegisterNUICallback('remoteLock', function(data, cb)
    if not data.targetNumber then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:remoteLock', tostring(data.targetNumber))
    cb('ok')
end)

-- ── MDT / Police ─────────────────────────────────────────────

RegisterNUICallback('mdtLookupIMEI', function(data, cb)
    if not data.imei then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:mdtLookupIMEI', tostring(data.imei):sub(1, 20))
    cb('ok')
end)

RegisterNUICallback('mdtFlagIMEI', function(data, cb)
    if not data.imei then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:mdtFlagIMEI', tostring(data.imei):sub(1, 20), data.reason)
    cb('ok')
end)

-- ── Data Transfer ────────────────────────────────────────────

RegisterNUICallback('initiateDataTransfer', function(data, cb)
    if not data.targetServerId then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:initiateDataTransfer', tonumber(data.targetServerId))
    cb('ok')
end)

RegisterNUICallback('acceptDataTransfer', function(data, cb)
    if not data.transferId then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:acceptDataTransfer', data.transferId)
    cb('ok')
end)

RegisterNUICallback('cloudBackup', function(_, cb)
    TriggerServerEvent('apexphone:server:cloudBackup')
    cb('ok')
end)

RegisterNUICallback('cloudRestore', function(_, cb)
    TriggerServerEvent('apexphone:server:cloudRestore')
    cb('ok')
end)

-- ── Email ─────────────────────────────────────────────────────

RegisterNUICallback('sendEmail', function(data, cb)
    if not data.to or not data.subject or not data.body then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:sendEmail', {
        to         = tostring(data.to):sub(1, 100),
        subject    = tostring(data.subject):sub(1, 150),
        body       = tostring(data.body):sub(1, 5000),
        attachment = data.attachment,
    })
    cb('ok')
end)

-- ── Garage ────────────────────────────────────────────────────

RegisterNUICallback('getGarageVehicles', function(_, cb)
    TriggerServerEvent('apexphone:server:loadApp', 'garage')
    cb('ok')
end)

RegisterNUICallback('retrieveVehicle', function(data, cb)
    if not data.plate then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:retrieveVehicle', tostring(data.plate))
    cb('ok')
end)

-- ── Uber-style Taxi ──────────────────────────────────────────

RegisterNUICallback('requestRide', function(data, cb)
    local c = GetCoords()
    TriggerServerEvent('apexphone:server:requestRide', {
        pickup  = { x = c.x, y = c.y, z = c.z },
        dest    = data.dest,
        note    = tostring(data.note or ''):sub(1, 100),
    })
    cb('ok')
end)

RegisterNUICallback('acceptRide', function(data, cb)
    if not data.rideId then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:acceptRide', tonumber(data.rideId))
    cb('ok')
end)

-- ── App Lazy Load ────────────────────────────────────────────

RegisterNUICallback('loadApp', function(data, cb)
    if not data.app then cb({ error = 'Invalid' }) return end
    TriggerServerEvent('apexphone:server:loadApp', tostring(data.app))
    cb('ok')
end)

-- ──────────────────────────────────────────────────────────────
--  Keybinding to open/close phone
-- ──────────────────────────────────────────────────────────────

RegisterKeyMapping('apexphone_toggle', 'Open / Close Phone', 'keyboard', Config.OpenKey)

RegisterCommand('apexphone_toggle', function()
    if phoneOpen then
        ClosePhone()
    else
        OpenPhone()
    end
end, false)

-- ──────────────────────────────────────────────────────────────
--  Export for other resources
-- ──────────────────────────────────────────────────────────────

exports('IsPhoneOpen',     function() return phoneOpen end)
exports('OpenPhone',       OpenPhone)
exports('ClosePhone',      ClosePhone)
exports('GetPhoneSignal',  function() return currentSignal end)
exports('IsAirplaneMode',  function() return airplaneMode end)
exports('PushNotification', function(notif) TriggerEvent('apexphone:client:pushNotification', notif) end)
