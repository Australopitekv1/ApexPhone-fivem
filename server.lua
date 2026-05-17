-- ============================================================
--  ApexPhone — server.lua
--  All server-side logic: DB access, event security validation,
--  call routing, IMEI management, crypto ticks, admin panel.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

-- ──────────────────────────────────────────────────────────────
--  Bootstrap — create tables on first run
-- ──────────────────────────────────────────────────────────────

local function BootstrapDB()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_phones` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `imei`        VARCHAR(20)  UNIQUE NOT NULL,
            `serial`      VARCHAR(20)  UNIQUE NOT NULL,
            `model`       VARCHAR(50)  NOT NULL,
            `owner`       VARCHAR(50)  NOT NULL,
            `pin`         VARCHAR(10)  DEFAULT NULL,
            `duress_pin`  VARCHAR(10)  DEFAULT NULL,
            `battery`     FLOAT        DEFAULT 100,
            `locked`      TINYINT(1)   DEFAULT 0,
            `cracked`     TINYINT(1)   DEFAULT 0,
            `imei_flagged` TINYINT(1)  DEFAULT 0,
            `theme`       VARCHAR(50)  DEFAULT 'dark',
            `wallpaper`   VARCHAR(100) DEFAULT 'default',
            `ringtone`    VARCHAR(100) DEFAULT 'default',
            `metadata`    JSON         DEFAULT NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`citizenid`), INDEX (`imei`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_sims` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `number`      VARCHAR(20)  UNIQUE NOT NULL,
            `citizenid`   VARCHAR(50)  DEFAULT NULL,
            `phone_imei`  VARCHAR(20)  DEFAULT NULL,
            `active`      TINYINT(1)   DEFAULT 1,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`number`), INDEX (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_contacts` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `name`        VARCHAR(100) NOT NULL,
            `number`      VARCHAR(20)  NOT NULL,
            `avatar`      TEXT         DEFAULT NULL,
            `favourite`   TINYINT(1)   DEFAULT 0,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_messages` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `thread_id`   VARCHAR(100) NOT NULL,
            `from_number` VARCHAR(20)  NOT NULL,
            `to_number`   VARCHAR(20)  NOT NULL,
            `message`     TEXT         NOT NULL,
            `type`        VARCHAR(20)  DEFAULT 'sms',
            `media`       JSON         DEFAULT NULL,
            `read`        TINYINT(1)   DEFAULT 0,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`thread_id`), INDEX (`from_number`), INDEX (`to_number`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_groups` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `name`        VARCHAR(100) NOT NULL,
            `owner`       VARCHAR(20)  NOT NULL,
            `members`     JSON         NOT NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_call_history` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `number`      VARCHAR(20)  NOT NULL,
            `direction`   ENUM('in','out') NOT NULL,
            `duration`    INT          DEFAULT 0,
            `status`      ENUM('answered','missed','declined') DEFAULT 'answered',
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_emails` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `to_citizenid` VARCHAR(50)  NOT NULL,
            `from_number` VARCHAR(20)  NOT NULL,
            `subject`     VARCHAR(200) NOT NULL,
            `body`        TEXT         NOT NULL,
            `attachment`  JSON         DEFAULT NULL,
            `read`        TINYINT(1)   DEFAULT 0,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`to_citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_social` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `app`         VARCHAR(30)  NOT NULL,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `display_name` VARCHAR(100) NOT NULL,
            `content`     TEXT         NOT NULL,
            `media`       JSON         DEFAULT NULL,
            `likes`       INT          DEFAULT 0,
            `liked_by`    JSON         DEFAULT '[]',
            `anonymous`   TINYINT(1)   DEFAULT 0,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`app`), INDEX (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_gallery` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `data`        LONGTEXT     NOT NULL,
            `caption`     VARCHAR(300) DEFAULT NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_marketplace` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `seller_number` VARCHAR(20) NOT NULL,
            `title`       VARCHAR(100) NOT NULL,
            `description` TEXT         DEFAULT NULL,
            `price`       INT          NOT NULL,
            `category`    VARCHAR(50)  DEFAULT 'Other',
            `images`      JSON         DEFAULT NULL,
            `active`      TINYINT(1)   DEFAULT 1,
            `expires_at`  TIMESTAMP    NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`citizenid`), INDEX (`active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_dark_listings` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `seller_anon` VARCHAR(50)  NOT NULL,
            `item_name`   VARCHAR(100) NOT NULL,
            `item_label`  VARCHAR(100) NOT NULL,
            `price`       INT          NOT NULL,
            `active`      TINYINT(1)   DEFAULT 1,
            `expires_at`  TIMESTAMP    NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_dark_chat` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `from_anon`   VARCHAR(50)  NOT NULL,
            `to_anon`     VARCHAR(50)  NOT NULL,
            `message`     TEXT         NOT NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`from_anon`), INDEX (`to_anon`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_crypto` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `coin`        VARCHAR(10)  NOT NULL,
            `amount`      FLOAT        DEFAULT 0,
            PRIMARY KEY(`id`),
            UNIQUE KEY (`citizenid`, `coin`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_crypto_prices` (
            `coin`        VARCHAR(10)  PRIMARY KEY,
            `price`       FLOAT        NOT NULL,
            `updated_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_invoices` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `from_citizenid` VARCHAR(50) NOT NULL,
            `to_citizenid`   VARCHAR(50) NOT NULL,
            `amount`      INT          NOT NULL,
            `note`        VARCHAR(300) DEFAULT NULL,
            `paid`        TINYINT(1)   DEFAULT 0,
            `due_at`      TIMESTAMP    NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`to_citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_gps_shares` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `from_number` VARCHAR(20)  NOT NULL,
            `to_number`   VARCHAR(20)  NOT NULL,
            `x`           FLOAT        DEFAULT 0,
            `y`           FLOAT        DEFAULT 0,
            `z`           FLOAT        DEFAULT 0,
            `active`      TINYINT(1)   DEFAULT 1,
            `updated_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX (`from_number`), INDEX (`to_number`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_imei_history` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `imei`        VARCHAR(20)  NOT NULL,
            `citizenid`   VARCHAR(50)  NOT NULL,
            `action`      VARCHAR(100) NOT NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`imei`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_cloud_backup` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  UNIQUE NOT NULL,
            `backup_data` LONGTEXT     NOT NULL,
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `apexphone_rides` (
            `id`          INT AUTO_INCREMENT PRIMARY KEY,
            `passenger_citizenid` VARCHAR(50)  NOT NULL,
            `driver_citizenid`    VARCHAR(50)  DEFAULT NULL,
            `pickup_x`    FLOAT        NOT NULL,
            `pickup_y`    FLOAT        NOT NULL,
            `pickup_z`    FLOAT        NOT NULL,
            `dest`        VARCHAR(200) DEFAULT NULL,
            `note`        VARCHAR(200) DEFAULT NULL,
            `status`      ENUM('pending','accepted','completed','cancelled') DEFAULT 'pending',
            `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Seed initial crypto prices
    for _, coin in ipairs(Config.Crypto.Coins) do
        MySQL.query([[
            INSERT IGNORE INTO `apexphone_crypto_prices` (`coin`, `price`) VALUES (?, ?)
        ]], { coin.id, coin.basePrice })
    end

    print('^2[ApexPhone]^0 Database bootstrap complete.')
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    BootstrapDB()
    StartCryptoPriceTick()
    StartDarkChatCleanup()
    StartMarketplaceCleanup()
end)

-- ──────────────────────────────────────────────────────────────
--  Utility helpers
-- ──────────────────────────────────────────────────────────────

--- Returns the QBCore Player object for a server source, or nil.
local function GetPlayer(source)
    return QBCore.Functions.GetPlayer(source)
end

--- Returns the citizenid for a source, or nil.
local function GetCitizenId(source)
    local p = GetPlayer(source)
    return p and p.PlayerData.citizenid or nil
end

--- Generates a unique 15-digit IMEI string.
local function GenerateIMEI()
    local imei = ''
    for i = 1, Config.IMEI.Length do
        imei = imei .. tostring(math.random(0, 9))
    end
    return imei
end

--- Generates a unique alphanumeric serial number (8 chars).
local function GenerateSerial()
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local serial = ''
    for i = 1, 8 do
        local idx = math.random(1, #chars)
        serial = serial .. chars:sub(idx, idx)
    end
    return serial
end

--- Generates a phone number string.
local function GenerateNumber()
    local number = Config.SIM.NumberPrefix
    for i = 1, Config.SIM.NumberLength - #Config.SIM.NumberPrefix do
        number = number .. tostring(math.random(0, 9))
    end
    return number
end

--- Returns the phone record for a citizenid.
local function GetPhoneRecord(citizenid)
    return MySQL.query.await('SELECT * FROM `apexphone_phones` WHERE `citizenid` = ? LIMIT 1', { citizenid })
end

--- Returns the SIM record for a citizenid.
local function GetSimRecord(citizenid)
    return MySQL.query.await('SELECT * FROM `apexphone_sims` WHERE `citizenid` = ? AND `active` = 1 LIMIT 1', { citizenid })
end

--- Returns a player's phone number, or nil.
local function GetPlayerNumber(citizenid)
    local rows = MySQL.query.await('SELECT `number` FROM `apexphone_sims` WHERE `citizenid` = ? AND `active` = 1 LIMIT 1', { citizenid })
    return rows and rows[1] and rows[1].number or nil
end

--- Returns the source of an online player by their phone number.
local function GetSourceByNumber(number)
    local players = QBCore.Functions.GetPlayers()
    for _, src in ipairs(players) do
        local p = GetPlayer(src)
        if p then
            local cid = p.PlayerData.citizenid
            local num = GetPlayerNumber(cid)
            if num == number then return src end
        end
    end
    return nil
end

--- Logs an action to the IMEI history table.
local function LogIMEI(imei, citizenid, action)
    MySQL.insert('INSERT INTO `apexphone_imei_history` (`imei`, `citizenid`, `action`) VALUES (?, ?, ?)',
        { imei, citizenid, action })
end

--- Logs a general action to server console (admin log).
local function AdminLog(action, citizenid, detail)
    print(('[ApexPhone][LOG] %s | CID: %s | %s'):format(action, citizenid, detail or ''))
    -- Extend here to write to a `apexphone_logs` table or Discord webhook
end

-- ──────────────────────────────────────────────────────────────
--  Phone creation (called by inventory on item use if no entry)
-- ──────────────────────────────────────────────────────────────

--- Creates a new phone record in the DB with unique IMEI & serial.
local function CreatePhone(citizenid, model)
    local imei, serial

    -- Ensure uniqueness
    repeat
        imei = GenerateIMEI()
    until not MySQL.query.await('SELECT id FROM `apexphone_phones` WHERE `imei` = ?', { imei })[1]

    repeat
        serial = GenerateSerial()
    until not MySQL.query.await('SELECT id FROM `apexphone_phones` WHERE `serial` = ?', { serial })[1]

    MySQL.insert('INSERT INTO `apexphone_phones` (`citizenid`,`imei`,`serial`,`model`,`owner`) VALUES (?,?,?,?,?)',
        { citizenid, imei, serial, model, citizenid })

    LogIMEI(imei, citizenid, 'created')
    AdminLog('PHONE_CREATED', citizenid, 'IMEI:' .. imei .. ' Model:' .. model)
    return imei, serial
end

--- Creates a new SIM record and assigns it to a citizenid.
local function CreateSIM(citizenid)
    local number
    repeat
        number = GenerateNumber()
    until not MySQL.query.await('SELECT id FROM `apexphone_sims` WHERE `number` = ?', { number })[1]

    -- Deactivate old SIM
    MySQL.query('UPDATE `apexphone_sims` SET `active` = 0 WHERE `citizenid` = ?', { citizenid })
    MySQL.insert('INSERT INTO `apexphone_sims` (`number`, `citizenid`, `active`) VALUES (?, ?, 1)', { number, citizenid })
    return number
end

-- ──────────────────────────────────────────────────────────────
--  Phone data delivery
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:requestPhoneData', function()
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    local phones = GetPhoneRecord(cid)
    local phone  = phones and phones[1]
    if not phone then return end  -- no phone record; shouldn't reach here

    local sim = GetSimRecord(cid)
    local number = sim and sim[1] and sim[1].number or nil

    -- Only send lightweight initial data; apps lazy-load on demand
    TriggerClientEvent('apexphone:client:phoneData', src, {
        imei      = phone.imei,
        serial    = phone.serial,
        model     = phone.model,
        battery   = phone.battery,
        locked    = phone.locked == 1,
        cracked   = phone.cracked == 1,
        theme     = phone.theme,
        wallpaper = phone.wallpaper,
        ringtone  = phone.ringtone,
        number    = number,
        hasPin    = phone.pin ~= nil,
        metadata  = phone.metadata,
    })
end)

--- Lazy-loads a single app's data and sends it to the client.
RegisterNetEvent('apexphone:server:loadApp', function(app)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    local data = {}

    if app == 'contacts' then
        data = MySQL.query.await('SELECT * FROM `apexphone_contacts` WHERE `citizenid` = ? ORDER BY `name`', { cid })

    elseif app == 'messages' then
        local number = GetPlayerNumber(cid)
        if number then
            data = MySQL.query.await([[
                SELECT m.*, (SELECT COUNT(*) FROM `apexphone_messages` WHERE `thread_id` = m.thread_id AND `read` = 0 AND `to_number` = ?) AS unread
                FROM `apexphone_messages` m
                WHERE m.thread_id IN (
                    SELECT DISTINCT thread_id FROM `apexphone_messages`
                    WHERE from_number = ? OR to_number = ?
                )
                ORDER BY m.created_at DESC
                LIMIT ?
            ]], { number, number, number, Config.Messages.MaxPerThread })
        end

    elseif app == 'callhistory' then
        data = MySQL.query.await('SELECT * FROM `apexphone_call_history` WHERE `citizenid` = ? ORDER BY `created_at` DESC LIMIT ?',
            { cid, Config.Calls.CallHistoryLimit })

    elseif app == 'bank' then
        local p = GetPlayer(src)
        if p then
            data = {
                bank    = p.PlayerData.money.bank,
                cash    = p.PlayerData.money.cash,
                invoices = MySQL.query.await('SELECT * FROM `apexphone_invoices` WHERE `to_citizenid` = ? AND `paid` = 0', { cid }),
            }
        end

    elseif app == 'crypto' then
        local holdings = MySQL.query.await('SELECT * FROM `apexphone_crypto` WHERE `citizenid` = ?', { cid })
        local prices   = MySQL.query.await('SELECT * FROM `apexphone_crypto_prices`')
        data = { holdings = holdings, prices = prices, coins = Config.Crypto.Coins }

    elseif app == 'gallery' then
        data = MySQL.query.await('SELECT `id`,`caption`,`created_at` FROM `apexphone_gallery` WHERE `citizenid` = ? ORDER BY `created_at` DESC', { cid })

    elseif app == 'marketplace' then
        data = MySQL.query.await('SELECT * FROM `apexphone_marketplace` WHERE `active` = 1 AND (`expires_at` IS NULL OR `expires_at` > NOW()) ORDER BY `created_at` DESC')

    elseif app == 'catiter' then
        data = MySQL.query.await('SELECT * FROM `apexphone_social` WHERE `app` = "catiter" ORDER BY `created_at` DESC LIMIT 100')

    elseif app == 'instapic' then
        data = MySQL.query.await('SELECT * FROM `apexphone_social` WHERE `app` = "instapic" ORDER BY `created_at` DESC LIMIT 50')

    elseif app == 'tiktok' then
        data = MySQL.query.await('SELECT * FROM `apexphone_social` WHERE `app` = "tiktok" ORDER BY `created_at` DESC LIMIT 50')

    elseif app == 'flirtdate' then
        -- FlirtDate shows nearby profiles; return all profiles (client filters by distance)
        data = MySQL.query.await('SELECT `citizenid`,`display_name`,`content` AS `bio`,`media` AS `photos` FROM `apexphone_social` WHERE `app` = "flirtdate" ORDER BY RAND() LIMIT 50')

    elseif app == 'darkweb' then
        data = {
            listings = MySQL.query.await('SELECT * FROM `apexphone_dark_listings` WHERE `active` = 1 AND (`expires_at` IS NULL OR `expires_at` > NOW()) ORDER BY `created_at` DESC'),
            blacklist = Config.DarkWeb.BlacklistItems,
        }

    elseif app == 'email' then
        data = MySQL.query.await('SELECT * FROM `apexphone_emails` WHERE `to_citizenid` = ? ORDER BY `created_at` DESC LIMIT 100', { cid })

    elseif app == 'garage' then
        -- Delegate to garage resource if available
        local ok, vehicles = pcall(function()
            return exports[Config.Garage.Resource]:GetPlayerVehicles(src)
        end)
        data = ok and vehicles or {}

    elseif app == 'mdt' then
        -- Only police/admin can access MDT
        local p = GetPlayer(src)
        if p and (p.PlayerData.job.name == 'police' or IsAdmin(src)) then
            data = { access = true }
        else
            data = { access = false }
        end
    end

    TriggerClientEvent('apexphone:client:appData', src, app, data)
end)

-- ──────────────────────────────────────────────────────────────
--  Phone save on close
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:phoneClosed', function(battery)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end
    MySQL.query('UPDATE `apexphone_phones` SET `battery` = ? WHERE `citizenid` = ?',
        { tonumber(battery) or 100, cid })
end)

