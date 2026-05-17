-- ============================================================
--  ApexPhone — config.lua
--  All tunable parameters. Change here; never hardcode in logic.
-- ============================================================

Config = {}

-- ── Framework ────────────────────────────────────────────────
Config.Framework   = 'qbcore'   -- 'qbcore' | 'esx'
Config.VoiceScript = 'pma-voice' -- 'pma-voice' | 'mumble-voip' | 'none'

-- ── Item names (must match your inventory resource) ──────────
Config.Items = {
    -- Phone models
    PhoneFlagship  = 'phone_flagship',   -- iPhone-style flagship
    PhoneSamsung   = 'phone_samsung',    -- Android flagship
    PhoneBurner    = 'phone_burner',     -- Untraceable burner
    -- Accessories
    SimCard        = 'sim_card',
    Charger        = 'phone_charger',
    PhoneCase      = 'phone_case',
    -- Temporary / shop receipts
    PhoneBox       = 'phone_box',
}

-- ── Phone model capabilities ─────────────────────────────────
Config.PhoneModels = {
    phone_flagship = {
        label           = 'ApexPhone Pro',
        fingerprint     = true,
        camera          = true,
        darkweb         = true,
        batteryCapacity = 100,
        batteryDrain    = 0.005,  -- % per second while open
        maxStorage      = 512,    -- MB (cosmetic, for UI display)
    },
    phone_samsung = {
        label           = 'Galaxy X',
        fingerprint     = true,
        camera          = true,
        darkweb         = true,
        batteryCapacity = 100,
        batteryDrain    = 0.006,
        maxStorage      = 256,
    },
    phone_burner = {
        label           = 'BurnerPhone',
        fingerprint     = false,
        camera          = false,
        darkweb         = true,   -- burners ARE useful on dark web
        batteryCapacity = 60,
        batteryDrain    = 0.01,
        maxStorage      = 32,
    },
}

-- ── Battery ──────────────────────────────────────────────────
Config.Battery = {
    SaveInterval    = 60,        -- seconds between DB battery saves
    LowWarning      = 15,        -- % — show low battery notification
    CriticalWarning = 5,         -- % — red pulse warning
    DrainWhileClosed = 0.001,    -- % per second while phone is closed
    ChargeRate       = 0.5,      -- % per second near charger / station
    ChargingZones   = {          -- world coords of charging stations
        vector3(224.8, -792.8, 30.7),
        vector3(-47.5, -1757.3, 29.4),
        vector3(372.9, 325.5, 103.6),
    },
    ChargingRadius  = 2.5,       -- metres
}

-- ── SIM Card ─────────────────────────────────────────────────
Config.SIM = {
    NumberLength    = 9,          -- digits in generated number
    NumberPrefix    = '555',      -- first 3 digits (cosmetic)
    BlackMarketItem = 'sim_card_burner',
    BlackMarketPrice = 500,       -- $
}

-- ── IMEI ─────────────────────────────────────────────────────
Config.IMEI = {
    Length       = 15,
    CloneMinigameDuration = 30,   -- seconds
    CloneCost    = 2500,          -- $ dark web fee
}

-- ── Security ─────────────────────────────────────────────────
Config.Security = {
    PINLength      = 4,
    MaxPINAttempts = 3,
    LockoutDuration = 300,        -- seconds (5 min)
    DuressPIN      = true,        -- enable duress PIN feature
    DuressAction   = 'wipe',      -- 'wipe' | 'alert_only' | 'both'
    FingerprintAnimDuration = 2000, -- ms NUI animation
}

-- ── Signal zones ─────────────────────────────────────────────
-- signal: 0 = no signal, 1 = weak, 2 = normal, 3 = full
Config.SignalZones = {
    { coords = vector3(135.0, 3700.0, 41.0),  radius = 150, signal = 0 },  -- Alamo bunker
    { coords = vector3(1857.0, 3693.0, 34.0), radius = 80,  signal = 1 },  -- Chumash tunnel
    { coords = vector3(-361.0, 6011.0, 31.0), radius = 200, signal = 0 },  -- Sandy caves
    -- Add custom zones below
}
Config.DefaultSignal  = 3   -- signal when not in any zone
Config.AirplaneMode   = false -- global default (runtime flag)

-- ── Voice calls ──────────────────────────────────────────────
Config.Calls = {
    MaxCallDuration    = 3600,    -- seconds, 0 = unlimited
    SpeakerRadius      = 5.0,     -- metres — nearby players hear speaker
    VoicemailMaxLength = 60,      -- seconds
    RingTimeout        = 30,      -- seconds before call goes to voicemail
    CallHistoryLimit   = 50,
    VoiceChannel       = 'phone', -- pma-voice channel name
}

-- ── Messaging ────────────────────────────────────────────────
Config.Messages = {
    MaxPerThread       = 200,
    MaxGroupMembers    = 10,
    MMSImageSizeLimit  = 5,       -- MB (cosmetic, enforced in JS)
    AirShareRadius     = 5.0,     -- metres for proximity contact share
}

