Config = {}

-- Players with this ace are never checked. Give it to staff:
--   add_ace group.admin warden.bypass allow
Config.bypassAce = 'warden.bypass'

-- Players with this ace see detections in chat.
Config.notifyAce = 'warden.notify'

-- Everything is logged but nobody is kicked or banned. Turn this on for the
-- first few days on a new server, read the logs, then tune the rules below.
Config.testMode = false

-- Bans and logs go through fivecord when it's running. Otherwise bans are kept
-- in bans.json and logs go to a webhook set in server.cfg:
--   set warden_webhook "https://discord.com/api/webhooks/..."
Config.useFivecord = true

-- Seconds, 0 for permanent.
Config.banLength = 0
Config.appeal = 'discord.gg/yourserver'
Config.kickMessage = 'You were kicked by the anticheat. If you think this is a mistake, contact staff.'

-- Grab the player's screen before a kick or ban. Needs screenshot-basic.
Config.screenshots = true

-- With fivelog running, kick and ban logs show this many of the player's last
-- logged actions, like kills, damage and items. 0 for none.
Config.history = 5

-- What each detection does.
--   action   'ban', 'kick', 'log', or false to turn it off
--   strikes  how many times it has to happen within `window` seconds before
--            the action is taken. Until then it is only logged.
Config.detections = {
    -- Game events. These are checked on the server, so a cheat can't hide them.
    honeypot           = { action = 'ban' },
    blockedExplosion   = { action = 'ban', strikes = 2, window = 30 },
    invisibleExplosion = { action = 'kick', strikes = 2, window = 30 },
    explosionSpam      = { action = 'ban', strikes = 10, window = 30 },
    blockedModel       = { action = 'kick', strikes = 2, window = 60 },
    entitySpam         = { action = 'kick', strikes = 10, window = 30 },
    giveWeapon         = { action = 'ban', strikes = 2, window = 60 },
    removeWeapon       = { action = 'kick', strikes = 2, window = 60 },
    clearTasks         = { action = 'kick', strikes = 2, window = 60 },
    particleSpam       = { action = 'kick', strikes = 5, window = 30 },
    projectileSpam     = { action = 'log' },
    meleeRange         = { action = 'kick', strikes = 3, window = 60 },
    blockedWeapon      = { action = 'ban', strikes = 2, window = 60 },
    health             = { action = 'kick', strikes = 3, window = 30 },
    armour             = { action = 'kick', strikes = 3, window = 30 },
    invincible         = { action = 'log' },
    teleport           = { action = 'log' },
    speed              = { action = 'log' },

    -- The client stopped answering, so the anticheat was likely stopped.
    heartbeat          = { action = 'kick' },
    injection          = { action = 'ban' },

    -- Client checks. A good cheat can fool these, so they're kept gentle.
    godmode            = { action = 'kick', strikes = 3, window = 120 },
    damageModifier     = { action = 'ban', strikes = 2, window = 60 },
    spectate           = { action = 'kick', strikes = 2, window = 60 },
    invisible          = { action = 'log' },
    noclip             = { action = 'kick', strikes = 3, window = 60 },
    superJump          = { action = 'kick', strikes = 2, window = 60 },
    freecam            = { action = 'log' },
    vision             = false,
    blockedCommand     = { action = 'ban' },

    -- Other resources reporting a player, like fiveheists catching loot claimed
    -- from across the map. Logged so you can look before turning it up.
    exploit            = { action = 'log' },
}

-- Fake server events nothing on your server uses. Cheat menus fire events
-- like these looking for free money, so anyone who triggers one is caught.
-- Make sure none of them are real events in your resources.
Config.honeypots = {
    'esx:giveMoneyToPlayer',
    'esx_society:withdrawAll',
    'qb-core:server:addMoney',
    'qb-banking:server:giveAll',
    'admin:server:setGroup',
    'bank:server:depositAll',
    'jobs:server:setPaycheck',
    'police:server:giveAllWeapons',
}

Config.limits = {
    -- Per player, script spawned only. Players' own peds don't count.
    entities = {
        peds = { count = 10, seconds = 10 },
        vehicles = { count = 8, seconds = 10 },
        objects = { count = 60, seconds = 10 },
    },
    explosions = { count = 6, seconds = 10 },
    particles = { count = 15, seconds = 5, maxScale = 5.0 },
    projectiles = { count = 25, seconds = 5 },
    meleeRange = 10.0,
    maxArmour = 100,
    invincibleSeconds = 30,
    teleportDistance = 300.0,
    footSpeed = 20.0, -- m/s on foot, 3 seconds in a row
    joinGrace = 30, -- seconds after joining before movement is checked
}

-- See https://docs.fivem.net/docs/game-references/explosion-types/ for the list.
Config.blockedExplosions = {
    29, -- blimp
    36, -- railgun
    37, -- blimp 2
}

-- Spawning these is blocked. Remove any your server actually uses.
Config.blockedModels = {
    'rhino', 'khanjali', 'apc', 'chernobog', 'minitank',
    'lazer', 'hydra', 'strikeforce', 'starling', 'molotok', 'pyro', 'nokota', 'rogue',
    'hunter', 'savage', 'akula', 'annihilator2', 'valkyrie', 'valkyrie2',
    'oppressor', 'oppressor2', 'deluxo', 'vigilante', 'scramjet', 'ruiner2', 'stromberg', 'thruster',
    'avenger', 'bombushka', 'volatol', 'titan', 'cargoplane', 'blimp', 'blimp2', 'blimp3',
    'prop_windmill_01', 'prop_ld_ferris_wheel', 'p_spinning_anus_s', 'stt_prop_ramp_jump_xxl',
    'prop_container_05a', 'prop_cj_big_boat', 'prop_beach_fire',
}

-- Holding one of these is a detection, and the weapon is taken away.
Config.blockedWeapons = {
    'WEAPON_RAILGUN', 'WEAPON_RAILGUNXM3', 'WEAPON_MINIGUN', 'WEAPON_RAYMINIGUN',
    'WEAPON_RAYPISTOL', 'WEAPON_RAYCARBINE', 'WEAPON_HOMINGLAUNCHER', 'WEAPON_EMPLAUNCHER',
}

Config.heartbeat = {
    interval = 15, -- seconds between checks
    misses = 3, -- unanswered checks in a row before it counts
    grace = 180, -- seconds after joining for the anticheat to start on the client
}

-- Sent to each client when it connects, so the values never sit in a client file.
Config.client = {
    godmodeSeconds = 20,
    invisibleSeconds = 10,
    maxDamageModifier = 1.0,
    noclipHeight = 5.0,
    superJumpSpeed = 10.0,
    freecamDistance = 150.0,
    blockedCommands = {},
}