-- ──────────────────────────────────────────────────────────────
--  Authentication
-- ──────────────────────────────────────────────────────────────

-- Track PIN lockouts server-side: key = citizenid, value = { attempts, unlocksAt }
local pinLockouts = {}

RegisterNetEvent('apexphone:server:verifyFingerprint', function()
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end
    local phones = GetPhoneRecord(cid)
    local phone  = phones and phones[1]
    -- Fingerprint: passes if the phone's owner == current citizenid
    local success = phone and phone.owner == cid
    TriggerClientEvent('apexphone:client:fingerprintResult', src, success)
end)

RegisterNetEvent('apexphone:server:verifyPIN', function(pin)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not pin then return end

    -- Check lockout
    local lockout = pinLockouts[cid]
    if lockout and lockout.unlocksAt > os.time() then
        local remaining = lockout.unlocksAt - os.time()
        TriggerClientEvent('apexphone:client:fingerprintResult', src, false)
        TriggerClientEvent('apexphone:client:pushNotification', src, {
            title   = 'Phone Locked',
            message = 'Too many attempts. Unlocks in ' .. remaining .. 's.',
            type    = 'error',
        })
        return
    end

    local phones = GetPhoneRecord(cid)
    local phone  = phones and phones[1]
    if not phone then return end

    -- Duress PIN check
    if Config.Security.DuressPIN and phone.duress_pin and pin == phone.duress_pin then
        -- Wipe data and alert police
        MySQL.query('UPDATE `apexphone_phones` SET `pin` = NULL, `metadata` = NULL WHERE `citizenid` = ?', { cid })
        MySQL.query('DELETE FROM `apexphone_contacts` WHERE `citizenid` = ?', { cid })
        MySQL.query('DELETE FROM `apexphone_messages` WHERE `from_number` = (SELECT number FROM `apexphone_sims` WHERE citizenid = ?)', { cid })
        MySQL.query('DELETE FROM `apexphone_gallery` WHERE `citizenid` = ?', { cid })
        TriggerClientEvent('apexphone:client:duressTriggered', src)
        -- Alert police
        AlertPolice(src, cid, 'DURESS PIN activated — owner is in danger.')
        AdminLog('DURESS_PIN', cid, 'Phone wiped, police alerted')
        TriggerClientEvent('apexphone:client:fingerprintResult', src, true) -- appear successful
        return
    end

    local success = phone.pin == nil or pin == phone.pin
    if success then
        pinLockouts[cid] = nil  -- reset lockout
    else
        if not pinLockouts[cid] then
            pinLockouts[cid] = { attempts = 0, unlocksAt = 0 }
        end
        pinLockouts[cid].attempts = pinLockouts[cid].attempts + 1
        if pinLockouts[cid].attempts >= Config.Security.MaxPINAttempts then
            pinLockouts[cid].unlocksAt = os.time() + Config.Security.LockoutDuration
            pinLockouts[cid].attempts  = 0
        end
    end

    TriggerClientEvent('apexphone:client:fingerprintResult', src, success)
end)