-- ── Banking ──────────────────────────────────────────────────
Config.Banking = {
    TransactionHistoryLimit = 100,
    TransferFee             = 0.0, -- fraction (0.02 = 2 %)
    InvoiceDueDays          = 7,
    MaxInvoiceAmount        = 1000000,
}

-- ── Crypto ───────────────────────────────────────────────────
Config.Crypto = {
    Coins = {
        { id = 'APC',  name = 'ApexCoin',   basePrice = 500  },
        { id = 'BTC',  name = 'BitCoin',    basePrice = 30000 },
        { id = 'ETH',  name = 'EtherCoin',  basePrice = 2000 },
        { id = 'XMR',  name = 'MoneroCoin', basePrice = 150  },
    },
    UpdateInterval    = 120,      -- seconds between price ticks
    VolatilityFactor  = 0.08,     -- max % swing per tick
    ServerBusynessWeight = 0.3,   -- how much player count influences price
}

-- ── Social Media ─────────────────────────────────────────────
Config.Social = {
    Catiter = {
        PostMaxLength   = 280,
        TrendingWindow  = 3600,   -- 1 hour
        ServerAnnounceRole = 'admin', -- QBCore job that can post server announcements
    },
    InstaPic = {
        MaxPhotosPerPost = 4,
        LiveStreamRadius = 50.0,
    },
    FlirtDate = {
        MaxDistance = 200.0,      -- metres — show nearby profiles
        SuperLikeCooldown = 86400,
    },
    VideoHub = {
        MaxVideoDuration = 120,   -- seconds (cosmetic)
    },
}

-- ── Dark Web ─────────────────────────────────────────────────
Config.DarkWeb = {
    Enabled          = true,
    BlacklistItems   = {          -- items tradeable on dark market
        { item = 'weapon_pistol',    price = 2500, label = 'Pistol'   },
        { item = 'ammo_pistol',      price = 50,   label = 'Ammo 9mm' },
        { item = 'lockpick',         price = 300,  label = 'Lockpick' },
        { item = 'drug_weed',        price = 150,  label = 'Weed'     },
        { item = 'drug_cocaine',     price = 800,  label = 'Cocaine'  },
    },
    ListingFee       = 0.05,      -- fraction of sale price
    ListingDuration  = 86400,     -- seconds a listing lives
    DarkChatDeleteAfter = 3600,   -- seconds — messages auto-delete
    DuressAlertJob   = 'police',  -- job that receives duress PIN alerts
}

-- ── GPS / Navigation ─────────────────────────────────────────
Config.GPS = {
    ShareUpdateInterval = 5,      -- seconds between shared-location updates
    TrackerUpdateInterval = 10,
    MaxTrackers         = 3,      -- max vehicles tracked simultaneously
}

-- ── Marketplace ──────────────────────────────────────────────
Config.Marketplace = {
    Categories = { 'Vehicles', 'Electronics', 'Weapons', 'Clothing', 'Real Estate', 'Other' },
    MaxListings = 5,              -- per player
    ListingDuration = 604800,     -- 7 days
    MaxPrice        = 10000000,
    ImageUploadAllowed = true,
}

-- ── Garage ───────────────────────────────────────────────────
Config.Garage = {
    Resource = 'qb-garages',      -- garage resource to trigger
    MaxVehiclesShown = 20,
}

-- ── Admin ────────────────────────────────────────────────────
Config.Admin = {
    Groups = { 'god', 'admin', 'mod' },
    LogAllMessages = true,
    LogAllCalls    = true,
    LogTransactions = true,
}

-- ── Notifications (NUI toast) ────────────────────────────────
Config.Notifications = {
    Duration       = 5000,        -- ms
    MaxVisible     = 3,
    Position       = 'top-right', -- 'top-right' | 'top-left' | 'bottom-right'
}

-- ── Minigames ────────────────────────────────────────────────
Config.Minigames = {
    IMEICloneDifficulty = 3,      -- 1-5
    HackAttemptWindow   = 10,     -- seconds to complete keypad
}

-- ── Data Transfer ────────────────────────────────────────────
Config.DataTransfer = {
    MinDuration  = 10,            -- seconds
    MaxDuration  = 30,
    ProximityMax = 3.0,           -- metres
    CloudBackupPrice = 1000,      -- $ per backup
}

-- ── UI / Theme defaults ──────────────────────────────────────
Config.UI = {
    DefaultTheme   = 'dark',      -- 'dark' | 'light'
    DefaultWallpaper = 'default',
    DefaultRingtone  = 'default',
    AnimationSpeed   = 'normal',  -- 'slow' | 'normal' | 'fast'
    DynamicIsland    = true,
}

-- ── Keybind ──────────────────────────────────────────────────
Config.OpenKey = 'F1'             -- RegisterKeyMapping key
