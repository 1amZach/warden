-- Game events the client sends to the server. These are the checks a cheat
-- can't switch off, because the server sees them before anyone else does.

local W = Warden
local L = Config.limits

local blockedExplosions = {}
for _, t in ipairs(Config.blockedExplosions) do blockedExplosions[t] = true end

local blockedModels = W.hashSet(Config.blockedModels)
W.blockedWeapons = W.hashSet(Config.blockedWeapons)

local melee = W.hashSet({
    'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_NIGHTSTICK', 'WEAPON_HAMMER', 'WEAPON_BAT', 'WEAPON_GOLFCLUB',
    'WEAPON_CROWBAR', 'WEAPON_BOTTLE', 'WEAPON_DAGGER', 'WEAPON_HATCHET', 'WEAPON_KNUCKLE', 'WEAPON_MACHETE',
    'WEAPON_SWITCHBLADE', 'WEAPON_WRENCH', 'WEAPON_BATTLEAXE', 'WEAPON_POOLCUE', 'WEAPON_STONE_HATCHET',
    'WEAPON_FLASHLIGHT',
})

local entityLimits = { [1] = L.entities.peds, [2] = L.entities.vehicles, [3] = L.entities.objects }
local entityNames = { 'peds', 'vehicles', 'objects' }

for _, name in ipairs(Config.honeypots) do
    RegisterNetEvent(name, function()
        W.flag(source, 'honeypot', name)
    end)
end

AddEventHandler('explosionEvent', function(sender, ev)
    local src = tonumber(sender)
    local kind = ev.explosionType

    if blockedExplosions[kind] and not W.exempt(src, 'blockedExplosion') then
        CancelEvent()
        return W.flag(src, 'blockedExplosion', ('Explosion type %d'):format(kind))
    end

    if ev.isInvisible and not W.exempt(src, 'invisibleExplosion') then
        CancelEvent()
        return W.flag(src, 'invisibleExplosion', ('Explosion type %d'):format(kind))
    end

    if W.over(src, 'explosion', L.explosions) and not W.exempt(src, 'explosionSpam') then
        CancelEvent()
        W.flag(src, 'explosionSpam', ('More than %d explosions in %ds'):format(L.explosions.count, L.explosions.seconds))
    end
end)

AddEventHandler('entityCreating', function(entity)
    local owner = NetworkGetEntityOwner(entity)
    if not owner or owner <= 0 or GetEntityPopulationType(entity) ~= 7 then return end

    local model = W.u32(GetEntityModel(entity))
    if blockedModels[model] and not W.exempt(owner, 'blockedModel') then
        CancelEvent()
        return W.flag(owner, 'blockedModel', blockedModels[model])
    end

    local kind = GetEntityType(entity)
    local limit = entityLimits[kind]
    if not limit or (kind == 1 and IsPedAPlayer(entity)) then return end

    if W.over(owner, 'entity' .. kind, limit) and not W.exempt(owner, 'entitySpam') then
        CancelEvent()
        W.flag(owner, 'entitySpam', ('More than %d %s in %ds'):format(limit.count, entityNames[kind], limit.seconds))
    end
end)

-- Weapon and task events aimed at another player. A script changes your own
-- ped, never someone else's, so these are cancelled.
local function otherPlayer(src, netId)
    local ped = NetworkGetEntityFromNetworkId(netId or 0)
    return ped ~= 0 and ped ~= GetPlayerPed(src) and IsPedAPlayer(ped), ped
end

local function targetName(ped)
    local owner = NetworkGetEntityOwner(ped)
    return owner and GetPlayerName(owner) and ('%s (id %d)'):format(GetPlayerName(owner), owner) or 'another player'
end

AddEventHandler('giveWeaponEvent', function(sender, data)
    local hit, ped = otherPlayer(sender, data.pedId)
    if hit and not W.exempt(sender, 'giveWeapon') then
        CancelEvent()
        W.flag(sender, 'giveWeapon', 'Target: ' .. targetName(ped))
    end
end)

local function removeWeapons(sender, data)
    local hit, ped = otherPlayer(sender, data.pedId)
    if hit and not W.exempt(sender, 'removeWeapon') then
        CancelEvent()
        W.flag(sender, 'removeWeapon', 'Target: ' .. targetName(ped))
    end
end
AddEventHandler('removeWeaponEvent', removeWeapons)
AddEventHandler('removeAllWeaponsEvent', removeWeapons)

AddEventHandler('clearPedTasksEvent', function(sender, data)
    local hit, ped = otherPlayer(sender, data.pedId)
    if hit and not W.exempt(sender, 'clearTasks') then
        CancelEvent()
        W.flag(sender, 'clearTasks', ('Target: %s%s'):format(targetName(ped), data.immediately and ', immediately' or ''))
    end
end)

AddEventHandler('ptFxEvent', function(sender, data)
    if W.exempt(sender, 'particleSpam') then return end
    if (data.scale or 0) > L.particles.maxScale then
        CancelEvent()
        return W.flag(sender, 'particleSpam', ('Effect at scale %.1f'):format(data.scale))
    end
    if W.over(sender, 'ptfx', L.particles) then
        CancelEvent()
        W.flag(sender, 'particleSpam', ('More than %d effects in %ds'):format(L.particles.count, L.particles.seconds))
    end
end)

AddEventHandler('startProjectileEvent', function(sender, data)
    if W.exempt(sender, 'projectileSpam') then return end
    if W.blockedWeapons[W.u32(data.weaponHash)] then
        CancelEvent()
        return W.flag(sender, 'blockedWeapon', 'Fired ' .. W.blockedWeapons[W.u32(data.weaponHash)])
    end
    if W.over(sender, 'projectile', L.projectiles) then
        CancelEvent()
        W.flag(sender, 'projectileSpam', ('More than %d projectiles in %ds'):format(L.projectiles.count, L.projectiles.seconds))
    end
end)

AddEventHandler('weaponDamageEvent', function(sender, data)
    local src = tonumber(sender)
    local weapon = W.u32(data.weaponType)

    if W.blockedWeapons[weapon] and not W.exempt(src, 'blockedWeapon') then
        CancelEvent()
        return W.flag(src, 'blockedWeapon', 'Hit someone with ' .. W.blockedWeapons[weapon])
    end

    if not melee[weapon] then return end
    local target = NetworkGetEntityFromNetworkId(data.hitGlobalId or 0)
    local ped = GetPlayerPed(src)
    if target == 0 or ped == 0 then return end

    local a, b = GetEntityCoords(ped), GetEntityCoords(target)
    local dist = #(a - b)
    if dist > L.meleeRange and not W.exempt(src, 'meleeRange') then
        CancelEvent()
        W.flag(src, 'meleeRange', ('%s from %.0fm'):format(melee[weapon], dist))
    end
end)