-- ──────────────────────────────────────────────────────────────
--  Call system
-- ──────────────────────────────────────────────────────────────

local activeCalls = {}  -- callId → { caller, callee, channel, startTime }
local callCounter = 0

local function NewCallId()
    callCounter = callCounter + 1
    return 'call_' .. GetGameTimer() .. '_' .. callCounter
end

RegisterNetEvent('apexphone:server:makeCall', function(targetNumber)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    local callerNumber = GetPlayerNumber(cid)
    if not callerNumber then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'No SIM', message = 'Insert a SIM card to make calls.', type = 'error' })
        return
    end

    local targetSrc = GetSourceByNumber(targetNumber)
    if not targetSrc then
        -- Target offline — could leave voicemail; for now return missed
        TriggerClientEvent('apexphone:client:callEnded', src, nil, 'unavailable')
        return
    end

    local callId = NewCallId()
    local channel = 'apexphone_call_' .. callId

    activeCalls[callId] = {
        callerSrc    = src,
        callerNumber = callerNumber,
        calleeSrc    = targetSrc,
        calleeNumber = targetNumber,
        channel      = channel,
        startTime    = nil,
    }

    -- Find caller's name for the receiver
    local callerName = GetPlayerName(src)

    TriggerClientEvent('apexphone:client:incomingCall', targetSrc, callerNumber, callerName, callId, channel)
    -- Inform caller that it's ringing
    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Calling...', message = targetNumber, type = 'call' })

    if Config.Admin.LogAllCalls then
        AdminLog('CALL_INITIATED', cid, callerNumber .. ' → ' .. targetNumber)
    end
end)

RegisterNetEvent('apexphone:server:answerCall', function(callId)
    local src = source
    local call = activeCalls[callId]
    if not call then return end
    if call.calleeSrc ~= src then return end  -- security: only callee can answer

    call.startTime = os.time()
    TriggerClientEvent('apexphone:client:callConnected', call.callerSrc, callId, call.channel)
    TriggerClientEvent('apexphone:client:callConnected', call.calleeSrc, callId, call.channel)
end)

RegisterNetEvent('apexphone:server:declineCall', function(callId)
    local src = source
    local call = activeCalls[callId]
    if not call then return end

    local otherSrc = (src == call.callerSrc) and call.calleeSrc or call.callerSrc
    TriggerClientEvent('apexphone:client:callEnded', call.callerSrc, callId, 'declined')
    TriggerClientEvent('apexphone:client:callEnded', call.calleeSrc, callId, 'declined')
    activeCalls[callId] = nil

    -- Log missed call
    local callerCid = GetCitizenId(call.callerSrc)
    local calleeCid = GetCitizenId(call.calleeSrc)
    if callerCid then MySQL.insert('INSERT INTO `apexphone_call_history` (`citizenid`,`number`,`direction`,`status`) VALUES (?,?,?,?)', { callerCid, call.calleeNumber, 'out', 'declined' }) end
    if calleeCid then MySQL.insert('INSERT INTO `apexphone_call_history` (`citizenid`,`number`,`direction`,`status`) VALUES (?,?,?,?)', { calleeCid, call.callerNumber, 'in', 'missed' }) end
end)

RegisterNetEvent('apexphone:server:endCall', function(callId)
    local src = source
    local call = activeCalls[callId]
    if not call then return end
    if call.callerSrc ~= src and call.calleeSrc ~= src then return end

    local duration = call.startTime and (os.time() - call.startTime) or 0

    TriggerClientEvent('apexphone:client:callEnded', call.callerSrc, callId, 'ended')
    TriggerClientEvent('apexphone:client:callEnded', call.calleeSrc, callId, 'ended')
    activeCalls[callId] = nil

    local callerCid = GetCitizenId(call.callerSrc)
    local calleeCid = GetCitizenId(call.calleeSrc)
    if callerCid then MySQL.insert('INSERT INTO `apexphone_call_history` (`citizenid`,`number`,`direction`,`duration`,`status`) VALUES (?,?,?,?,?)', { callerCid, call.calleeNumber, 'out', duration, 'answered' }) end
    if calleeCid then MySQL.insert('INSERT INTO `apexphone_call_history` (`citizenid`,`number`,`direction`,`duration`,`status`) VALUES (?,?,?,?,?)', { calleeCid, call.callerNumber, 'in', duration, 'answered' }) end
end)

