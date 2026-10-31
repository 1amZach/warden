Warden = {}
local W = Warden

function W.now()
    return GetGameTimer() / 1000
end

-- Hashes come back signed from some natives and unsigned from event data.
function W.u32(n)
    return (math.tointeger(n) or 0) & 0xFFFFFFFF
end

function W.hashSet(list)
    local set = {}
    for _, v in ipairs(list or {}) do
        set[W.u32(type(v) == 'string' and GetHashKey(v) or v)] = v
    end
    return set
end

W.labels = {
    honeypot = 'Triggered a fake event',
    blockedExplosion = 'Blocked explosion',
    invisibleExplosion = 'Invisible explosion',
    explosionSpam = 'Explosion spam',
    blockedModel = 'Spawned a blocked model',
    entitySpam = 'Entity spam',
    giveWeapon = 'Gave weapons to another player',
    removeWeapon = 'Removed another player\'s weapons',
    clearTasks = 'Cleared another player\'s tasks',
    particleSpam = 'Particle spam',
    projectileSpam = 'Projectile spam',
    meleeRange = 'Melee hit from too far away',
    blockedWeapon = 'Blocked weapon',
    health = 'Health above max',
    armour = 'Armour above max',
    invincible = 'Invincible',
    teleport = 'Teleported',
    speed = 'Moving too fast on foot',
    heartbeat = 'Anticheat stopped responding',
    injection = 'Unknown resource on client',
    godmode = 'Godmode',
    damageModifier = 'Damage modifier',
    spectate = 'Spectating',
    invisible = 'Invisible',
    noclip = 'Noclip',
    superJump = 'Super jump',
    freecam = 'Freecam',
    vision = 'Night or thermal vision',
    blockedCommand = 'Cheat menu command',
    exploit = 'Script exploit',
}

W.players = {}

function W.player(src)
    src = tonumber(src)
    if not src or src <= 0 then return end
    local p = W.players[src]
    if not p and GetPlayerName(src) then
        p = { joined = W.now(), strikes = {}, allowed = {}, rates = {}, logged = {} }
        W.players[src] = p
    end
    return p
end

AddEventHandler('playerJoining', function()
    W.player(source)
end)

AddEventHandler('playerDropped', function()
    W.players[tonumber(source)] = nil
end)

-- Staff, players already being removed, and anything a resource allowed.
function W.exempt(src, kind)
    local p = W.player(src)
    if not p or p.gone then return true end
    if IsPlayerAceAllowed(src, Config.bypassAce) then return true end
    local t = W.now()
    return (p.allowed[kind] or 0) > t or (p.allowed.all or 0) > t
end

function W.allow(src, kind, seconds)
    local p = W.player(src)
    if p then p.allowed[kind or 'all'] = W.now() + (tonumber(seconds) or 10) end
end

-- True once more than `count` things happened within `seconds`.
function W.over(src, key, limit)
    local p = W.player(src)
    if not p then return false end
    local t, r = W.now(), p.rates[key]
    if not r or t - r.start >= limit.seconds then
        r = { start = t, n = 0 }
        p.rates[key] = r
    end
    r.n = r.n + 1
    return r.n > limit.count
end

function W.identity(src)
    local ids, out = {}, { name = GetPlayerName(src) or ('#' .. src), tokens = {} }
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and not id:find('^ip:') then
            ids[#ids + 1] = id
            local kind = id:match('^(%w+):')
            if kind and not out[kind] then out[kind] = id end
        end
    end
    for i = 0, GetNumPlayerTokens(src) - 1 do
        out.tokens[#out.tokens + 1] = GetPlayerToken(src, i)
    end
    out.identifiers = ids
    return out
end

function W.fivecord()
    return Config.useFivecord and GetResourceState('fivecord') == 'started'
end

-- A detection happened. Counts it and decides what to do.
function W.flag(src, kind, detail)
    src = tonumber(src)
    local rule = Config.detections[kind]
    if not rule or not rule.action or W.exempt(src, kind) then return end

    local p, t = W.player(src), W.now()
    local window, kept = rule.window or 60, {}
    for _, at in ipairs(p.strikes[kind] or {}) do
        if t - at < window then kept[#kept + 1] = at end
    end
    kept[#kept + 1] = t
    p.strikes[kind] = kept

    local count, needed = #kept, rule.strikes or 1
    local action = count >= needed and rule.action or 'log'
    TriggerEvent('warden:detected', src, kind, detail, action)

    if action ~= 'log' and not Config.testMode then
        return W.punish(src, action, kind, detail)
    end
    W.report(src, kind, detail, count, needed, action ~= 'log' and action or nil)
end
