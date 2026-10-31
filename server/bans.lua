-- Local bans, used when fivecord isn't running.

local W = Warden
local resource = GetCurrentResourceName()

local Bans = { list = {}, nextId = 1 }
W.bans = Bans

local function save()
    local data = json.encode({ nextId = Bans.nextId, bans = Bans.list })
    SaveResourceFile(resource, 'bans.json', data, #data)
end

function Bans.load()
    local raw = LoadResourceFile(resource, 'bans.json')
    local ok, data = pcall(json.decode, raw or '')
    if ok and type(data) == 'table' then
        Bans.list = data.bans or {}
        Bans.nextId = data.nextId or (#Bans.list + 1)
    end
end

local function active(b)
    return not b.expires or b.expires > os.time()
end

function Bans.add(ids, reason, detail)
    local b = {
        id = Bans.nextId,
        name = ids.name,
        identifiers = ids.identifiers,
        tokens = ids.tokens,
        reason = reason,
        detail = detail,
        created = os.time(),
        expires = Config.banLength > 0 and os.time() + Config.banLength or nil,
    }
    Bans.nextId = Bans.nextId + 1
    Bans.list[#Bans.list + 1] = b
    save()
    return b
end

function Bans.remove(id)
    for i, b in ipairs(Bans.list) do
        if b.id == id then
            table.remove(Bans.list, i)
            save()
            return b
        end
    end
end

-- Returns the ban and whether it matched on something the ban didn't have yet,
-- like a new account on the same PC.
function Bans.find(identifiers, tokens)
    local ids, toks = {}, {}
    for _, v in ipairs(identifiers) do ids[v] = true end
    for _, v in ipairs(tokens) do toks[v] = true end

    for _, b in ipairs(Bans.list) do
        if active(b) then
            local idHit, tokenHit = false, false
            for _, v in ipairs(b.identifiers) do if ids[v] then idHit = true break end end
            for _, v in ipairs(b.tokens) do if toks[v] then tokenHit = true break end end
            if idHit or tokenHit then
                local license
                for _, v in ipairs(identifiers) do if v:find('^license:') then license = v end end
                local known = false
                for _, v in ipairs(b.identifiers) do if v == license then known = true end end
                return b, not known
            end
        end
    end
end

-- Remember the new account so it stays banned even from another PC.
function Bans.extend(b, identifiers, tokens)
    local have = {}
    for _, v in ipairs(b.identifiers) do have[v] = true end
    for _, v in ipairs(b.tokens) do have[v] = true end
    for _, v in ipairs(identifiers) do if not have[v] then b.identifiers[#b.identifiers + 1] = v end end
    for _, v in ipairs(tokens) do if not have[v] then b.tokens[#b.tokens + 1] = v end end
    save()
end

function W.banMessage(b)
    local ends = b.expires and ('until ' .. os.date('%Y-%m-%d %H:%M', b.expires)) or 'permanently'
    return ('You are banned %s by the anticheat.\nBan #%d · Appeal at %s'):format(ends, b.id, Config.appeal)
end

AddEventHandler('playerConnecting', function(_, setKickReason)
    local src = source
    local ids = W.identity(src)
    local b, evading = Bans.find(ids.identifiers, ids.tokens)
    if not b then return end

    if evading then
        Bans.extend(b, ids.identifiers, ids.tokens)
        W.log('Ban evasion', ('%s tried to join on a new account.\nMatches ban **#%d** on **%s**'):format(W.describe(src, ids), b.id, b.name), W.colors.ban)
    end

    setKickReason(W.banMessage(b))
    CancelEvent()
end)

Bans.load()
