-- The client half: heartbeat, client-side detections and resource checks.

local W = Warden
local H = Config.heartbeat

local clientKinds = {
    godmode = true, damageModifier = true, spectate = true, invisible = true,
    noclip = true, superJump = true, freecam = true, vision = true, blockedCommand = true,
}

local function enabled()
    local on = {}
    for kind in pairs(clientKinds) do
        local rule = Config.detections[kind]
        on[kind] = rule and rule.action and true or false
    end
    return on
end

RegisterNetEvent('warden:ready', function()
    local src = source
    local p = W.player(src)
    if not p or p.ready then return end
    p.ready, p.missed = W.now(), 0
    TriggerClientEvent('warden:setup', src, Config.client, enabled())
end)

RegisterNetEvent('warden:pong', function(nonce)
    local p = W.player(source)
    if not p or not p.nonce then return end
    if nonce ~= p.nonce then
        return W.flag(source, 'heartbeat', 'Answered with the wrong code')
    end
    p.nonce, p.missed = nil, 0
end)

RegisterNetEvent('warden:flag', function(kind, detail)
    local src = source
    if not clientKinds[kind] then return end
    -- Cap how much a client can make us log.
    if W.over(src, 'clientFlags', { count = 20, seconds = 10 }) then return end
    W.flag(src, kind, detail and tostring(detail):sub(1, 200) or nil)
end)

-- Names of resources running on the client. Anything the server has never
-- heard of was put there by something else.
RegisterNetEvent('warden:resources', function(names)
    local src = source
    if type(names) ~= 'table' then return end
    for i = 1, math.min(#names, 2048) do
        local name = names[i]
        if type(name) == 'string' and GetResourceState(name) == 'missing' then
            W.flag(src, 'injection', ('Resource `%s`'):format(name:sub(1, 64)))
            return
        end
    end
end)

function W.heartbeat()
    local t = W.now()
    for src, p in pairs(W.players) do
        if p.gone or not GetPlayerName(src) then goto continue end

        if not p.ready then
            if t - p.joined > H.grace then
                p.ready = t
                W.flag(src, 'heartbeat', ('The anticheat never started on their client after %ds'):format(H.grace))
            end
            goto continue
        end

        if p.nonce then
            p.missed = p.missed + 1
            if p.missed >= H.misses then
                p.missed = 0
                W.flag(src, 'heartbeat', ('No answer for %ds'):format(H.interval * H.misses))
            end
        end

        p.nonce = ('%x%x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
        TriggerClientEvent('warden:ping', src, p.nonce)

        ::continue::
    end
end

CreateThread(function()
    while true do
        Wait(H.interval * 1000)
        W.heartbeat()
    end
end)
