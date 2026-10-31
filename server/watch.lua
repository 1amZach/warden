-- Once a second, look at every player's ped from the server's side.

local W = Warden
local L = Config.limits

local function check(src, p, t)
    local ped = GetPlayerPed(src)
    if ped == 0 then return end

    local weapon = W.u32(GetSelectedPedWeapon(ped))
    if W.blockedWeapons[weapon] and not W.exempt(src, 'blockedWeapon') then
        RemoveWeaponFromPed(ped, weapon)
        W.flag(src, 'blockedWeapon', 'Holding ' .. W.blockedWeapons[weapon])
    end

    local health, max = GetEntityHealth(ped), GetEntityMaxHealth(ped)
    if max > 0 and health > max then
        W.flag(src, 'health', ('%d health, max is %d'):format(health, max))
    end

    local armour = GetPedArmour(ped)
    if armour > L.maxArmour then
        W.flag(src, 'armour', ('%d armour'):format(armour))
    end

    if GetPlayerInvincible(src) then
        p.invincibleSince = p.invincibleSince or t
        if t - p.invincibleSince >= L.invincibleSeconds then
            W.flag(src, 'invincible', ('Invincible for %ds'):format(math.floor(t - p.invincibleSince)))
            p.invincibleSince = t
        end
    else
        p.invincibleSince = nil
    end

    local pos, last, lastAt = GetEntityCoords(ped), p.pos, p.posAt
    p.pos, p.posAt = pos, t
    if not last or t - p.joined < L.joinGrace or W.exempt(src, 'teleport') then
        p.fast = 0
        return
    end

    local dt = math.max(t - lastAt, 0.5)
    local dx, dy = pos.x - last.x, pos.y - last.y
    local flat = math.sqrt(dx * dx + dy * dy)

    if flat > L.teleportDistance then
        p.fast = 0
        return W.flag(src, 'teleport', ('Moved %.0fm in %.1fs'):format(flat, dt))
    end

    local onFoot = GetVehiclePedIsIn(ped, false) == 0 and GetEntityAttachedTo(ped) == 0
    if onFoot and flat / dt > L.footSpeed and math.abs(pos.z - last.z) / dt < 3 then
        p.fast = (p.fast or 0) + 1
        if p.fast >= 3 then
            p.fast = 0
            W.flag(src, 'speed', ('%.0f m/s on foot'):format(flat / dt))
        end
    else
        p.fast = 0
    end
end

function W.watch()
    local t = W.now()
    for src, p in pairs(W.players) do
        if not p.gone and GetPlayerName(src) then check(src, p, t) end
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        W.watch()
    end
end)
