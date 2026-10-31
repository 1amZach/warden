local cfg, on

local function flag(kind, detail)
    TriggerServerEvent('warden:flag', kind, detail)
end

RegisterNetEvent('warden:ping', function(nonce)
    TriggerServerEvent('warden:pong', nonce)
end)

RegisterNetEvent('warden:setup', function(settings, enabled)
    cfg, on = settings, enabled
end)

local function resources()
    local list = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and GetResourceState(name) == 'started' then list[#list + 1] = name end
    end
    return list
end

AddEventHandler('onClientResourceStart', function(name)
    TriggerServerEvent('warden:resources', { name })
end)

CreateThread(function()
    TriggerServerEvent('warden:ready')
    TriggerServerEvent('warden:resources', resources())
end)

-- Something the game or a script is doing on purpose, where the checks below
-- would only get it wrong.
local function busy(ped)
    return IsPlayerSwitchInProgress() or IsCutsceneActive() or not IsScreenFadedIn()
        or IsEntityDead(ped) or IsEntityPositionFrozen(ped) or not NetworkIsPlayerActive(PlayerId())
end

local since = {}
local function sustained(key, active, seconds)
    if not active then
        since[key] = nil
        return false
    end
    since[key] = since[key] or GetGameTimer()
    if GetGameTimer() - since[key] >= seconds * 1000 then
        since[key] = GetGameTimer()
        return true
    end
    return false
end

local hovering = 0

local function check()
    local ped, player = PlayerPedId(), PlayerId()
    if busy(ped) then
        since, hovering = {}, 0
        return
    end

    if on.godmode then
        local god = GetPlayerInvincible(player) or GetPlayerInvincible_2(player) or not GetEntityCanBeDamaged(ped)
        if sustained('god', god, cfg.godmodeSeconds) then flag('godmode', ('Invincible for %ds'):format(cfg.godmodeSeconds)) end
    end

    if on.damageModifier then
        local weapon, meleeMod = GetPlayerWeaponDamageModifier(player), GetPlayerMeleeWeaponDamageModifier(player)
        local top = math.max(weapon, meleeMod)
        if top > cfg.maxDamageModifier + 0.01 then flag('damageModifier', ('Weapon %.2f, melee %.2f'):format(weapon, meleeMod)) end
    end

    if on.spectate and NetworkIsInSpectatorMode() then flag('spectate') end

    if on.invisible and sustained('invisible', not IsEntityVisible(ped), cfg.invisibleSeconds) then
        flag('invisible', ('Invisible for %ds'):format(cfg.invisibleSeconds))
    end

    local inVehicle = IsPedInAnyVehicle(ped, false)

    if on.noclip and not inVehicle then
        local vz = GetEntityVelocity(ped).z
        local floating = GetEntityHeightAboveGround(ped) > cfg.noclipHeight
            and not IsPedFalling(ped) and not IsPedInParachuteFreeFall(ped) and GetPedParachuteState(ped) < 1
            and not IsPedClimbing(ped) and not IsPedSwimming(ped) and not IsEntityAttached(ped)
            and math.abs(vz) < 1.0
        hovering = floating and hovering + 1 or 0
        local ghost = sustained('collision', GetEntityCollisionDisabled(ped) and not IsEntityAttached(ped), 10)
        if hovering >= 3 or ghost then
            hovering = 0
            flag('noclip', ('%.0fm above the ground'):format(GetEntityHeightAboveGround(ped)))
        end
    end

    if on.superJump and IsPedJumping(ped) then
        local vz = GetEntityVelocity(ped).z
        if vz > cfg.superJumpSpeed then flag('superJump', ('Jumped at %.0f m/s'):format(vz)) end
    end

    if on.freecam then
        local dist = #(GetFinalRenderedCamCoord() - GetEntityCoords(ped))
        if sustained('freecam', dist > cfg.freecamDistance, 5) then flag('freecam', ('Camera %.0fm away'):format(dist)) end
    end

    if on.vision and (GetUsingnightvision() or GetUsingseethrough()) then
        flag('vision', GetUsingseethrough() and 'Thermal' or 'Night vision')
    end
end

local function commands()
    if not on.blockedCommand or #cfg.blockedCommands == 0 then return end
    local blocked = {}
    for _, name in ipairs(cfg.blockedCommands) do blocked[name:lower()] = true end
    for _, c in ipairs(GetRegisteredCommands()) do
        if blocked[c.name:lower()] then return flag('blockedCommand', c.name) end
    end
end

CreateThread(function()
    while not cfg do Wait(500) end
    local n = 0
    while true do
        Wait(2000)
        check()
        n = n + 1
        if n % 15 == 0 then commands() end
    end
end)