-- ──────────────────────────────────────────────────────────────
--  Messaging
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:sendMessage', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data or not data.to or not data.message then return end

    local fromNumber = GetPlayerNumber(cid)
    if not fromNumber then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'No SIM', message = 'Insert a SIM card to send messages.', type = 'error' })
        return
    end

    local toNumber = tostring(data.to)
    local message  = tostring(data.message):sub(1, 500)
    local msgType  = data.type or 'sms'
    local threadId = fromNumber < toNumber and (fromNumber .. '_' .. toNumber) or (toNumber .. '_' .. fromNumber)

    MySQL.insert('INSERT INTO `apexphone_messages` (`thread_id`,`from_number`,`to_number`,`message`,`type`,`media`) VALUES (?,?,?,?,?,?)',
        { threadId, fromNumber, toNumber, message, msgType, data.media and json.encode(data.media) or nil })

    -- Push notification to recipient if online
    local targetSrc = GetSourceByNumber(toNumber)
    if targetSrc then
        local senderName = GetPlayerName(src)
        TriggerClientEvent('apexphone:client:pushNotification', targetSrc, {
            title   = senderName,
            message = (msgType == 'location') and '📍 Shared location' or message:sub(1, 60),
            type    = 'message',
            number  = fromNumber,
        })
        -- Also update their messages app if open
        TriggerClientEvent('apexphone:client:appData', targetSrc, 'newMessage', {
            threadId   = threadId,
            from       = fromNumber,
            message    = message,
            type       = msgType,
            media      = data.media,
            created_at = os.date('%Y-%m-%d %H:%M:%S'),
        })
    end

    if Config.Admin.LogAllMessages then
        AdminLog('SMS', cid, fromNumber .. ' → ' .. toNumber .. ': ' .. message:sub(1, 60))
    end
end)

RegisterNetEvent('apexphone:server:createGroup', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data or not data.name or not data.members then return end

    local ownerNumber = GetPlayerNumber(cid)
    if not ownerNumber then return end

    local members = {}
    for i, m in ipairs(data.members) do
        if i > Config.Messages.MaxGroupMembers then break end
        table.insert(members, tostring(m))
    end
    if not table.contains(members, ownerNumber) then table.insert(members, ownerNumber) end

    MySQL.insert('INSERT INTO `apexphone_groups` (`name`,`owner`,`members`) VALUES (?,?,?)',
        { data.name:sub(1, 50), ownerNumber, json.encode(members) })
end)

RegisterNetEvent('apexphone:server:sendGroupMessage', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data or not data.groupId or not data.message then return end

    local fromNumber = GetPlayerNumber(cid)
    if not fromNumber then return end

    local groups = MySQL.query.await('SELECT * FROM `apexphone_groups` WHERE `id` = ? LIMIT 1', { tonumber(data.groupId) })
    local group  = groups and groups[1]
    if not group then return end

    local members = json.decode(group.members)
    local isMember = false
    for _, m in ipairs(members) do if m == fromNumber then isMember = true break end end
    if not isMember then return end  -- security: only members can send

    local message   = tostring(data.message):sub(1, 500)
    local threadId  = 'group_' .. data.groupId

    MySQL.insert('INSERT INTO `apexphone_messages` (`thread_id`,`from_number`,`to_number`,`message`,`type`,`media`) VALUES (?,?,?,?,?,?)',
        { threadId, fromNumber, 'group_' .. data.groupId, message, 'group', data.media and json.encode(data.media) or nil })

    for _, memberNumber in ipairs(members) do
        if memberNumber ~= fromNumber then
            local targetSrc = GetSourceByNumber(memberNumber)
            if targetSrc then
                TriggerClientEvent('apexphone:client:pushNotification', targetSrc, {
                    title   = group.name,
                    message = GetPlayerName(src) .. ': ' .. message:sub(1, 50),
                    type    = 'message',
                    number  = threadId,
                })
            end
        end
    end
end)

RegisterNetEvent('apexphone:server:shareContact', function(targetServerId, contactNumber)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    local targetSrc = tonumber(targetServerId)
    if not targetSrc or not GetPlayer(targetSrc) then return end

    -- Validate proximity
    local pSrc    = GetEntityCoords(GetPlayerPed(src))
    local pTarget = GetEntityCoords(GetPlayerPed(targetSrc))
    if #(pSrc - pTarget) > Config.Messages.AirShareRadius then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'AirShare', message = 'Player is too far away.', type = 'error' })
        return
    end

    -- Find contact details
    local contacts = MySQL.query.await('SELECT * FROM `apexphone_contacts` WHERE `citizenid` = ? AND `number` = ? LIMIT 1', { cid, contactNumber })
    local contact  = contacts and contacts[1]
    if not contact then return end

    TriggerClientEvent('apexphone:client:pushNotification', targetSrc, {
        title   = 'Contact Received',
        message = contact.name .. ' (' .. contact.number .. ')',
        type    = 'contact',
        contact = { name = contact.name, number = contact.number, avatar = contact.avatar },
    })
end)

-- ──────────────────────────────────────────────────────────────
--  Contacts
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:saveContact', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data then return end

    -- Upsert: if number already exists for this citizen, update name
    local existing = MySQL.query.await('SELECT id FROM `apexphone_contacts` WHERE `citizenid` = ? AND `number` = ? LIMIT 1', { cid, data.number })
    if existing and existing[1] then
        MySQL.query('UPDATE `apexphone_contacts` SET `name` = ?, `avatar` = ? WHERE `id` = ?',
            { data.name, data.avatar, existing[1].id })
    else
        MySQL.insert('INSERT INTO `apexphone_contacts` (`citizenid`,`name`,`number`,`avatar`) VALUES (?,?,?,?)',
            { cid, data.name, data.number, data.avatar })
    end
end)

RegisterNetEvent('apexphone:server:deleteContact', function(id)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not id then return end
    -- Ensure the contact belongs to this player
    MySQL.query('DELETE FROM `apexphone_contacts` WHERE `id` = ? AND `citizenid` = ?', { id, cid })
end)

-- ──────────────────────────────────────────────────────────────
--  Banking
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:bankTransfer', function(data)
    local src = source
    local p   = GetPlayer(src)
    if not p or not data then return end

    local amount = tonumber(data.amount)
    if not amount or amount <= 0 or amount > p.PlayerData.money.bank then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Transfer Failed', message = 'Insufficient funds.', type = 'error' })
        return
    end

    local fee = math.floor(amount * Config.Banking.TransferFee)
    local net = amount - fee

    -- Find target by number or citizenid
    local target = tostring(data.target)
    local targetCid = nil
    local simRows = MySQL.query.await('SELECT `citizenid` FROM `apexphone_sims` WHERE `number` = ? AND `active` = 1 LIMIT 1', { target })
    if simRows and simRows[1] then
        targetCid = simRows[1].citizenid
    else
        -- Try direct citizenid lookup
        local phoneRows = MySQL.query.await('SELECT `citizenid` FROM `apexphone_phones` WHERE `citizenid` = ? LIMIT 1', { target })
        if phoneRows and phoneRows[1] then targetCid = phoneRows[1].citizenid end
    end

    if not targetCid then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Transfer Failed', message = 'Recipient not found.', type = 'error' })
        return
    end

    p.Functions.RemoveMoney('bank', amount, 'apexphone-transfer')

    local targetOnline = QBCore.Functions.GetPlayerByCitizenId(targetCid)
    if targetOnline then
        targetOnline.Functions.AddMoney('bank', net, 'apexphone-transfer')
    else
        -- Offline transfer via DB
        MySQL.query('UPDATE `players` SET `money` = JSON_SET(money, "$.bank", JSON_EXTRACT(money, "$.bank") + ?) WHERE `citizenid` = ?', { net, targetCid })
    end

    if Config.Admin.LogTransactions then
        AdminLog('BANK_TRANSFER', p.PlayerData.citizenid, p.PlayerData.citizenid .. ' → ' .. targetCid .. ' $' .. amount)
    end

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Transfer Sent', message = '$' .. net .. ' sent.', type = 'success' })

    local targetSrc = QBCore.Functions.GetPlayerByCitizenId(targetCid)
    if targetSrc then
        TriggerClientEvent('apexphone:client:pushNotification', targetSrc.PlayerData.source, {
            title = 'Money Received', message = '$' .. net .. ' received.', type = 'success'
        })
    end
