local W = Warden

local function reply(src, text)
    if src == 0 then return print(text) end
    TriggerClientEvent('chat:addMessage', src, { color = { 245, 165, 36 }, multiline = true, args = { 'warden', text } })
end

local usage = [[warden status
warden strikes <id>
warden allow <id> <check|all> <seconds>
warden bans [name]
warden unban <ban id>
warden test <on|off>]]

local sub = {}

function sub.status(src)
    local n = 0
    for _ in pairs(W.players) do n = n + 1 end
    reply(src, ('%d players watched · %d local bans · test mode %s · bans and logs through %s'):format(
        n, #W.bans.list, Config.testMode and 'on' or 'off', W.fivecord() and 'fivecord' or 'warden'))
end

function sub.strikes(src, id)
    local p = W.players[tonumber(id)]
    if not p then return reply(src, 'No player with that id.') end
    local out = {}
    for kind, hits in pairs(p.strikes) do
        if #hits > 0 then out[#out + 1] = ('%s: %d'):format(kind, #hits) end
    end
    table.sort(out)
    reply(src, #out > 0 and table.concat(out, '\n') or 'No strikes.')
end

function sub.allow(src, id, kind, seconds)
    id, seconds = tonumber(id), tonumber(seconds)
    if not id or not kind or not seconds or not W.players[id] then return reply(src, 'warden allow <id> <check|all> <seconds>') end
    W.allow(id, kind, seconds)
    reply(src, ('%s is not checked for %s for %ds.'):format(GetPlayerName(id), kind, seconds))
end

function sub.bans(src, search)
    local out = {}
    for i = #W.bans.list, 1, -1 do
        local b = W.bans.list[i]
        if not search or b.name:lower():find(search:lower(), 1, true) then
            out[#out + 1] = ('#%d %s · %s · %s'):format(b.id, b.name, b.reason, os.date('%Y-%m-%d', b.created))
            if #out == 15 then break end
        end
    end
    reply(src, #out > 0 and table.concat(out, '\n') or 'No bans.')
end

function sub.unban(src, id)
    local b = W.bans.remove(tonumber(id))
    if not b then return reply(src, 'No ban with that id.') end
    local by = src == 0 and 'console' or GetPlayerName(src)
    W.log('Unbanned', ('Ban **#%d** on **%s** lifted by **%s**'):format(b.id, b.name, by), 0x30A46C)
    reply(src, ('Lifted ban #%d on %s.'):format(b.id, b.name))
end

function sub.test(src, state)
    if state ~= 'on' and state ~= 'off' then return reply(src, 'warden test <on|off>') end
    Config.testMode = state == 'on'
    reply(src, ('Test mode %s until the next restart.'):format(state))
end

RegisterCommand('warden', function(src, args)
    local fn = sub[args[1] or '']
    if not fn then return reply(src, usage) end
    fn(src, table.unpack(args, 2))
end, true)

exports('allow', W.allow)
exports('flag', function(src, kind, detail) W.flag(src, kind, detail) end)
exports('getStrikes', function(src)
    local p = W.players[tonumber(src)]
    local out = {}
    for kind, hits in pairs(p and p.strikes or {}) do out[kind] = #hits end
    return out
end)
exports('isBanned', function(identifier)
    return W.bans.find({ identifier }, {}) ~= nil
end)

-- Players already on the server when the resource starts.
for _, id in ipairs(GetPlayers()) do
    local p = W.player(id)
    if p then p.joined = W.now() - Config.limits.joinGrace end
end