end)

RegisterNetEvent('apexphone:server:payInvoice', function(invoiceId)
    local src = source
    local p   = GetPlayer(src)
    local cid = p and p.PlayerData.citizenid
    if not cid or not invoiceId then return end

    local invoices = MySQL.query.await('SELECT * FROM `apexphone_invoices` WHERE `id` = ? AND `to_citizenid` = ? AND `paid` = 0 LIMIT 1', { invoiceId, cid })
    local invoice  = invoices and invoices[1]
    if not invoice then return end

    if p.PlayerData.money.bank < invoice.amount then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Invoice Failed', message = 'Insufficient funds.', type = 'error' })
        return
    end

    p.Functions.RemoveMoney('bank', invoice.amount, 'invoice-payment')
    MySQL.query('UPDATE `apexphone_invoices` SET `paid` = 1 WHERE `id` = ?', { invoiceId })

    local from = QBCore.Functions.GetPlayerByCitizenId(invoice.from_citizenid)
    if from then
        from.Functions.AddMoney('bank', invoice.amount, 'invoice-received')
        TriggerClientEvent('apexphone:client:pushNotification', from.PlayerData.source, {
            title = 'Invoice Paid', message = '$' .. invoice.amount .. ' received.', type = 'success'
        })
    else
        MySQL.query('UPDATE `players` SET `money` = JSON_SET(money, "$.bank", JSON_EXTRACT(money, "$.bank") + ?) WHERE `citizenid` = ?', { invoice.amount, invoice.from_citizenid })
    end

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Invoice Paid', message = '$' .. invoice.amount .. ' paid.', type = 'success' })
end)

-- ──────────────────────────────────────────────────────────────
--  Crypto exchange
-- ──────────────────────────────────────────────────────────────

-- In-memory price cache (updated by tick)
local CryptoPrices = {}

local function LoadCryptoPrices()
    local rows = MySQL.query.await('SELECT * FROM `apexphone_crypto_prices`')
    if rows then
        for _, r in ipairs(rows) do
            CryptoPrices[r.coin] = r.price
        end
    end
end

--- Periodic price fluctuation tick.
function StartCryptoPriceTick()
    LoadCryptoPrices()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Config.Crypto.UpdateInterval * 1000)

            local playerCount = #QBCore.Functions.GetPlayers()
            local maxPlayers  = GetConvarInt('sv_maxclients', 64)
            local busyness    = playerCount / math.max(maxPlayers, 1)

            for _, coin in ipairs(Config.Crypto.Coins) do
                local current = CryptoPrices[coin.id] or coin.basePrice
                local rnd     = (math.random() * 2 - 1) * Config.Crypto.VolatilityFactor
                local serverEffect = (busyness - 0.5) * Config.Crypto.ServerBusynessWeight
                local change  = current * (rnd + serverEffect)
                local newPrice = math.max(1, current + change)
                CryptoPrices[coin.id] = newPrice
                MySQL.query('UPDATE `apexphone_crypto_prices` SET `price` = ? WHERE `coin` = ?', { newPrice, coin.id })
            end

            -- Broadcast updated prices to all players with phone open
            local prices = {}
            for k, v in pairs(CryptoPrices) do table.insert(prices, { coin = k, price = v }) end
            TriggerClientEvent('apexphone:client:cryptoPriceUpdate', -1, prices)
        end
    end)
end

RegisterNetEvent('apexphone:server:buyCrypto', function(data)
    local src = source
    local p   = GetPlayer(src)
    local cid = p and p.PlayerData.citizenid
    if not cid or not data or not data.coin or not data.amount then return end

    local price  = CryptoPrices[data.coin]
    if not price then return end

    local amount = tonumber(data.amount)
    if not amount or amount <= 0 then return end

    local cost = math.ceil(price * amount)
    if p.PlayerData.money.bank < cost then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Crypto', message = 'Insufficient funds.', type = 'error' })
        return
    end

    p.Functions.RemoveMoney('bank', cost, 'crypto-buy')
    MySQL.query([[
        INSERT INTO `apexphone_crypto` (`citizenid`,`coin`,`amount`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `amount` = `amount` + ?
    ]], { cid, data.coin, amount, amount })

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Crypto Bought', message = amount .. ' ' .. data.coin .. ' for $' .. cost, type = 'success' })
end)

RegisterNetEvent('apexphone:server:sellCrypto', function(data)
    local src = source
    local p   = GetPlayer(src)
    local cid = p and p.PlayerData.citizenid
    if not cid or not data or not data.coin or not data.amount then return end

    local amount = tonumber(data.amount)
    if not amount or amount <= 0 then return end

    local holding = MySQL.query.await('SELECT `amount` FROM `apexphone_crypto` WHERE `citizenid` = ? AND `coin` = ?', { cid, data.coin })
    if not holding or not holding[1] or holding[1].amount < amount then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Crypto', message = 'Insufficient holdings.', type = 'error' })
        return
    end

    local price   = CryptoPrices[data.coin] or 0
    local revenue = math.floor(price * amount)

    p.Functions.AddMoney('bank', revenue, 'crypto-sell')
    MySQL.query('UPDATE `apexphone_crypto` SET `amount` = `amount` - ? WHERE `citizenid` = ? AND `coin` = ?', { amount, cid, data.coin })

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Crypto Sold', message = amount .. ' ' .. data.coin .. ' for $' .. revenue, type = 'success' })
end)

-- ──────────────────────────────────────────────────────────────
--  Social Media
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:postSocial', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data or not data.app or not data.content then return end

    local displayName = GetPlayerName(src)

    MySQL.insert('INSERT INTO `apexphone_social` (`app`,`citizenid`,`display_name`,`content`,`media`) VALUES (?,?,?,?,?)',
        { data.app, cid, displayName, data.content, data.media and json.encode(data.media) or nil })

    -- Broadcast to all online players (they pull it next time they open the app)
    TriggerClientEvent('apexphone:client:newSocialPost', -1, {
        app     = data.app,
        name    = displayName,
        content = data.content,
        media   = data.media,
        time    = os.date('%Y-%m-%d %H:%M:%S'),
    })
end)

RegisterNetEvent('apexphone:server:likeSocialPost', function(postId, app)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not postId then return end

    local rows = MySQL.query.await('SELECT `liked_by`,`likes` FROM `apexphone_social` WHERE `id` = ?', { postId })
    if not rows or not rows[1] then return end

    local liked = json.decode(rows[1].liked_by or '[]')
    for _, v in ipairs(liked) do if v == cid then return end end  -- already liked

    table.insert(liked, cid)
    MySQL.query('UPDATE `apexphone_social` SET `likes` = `likes` + 1, `liked_by` = ? WHERE `id` = ?',
        { json.encode(liked), postId })
end)

RegisterNetEvent('apexphone:server:deleteSocialPost', function(postId, app)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not postId then return end
    -- Only owner or admin can delete
    if IsAdmin(src) then
        MySQL.query('DELETE FROM `apexphone_social` WHERE `id` = ?', { postId })
    else
        MySQL.query('DELETE FROM `apexphone_social` WHERE `id` = ? AND `citizenid` = ?', { postId, cid })
    end
end)

-- ──────────────────────────────────────────────────────────────
--  Photo gallery
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:savePhoto', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data or not data.data then return end

    MySQL.insert('INSERT INTO `apexphone_gallery` (`citizenid`,`data`,`caption`) VALUES (?,?,?)',
        { cid, data.data, data.caption })
end)

RegisterNetEvent('apexphone:server:deletePhoto', function(id)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not id then return end
    MySQL.query('DELETE FROM `apexphone_gallery` WHERE `id` = ? AND `citizenid` = ?', { id, cid })
end)

-- ──────────────────────────────────────────────────────────────
--  Marketplace
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:createListing', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data then return end

    local count = MySQL.query.await('SELECT COUNT(*) AS c FROM `apexphone_marketplace` WHERE `citizenid` = ? AND `active` = 1', { cid })
    if count and count[1] and count[1].c >= Config.Marketplace.MaxListings then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Marketplace', message = 'Max listings reached.', type = 'error' })
        return
    end

    local sellerNumber = GetPlayerNumber(cid) or 'unknown'
    local price = math.max(1, math.min(tonumber(data.price) or 0, Config.Marketplace.MaxPrice))
    local expires = os.date('%Y-%m-%d %H:%M:%S', os.time() + Config.Marketplace.ListingDuration)

    MySQL.insert('INSERT INTO `apexphone_marketplace` (`citizenid`,`seller_number`,`title`,`description`,`price`,`category`,`images`,`expires_at`) VALUES (?,?,?,?,?,?,?,?)',
        { cid, sellerNumber, data.title, data.description, price, data.category, data.images and json.encode(data.images) or nil, expires })
end)

RegisterNetEvent('apexphone:server:deleteListing', function(id)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not id then return end
    MySQL.query('UPDATE `apexphone_marketplace` SET `active` = 0 WHERE `id` = ? AND `citizenid` = ?', { id, cid })
end)

-- ──────────────────────────────────────────────────────────────
--  Dark Web
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:darkWebBuy', function(listingId)
    local src = source
    local p   = GetPlayer(src)
    local cid = p and p.PlayerData.citizenid
    if not cid or not listingId then return end

    local rows = MySQL.query.await('SELECT * FROM `apexphone_dark_listings` WHERE `id` = ? AND `active` = 1 LIMIT 1', { listingId })
    local listing = rows and rows[1]
    if not listing then return end

    if p.PlayerData.money.cash < listing.price then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Dark Web', message = 'Not enough cash.', type = 'error' })
        return
    end

    p.Functions.RemoveMoney('cash', listing.price, 'darkweb-buy')
    p.Functions.AddItem(listing.item_name, 1)

    MySQL.query('UPDATE `apexphone_dark_listings` SET `active` = 0 WHERE `id` = ?', { listingId })
    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Dark Web', message = listing.item_label .. ' purchased.', type = 'success' })
    AdminLog('DARKWEB_BUY', cid, listing.item_name .. ' $' .. listing.price)
end)

RegisterNetEvent('apexphone:server:darkWebSell', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data or not data.itemName or not data.price then return end

    local found = false
    for _, allowed in ipairs(Config.DarkWeb.BlacklistItems) do
        if allowed.item == data.itemName then found = true break end
    end
    if not found then return end  -- not a listed item

    local p = GetPlayer(src)
    if not p or not p.Functions.HasItem(data.itemName) then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Dark Web', message = 'You don\'t have that item.', type = 'error' })
        return
    end

    local price = math.max(1, math.min(tonumber(data.price) or 0, 1000000))
    local fee   = math.floor(price * Config.DarkWeb.ListingFee)
    local net   = price - fee

    if p.PlayerData.money.cash < fee then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Dark Web', message = 'Need $' .. fee .. ' listing fee.', type = 'error' })
        return
    end

    p.Functions.RemoveMoney('cash', fee, 'darkweb-fee')
    p.Functions.RemoveItem(data.itemName, 1)

    local expires = os.date('%Y-%m-%d %H:%M:%S', os.time() + Config.DarkWeb.ListingDuration)
    local anonId  = 'anon_' .. cid:sub(-6)

    local label = data.itemName
    for _, i in ipairs(Config.DarkWeb.BlacklistItems) do if i.item == data.itemName then label = i.label break end end

    MySQL.insert('INSERT INTO `apexphone_dark_listings` (`seller_anon`,`item_name`,`item_label`,`price`,`expires_at`) VALUES (?,?,?,?,?)',
        { anonId, data.itemName, label, price, expires })

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Dark Web', message = 'Listing posted.', type = 'success' })
end)

RegisterNetEvent('apexphone:server:sendDarkChat', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data or not data.to or not data.message then return end

    local anonFrom = 'anon_' .. cid:sub(-6)
    MySQL.insert('INSERT INTO `apexphone_dark_chat` (`from_anon`,`to_anon`,`message`) VALUES (?,?,?)',
        { anonFrom, data.to, data.message })

    -- Attempt to deliver if recipient online
    local players = QBCore.Functions.GetPlayers()
    for _, psrc in ipairs(players) do
        local pcid = GetCitizenId(psrc)
        if pcid then
            local panonId = 'anon_' .. pcid:sub(-6)
            if panonId == data.to then
                TriggerClientEvent('apexphone:client:appData', psrc, 'darkChat', {
                    from    = anonFrom,
                    message = data.message,
                    time    = os.date('%Y-%m-%d %H:%M:%S'),
                })
                break
            end
        end
    end
end)

-- Periodic cleanup of expired dark chat messages
function StartDarkChatCleanup()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(3600 * 1000) -- every hour
            MySQL.query('DELETE FROM `apexphone_dark_chat` WHERE TIMESTAMPDIFF(SECOND, `created_at`, NOW()) > ?',
                { Config.DarkWeb.DarkChatDeleteAfter })
        end
    end)
end

-- ──────────────────────────────────────────────────────────────
--  IMEI clone minigame
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:requestIMEIClone', function()
    local src = source
    local p   = GetPlayer(src)
    local cid = p and p.PlayerData.citizenid
    if not cid then return end

    if p.PlayerData.money.cash < Config.IMEI.CloneCost then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Dark Web', message = 'Need $' .. Config.IMEI.CloneCost .. ' to clone IMEI.', type = 'error' })
        return
    end

    p.Functions.RemoveMoney('cash', Config.IMEI.CloneCost, 'imei-clone-fee')
    TriggerClientEvent('apexphone:client:startIMEIClone', src)
end)

RegisterNetEvent('apexphone:server:imeiCloneResult', function(success)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    if success then
        local phones = GetPhoneRecord(cid)
        local phone  = phones and phones[1]
        if not phone then return end

        local newIMEI
        repeat
            newIMEI = GenerateIMEI()
        until not MySQL.query.await('SELECT id FROM `apexphone_phones` WHERE `imei` = ?', { newIMEI })[1]

        MySQL.query('UPDATE `apexphone_phones` SET `imei` = ?, `imei_flagged` = 0 WHERE `citizenid` = ?', { newIMEI, cid })
        LogIMEI(newIMEI, cid, 'cloned')
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'IMEI Cloned', message = 'New IMEI: ' .. newIMEI, type = 'success' })
        AdminLog('IMEI_CLONED', cid, 'Old:' .. phone.imei .. ' New:' .. newIMEI)
    else
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'IMEI Clone', message = 'Minigame failed. IMEI unchanged.', type = 'error' })
    end
end)

-- ──────────────────────────────────────────────────────────────
--  GPS share
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:startGPSShare', function(targetNumber)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not targetNumber then return end

    local fromNumber = GetPlayerNumber(cid)
    if not fromNumber then return end

    MySQL.query([[
        INSERT INTO `apexphone_gps_shares` (`from_number`,`to_number`,`active`) VALUES (?,?,1)
        ON DUPLICATE KEY UPDATE `active` = 1
    ]], { fromNumber, targetNumber })
end)

RegisterNetEvent('apexphone:server:stopGPSShare', function()
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end
    local number = GetPlayerNumber(cid)
    if number then
        MySQL.query('UPDATE `apexphone_gps_shares` SET `active` = 0 WHERE `from_number` = ?', { number })
    end
end)

RegisterNetEvent('apexphone:server:updateGPSShare', function(x, y, z)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end
    local number = GetPlayerNumber(cid)
    if not number then return end

    MySQL.query('UPDATE `apexphone_gps_shares` SET `x` = ?, `y` = ?, `z` = ? WHERE `from_number` = ? AND `active` = 1',
        { x, y, z, number })

    -- Push to all recipients who are online
    local recipients = MySQL.query.await('SELECT `to_number` FROM `apexphone_gps_shares` WHERE `from_number` = ? AND `active` = 1', { number })
    if recipients then
        local name = GetPlayerName(src)
        for _, r in ipairs(recipients) do
            local targetSrc = GetSourceByNumber(r.to_number)
            if targetSrc then
                TriggerClientEvent('apexphone:client:receiveLiveLocation', targetSrc, number, name, x, y, z)
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────────
--  Remote lock / wipe / find
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:remoteLock', function(targetNumber)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not targetNumber then return end

    -- Verify this player owns the target phone (or is admin)
    local myNumber = GetPlayerNumber(cid)
    if myNumber ~= targetNumber and not IsAdmin(src) then return end

    MySQL.query('UPDATE `apexphone_phones` SET `locked` = 1 WHERE `citizenid` = (SELECT `citizenid` FROM `apexphone_sims` WHERE `number` = ? LIMIT 1)', { targetNumber })

    local targetSrc = GetSourceByNumber(targetNumber)
    if targetSrc then
        TriggerClientEvent('apexphone:client:remoteLock', targetSrc)
    end
end)

RegisterNetEvent('apexphone:server:remoteWipe', function(targetNumber)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not targetNumber then return end

    local myNumber = GetPlayerNumber(cid)
    if myNumber ~= targetNumber and not IsAdmin(src) then return end

    local simRows = MySQL.query.await('SELECT `citizenid` FROM `apexphone_sims` WHERE `number` = ? LIMIT 1', { targetNumber })
    local targetCid = simRows and simRows[1] and simRows[1].citizenid
    if not targetCid then return end

    -- Wipe data
    MySQL.query('DELETE FROM `apexphone_contacts` WHERE `citizenid` = ?', { targetCid })
    MySQL.query('DELETE FROM `apexphone_gallery` WHERE `citizenid` = ?', { targetCid })
    MySQL.query('UPDATE `apexphone_phones` SET `metadata` = NULL, `pin` = NULL WHERE `citizenid` = ?', { targetCid })

    local targetSrc = GetSourceByNumber(targetNumber)
    if targetSrc then TriggerClientEvent('apexphone:client:remoteLock', targetSrc) end

    AdminLog('REMOTE_WIPE', cid, 'Wiped: ' .. targetNumber)
end)

RegisterNetEvent('apexphone:server:findMyPhoneResponse', function(requesterId, x, y, z)
    local src = source
    -- Forward location to requester
    TriggerClientEvent('apexphone:client:appData', tonumber(requesterId), 'findMyPhone', { x = x, y = y, z = z })
end)

-- ──────────────────────────────────────────────────────────────
--  MDT (police)
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:mdtLookupIMEI', function(imei)
    local src = source
    if not IsPoliceOrAdmin(src) then return end

    local phones = MySQL.query.await('SELECT * FROM `apexphone_phones` WHERE `imei` = ? LIMIT 1', { imei })
    local history = MySQL.query.await('SELECT * FROM `apexphone_imei_history` WHERE `imei` = ? ORDER BY `created_at` DESC LIMIT 20', { imei })

    TriggerClientEvent('apexphone:client:appData', src, 'mdtIMEIResult', {
        phone   = phones and phones[1],
        history = history,
    })
end)

RegisterNetEvent('apexphone:server:mdtFlagIMEI', function(imei, reason)
    local src = source
    if not IsPoliceOrAdmin(src) then return end
    local cid = GetCitizenId(src)

    MySQL.query('UPDATE `apexphone_phones` SET `imei_flagged` = 1 WHERE `imei` = ?', { imei })
    LogIMEI(imei, cid, 'flagged: ' .. (reason or 'no reason'))
    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'MDT', message = 'IMEI ' .. imei .. ' flagged.', type = 'success' })
end)

-- ──────────────────────────────────────────────────────────────
--  Data transfer (phone-to-phone)
-- ──────────────────────────────────────────────────────────────

local pendingTransfers = {}

RegisterNetEvent('apexphone:server:initiateDataTransfer', function(targetServerId)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    local targetSrc = tonumber(targetServerId)
    if not targetSrc or not GetPlayer(targetSrc) then return end

    -- Proximity check
    local pSrc    = GetEntityCoords(GetPlayerPed(src))
    local pTarget = GetEntityCoords(GetPlayerPed(targetSrc))
    if #(pSrc - pTarget) > Config.DataTransfer.ProximityMax then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Transfer', message = 'Too far away.', type = 'error' })
        return
    end

    local transferId = 'transfer_' .. GetGameTimer()
    pendingTransfers[transferId] = { from = src, to = targetSrc, fromCid = cid, accepted = false }

    local fromName   = GetPlayerName(src)
    local fromNumber = GetPlayerNumber(cid) or '???'
    TriggerClientEvent('apexphone:client:dataTransferRequest', targetSrc, fromName, fromNumber, transferId)
end)

RegisterNetEvent('apexphone:server:acceptDataTransfer', function(transferId)
    local src = source
    local transfer = pendingTransfers[transferId]
    if not transfer or transfer.to ~= src then return end
    if transfer.accepted then return end
    transfer.accepted = true

    local duration = math.random(Config.DataTransfer.MinDuration, Config.DataTransfer.MaxDuration)

    -- Simulate progress updates
    Citizen.CreateThread(function()
        for i = 1, duration do
            Citizen.Wait(1000)
            local pct = math.floor((i / duration) * 100)
            TriggerClientEvent('apexphone:client:dataTransferProgress', transfer.from, transferId, pct)
            TriggerClientEvent('apexphone:client:dataTransferProgress', transfer.to,   transferId, pct)
        end

        -- Perform actual data copy
        local fromCid = transfer.fromCid
        local toCid   = GetCitizenId(transfer.to)
        if toCid then
            -- Copy contacts
            local contacts = MySQL.query.await('SELECT * FROM `apexphone_contacts` WHERE `citizenid` = ?', { fromCid })
            for _, c in ipairs(contacts or {}) do
                MySQL.query([[
                    INSERT IGNORE INTO `apexphone_contacts` (`citizenid`,`name`,`number`,`avatar`) VALUES (?,?,?,?)
                ]], { toCid, c.name, c.number, c.avatar })
            end
            -- Copy gallery
            local photos = MySQL.query.await('SELECT * FROM `apexphone_gallery` WHERE `citizenid` = ?', { fromCid })
            for _, ph in ipairs(photos or {}) do
                MySQL.insert('INSERT INTO `apexphone_gallery` (`citizenid`,`data`,`caption`) VALUES (?,?,?)',
                    { toCid, ph.data, ph.caption })
            end
        end

        TriggerClientEvent('apexphone:client:dataTransferComplete', transfer.from, transferId)
        TriggerClientEvent('apexphone:client:dataTransferComplete', transfer.to, transferId)
        pendingTransfers[transferId] = nil
    end)
end)

-- ──────────────────────────────────────────────────────────────
--  Cloud backup
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:cloudBackup', function()
    local src = source
    local p   = GetPlayer(src)
    local cid = p and p.PlayerData.citizenid
    if not cid then return end

    if p.PlayerData.money.bank < Config.DataTransfer.CloudBackupPrice then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Cloud Backup', message = 'Insufficient funds.', type = 'error' })
        return
    end

    p.Functions.RemoveMoney('bank', Config.DataTransfer.CloudBackupPrice, 'cloud-backup')

    local contacts = MySQL.query.await('SELECT * FROM `apexphone_contacts` WHERE `citizenid` = ?', { cid })
    local photos   = MySQL.query.await('SELECT `id`,`caption`,`created_at` FROM `apexphone_gallery` WHERE `citizenid` = ?', { cid })

    local backup = json.encode({ contacts = contacts, photos = photos, ts = os.time() })
    MySQL.query([[
        INSERT INTO `apexphone_cloud_backup` (`citizenid`,`backup_data`) VALUES (?,?)
        ON DUPLICATE KEY UPDATE `backup_data` = VALUES(`backup_data`)
    ]], { cid, backup })

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Cloud Backup', message = 'Backup saved.', type = 'success' })
end)

RegisterNetEvent('apexphone:server:cloudRestore', function()
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end

    local rows = MySQL.query.await('SELECT * FROM `apexphone_cloud_backup` WHERE `citizenid` = ? LIMIT 1', { cid })
    local row  = rows and rows[1]
    if not row then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Cloud Restore', message = 'No backup found.', type = 'error' })
        return
    end

    local data = json.decode(row.backup_data)
    if not data then return end

    for _, c in ipairs(data.contacts or {}) do
        MySQL.query([[
            INSERT IGNORE INTO `apexphone_contacts` (`citizenid`,`name`,`number`,`avatar`) VALUES (?,?,?,?)
        ]], { cid, c.name, c.number, c.avatar })
    end

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Cloud Restore', message = 'Data restored.', type = 'success' })
end)

-- ──────────────────────────────────────────────────────────────
--  Email
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:sendEmail', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data then return end

    local fromNumber = GetPlayerNumber(cid) or 'unknown'

    -- Find recipient by number or name (basic lookup)
    local simRows = MySQL.query.await('SELECT `citizenid` FROM `apexphone_sims` WHERE `number` = ? AND `active` = 1 LIMIT 1', { data.to })
    local targetCid = simRows and simRows[1] and simRows[1].citizenid

    if not targetCid then
        TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Email', message = 'Recipient not found.', type = 'error' })
        return
    end

    MySQL.insert('INSERT INTO `apexphone_emails` (`to_citizenid`,`from_number`,`subject`,`body`,`attachment`) VALUES (?,?,?,?,?)',
        { targetCid, fromNumber, data.subject, data.body, data.attachment and json.encode(data.attachment) or nil })

    local targetSrc = QBCore.Functions.GetPlayerByCitizenId(targetCid)
    if targetSrc then
        TriggerClientEvent('apexphone:client:pushNotification', targetSrc.PlayerData.source, {
            title   = 'New Email',
            message = data.subject,
            type    = 'email',
        })
    end

    TriggerClientEvent('apexphone:client:pushNotification', src, { title = 'Email Sent', message = data.subject, type = 'success' })
end)

-- ──────────────────────────────────────────────────────────────
--  Settings save
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:saveSettings', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data then return end

    local updates = {}
    local params  = {}

    if data.theme then
        updates[#updates+1] = '`theme` = ?'
        table.insert(params, data.theme:sub(1, 50))
    end
    if data.wallpaper then
        updates[#updates+1] = '`wallpaper` = ?'
        table.insert(params, data.wallpaper:sub(1, 100))
    end
    if data.ringtone then
        updates[#updates+1] = '`ringtone` = ?'
        table.insert(params, data.ringtone:sub(1, 100))
    end
    if data.pin then
        updates[#updates+1] = '`pin` = ?'
        table.insert(params, data.pin:sub(1, 6))
    end
    if data.duressPin then
        updates[#updates+1] = '`duress_pin` = ?'
        table.insert(params, data.duressPin:sub(1, 6))
    end

    if #updates == 0 then return end
    table.insert(params, cid)
    MySQL.query('UPDATE `apexphone_phones` SET ' .. table.concat(updates, ', ') .. ' WHERE `citizenid` = ?', params)
end)

-- ──────────────────────────────────────────────────────────────
--  Phone damage
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:phoneDamaged', function(reason)
    local src = source
    local cid = GetCitizenId(src)
    if not cid then return end
    MySQL.query('UPDATE `apexphone_phones` SET `cracked` = 1 WHERE `citizenid` = ?', { cid })
end)

-- ──────────────────────────────────────────────────────────────
--  Rides (Uber-style)
-- ──────────────────────────────────────────────────────────────

RegisterNetEvent('apexphone:server:requestRide', function(data)
    local src = source
    local cid = GetCitizenId(src)
    if not cid or not data then return end

    local rideId = MySQL.insert.await([[
        INSERT INTO `apexphone_rides` (`passenger_citizenid`,`pickup_x`,`pickup_y`,`pickup_z`,`dest`,`note`)
        VALUES (?,?,?,?,?,?)
    ]], { cid, data.pickup.x, data.pickup.y, data.pickup.z, data.dest, data.note })

    -- Broadcast to all online taxi-job players
    local players = QBCore.Functions.GetPlayers()
    for _, psrc in ipairs(players) do
        local pp = GetPlayer(psrc)
        if pp and pp.PlayerData.job.name == 'taxi' then
            TriggerClientEvent('apexphone:client:pushNotification', psrc, {
                title   = 'New Ride Request',
                message = 'Pickup nearby. Ride #' .. rideId,
                type    = 'ride',
                rideId  = rideId,
            })
        end
    end
end)

RegisterNetEvent('apexphone:server:acceptRide', function(rideId)
    local src = source
    local p   = GetPlayer(src)
    if not p or p.PlayerData.job.name ~= 'taxi' then return end

    MySQL.query('UPDATE `apexphone_rides` SET `driver_citizenid` = ?, `status` = "accepted" WHERE `id` = ? AND `status` = "pending"',
        { p.PlayerData.citizenid, rideId })

    local rides = MySQL.query.await('SELECT `passenger_citizenid` FROM `apexphone_rides` WHERE `id` = ? LIMIT 1', { rideId })
    local ride  = rides and rides[1]
    if ride then
        local passengerOnline = QBCore.Functions.GetPlayerByCitizenId(ride.passenger_citizenid)
        if passengerOnline then
            TriggerClientEvent('apexphone:client:pushNotification', passengerOnline.PlayerData.source, {
                title   = 'Ride Accepted',
                message = GetPlayerName(src) .. ' is on the way.',
                type    = 'ride',
            })
        end
    end
end)

-- ──────────────────────────────────────────────────────────────
--  Marketplace cleanup (expired listings)
-- ──────────────────────────────────────────────────────────────

function StartMarketplaceCleanup()
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(3600 * 1000)
            MySQL.query('UPDATE `apexphone_marketplace` SET `active` = 0 WHERE `expires_at` < NOW()')
            MySQL.query('UPDATE `apexphone_dark_listings` SET `active` = 0 WHERE `expires_at` < NOW()')
        end
    end)
end

-- ──────────────────────────────────────────────────────────────
--  Utility: admin / police check
-- ──────────────────────────────────────────────────────────────

function IsAdmin(src)
    local p = GetPlayer(src)
    if not p then return false end
    for _, g in ipairs(Config.Admin.Groups) do
        if QBCore.Functions.GetPermission(src, g) then return true end
    end
    return false
end

function IsPoliceOrAdmin(src)
    local p = GetPlayer(src)
    if not p then return false end
    return p.PlayerData.job.name == 'police' or IsAdmin(src)
end

--- Alerts all online police players with a message.
function AlertPolice(src, cid, message)
    local players = QBCore.Functions.GetPlayers()
    for _, psrc in ipairs(players) do
        local pp = GetPlayer(psrc)
        if pp and pp.PlayerData.job.name == Config.DarkWeb.DuressAlertJob then
            TriggerClientEvent('apexphone:client:pushNotification', psrc, {
                title   = '🚨 DURESS ALERT',
                message = message .. ' (CID: ' .. cid .. ')',
                type    = 'alert',
            })
        end
    end
end

-- table.contains helper
function table.contains(t, val)
    for _, v in ipairs(t) do if v == val then return true end end
    return false
end

-- ──────────────────────────────────────────────────────────────
--  Server-side exports for other resources
-- ──────────────────────────────────────────────────────────────

exports('GetPlayerNumber',  GetPlayerNumber)
exports('GetSourceByNumber', GetSourceByNumber)
exports('CreatePhone',      CreatePhone)
exports('CreateSIM',        CreateSIM)
exports('IsAdmin',          IsAdmin)
exports('AlertPolice',      AlertPolice)

--- Lets other resources push a notification to a player's phone.
exports('PushNotification', function(source, data)
    TriggerClientEvent('apexphone:client:pushNotification', source, data)
end)

--- Lets other resources send an in-game invoice.
exports('SendInvoice', function(fromCid, toCid, amount, note)
    local due = os.date('%Y-%m-%d %H:%M:%S', os.time() + (Config.Banking.InvoiceDueDays * 86400))
    MySQL.insert('INSERT INTO `apexphone_invoices` (`from_citizenid`,`to_citizenid`,`amount`,`note`,`due_at`) VALUES (?,?,?,?,?)',
        { fromCid, toCid, amount, note, due })
    local target = QBCore.Functions.GetPlayerByCitizenId(toCid)
    if target then
        TriggerClientEvent('apexphone:client:pushNotification', target.PlayerData.source, {
            title   = 'New Invoice',
            message = '$' .. amount .. ' — ' .. (note or ''),
            type    = 'invoice',
        })
    end
end)
