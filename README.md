# warden

A FiveM anticheat that does most of its work on the server, where a cheat can't reach it. It watches the game events every client sends (explosions, spawned entities, weapons, damage, particles) and checks each player's ped once a second, then catches the rest with a heartbeat and a handful of client checks.

No dependencies. Works with any framework, or none.

## Features

**Server side.** These can't be switched off by a cheat.

- Blocked explosion types, invisible explosions and explosion spam are cancelled before anyone sees them
- Spawn limits for peds, vehicles and objects, and a blocklist of models like tanks, jets and troll props
- Giving or taking another player's weapons, or clearing their tasks (the vehicle kick), is cancelled
- Melee hits from too far away
- Particle and projectile spam
- Blocked weapons are taken away the moment they're held, and hits with them are cancelled
- Health above max, armour above max, staying invincible
- Teleports and running too fast on foot
- Honeypots: fake money and admin events that cheat menus go looking for

**Heartbeat.** The server checks in with every client every 15 seconds with a new code. A client that stops answering, answers wrong, or never starts the anticheat is caught. Resources running on the client that the server has never heard of are caught too.

**Client checks** for godmode, damage modifiers, spectating, invisibility, noclip, super jump, freecam, night and thermal vision, and known cheat menu commands. Their settings are sent from the server when a player connects, so they never sit in a file a cheater can read.

**Strikes.** Each detection has its own action (ban, kick or log) and how many times it has to happen before the action is taken. Below that it's only logged, so one laggy moment won't get anyone banned.

**Test mode** logs what would have happened without kicking or banning anyone. Turn it on for the first few days and tune from the logs.

**Bans** cover the player's identifiers and hardware tokens. Someone who comes back on a new account from the same PC is refused, and the new account is added to the ban.

**Screenshots** of the player's screen are attached to every kick and ban when screenshot-basic is running.

Repeat detections are folded into one log line every 10 seconds, so a spamming cheat can't flood your log channel.

## Install

Needs OneSync, which is on by default on current servers.

1. Drop `warden` into your resources and start it in `server.cfg`:

   ```
   ensure warden
   ```

2. Let staff skip the checks, see detections in chat and use the command:

   ```
   add_ace group.admin warden.bypass allow
   add_ace group.admin warden.notify allow
   add_ace group.admin command.warden allow
   ```

3. For logs without fivecord, add a Discord webhook:

   ```
   set warden_webhook "https://discord.com/api/webhooks/..."
   ```

4. Go through `config.lua`. Most important: make sure none of the honeypot events are real events on your server, and take any vehicles you sell off the blocked model list.

## Detections

Defaults are shown. Change them in `Config.detections`.

| Check | | Default |
|---|---|---|
| `honeypot` | Triggered one of the fake events | ban |
| `blockedExplosion` | Explosion type on the blocklist | ban on the 2nd |
| `invisibleExplosion` | Explosion with no visual | kick on the 2nd |
| `explosionSpam` | Over 6 explosions in 10s | ban on the 10th |
| `blockedModel` | Spawned something on the blocklist | kick on the 2nd |
| `entitySpam` | Over the spawn limits | kick on the 10th |
| `giveWeapon` | Gave another player a weapon | ban on the 2nd |
| `removeWeapon` | Took another player's weapons | kick on the 2nd |
| `clearTasks` | Cleared another player's tasks | kick on the 2nd |
| `particleSpam` | Too many or too large particle effects | kick on the 5th |
| `projectileSpam` | Too many projectiles | log |
| `meleeRange` | Punched or stabbed someone from over 10m | kick on the 3rd |
| `blockedWeapon` | Held or used a blocked weapon | ban on the 2nd |
| `health` | Health above max | kick on the 3rd |
| `armour` | Armour above max | kick on the 3rd |
| `invincible` | Invincible for 30s | log |
| `teleport` | Moved over 300m in a second | log |
| `speed` | Over 20 m/s on foot for 3 seconds | log |
| `heartbeat` | Client stopped answering | kick |
| `injection` | Unknown resource on the client | ban |
| `godmode` | Can't be damaged for 20s | kick on the 3rd |
| `damageModifier` | Weapon or melee damage boosted | ban on the 2nd |
| `spectate` | In spectator mode | kick on the 2nd |
| `invisible` | Invisible for 10s | log |
| `noclip` | Floating with no fall, or no collision | kick on the 3rd |
| `superJump` | Jumped far too high | kick on the 2nd |
| `freecam` | Camera far from the player | log |
| `vision` | Night or thermal vision | off |
| `blockedCommand` | A command from `Config.client.blockedCommands` | ban |
| `exploit` | Another resource caught something only a cheat could do, like [fiveheists](https://github.com/1amZach/fiveheists) loot claimed from across the map | log |

Teleports and speed only log by default, because spawn selectors, apartments and elevators all teleport. If your scripts call `allow` before they move a player, you can turn these up.

## Commands

Needs `command.warden`. Works from the server console too.

| Command | |
|---|---|
| `warden status` | Players watched, local bans, test mode |
| `warden strikes <id>` | A player's current strikes |
| `warden allow <id> <check\|all> <seconds>` | Skip a check for a player for a while |
| `warden bans [name]` | Recent local bans |
| `warden unban <ban id>` | Lift a local ban |
| `warden test <on\|off>` | Test mode until the next restart |

## Exports

```lua
-- Before your script teleports someone, makes them invincible, and so on.
exports.warden:allow(source, 'teleport', 10)
exports.warden:allow(source, 'all', 5)

-- Report something your own script noticed. `kind` is one of the checks above.
exports.warden:flag(source, 'speed', 'Outran a police car on foot')

exports.warden:getStrikes(source) -- { teleport = 1, ... }
exports.warden:isBanned('license:...')
```

```lua
exports.warden:getBans() -- local bans, newest first
exports.warden:unban(id, 'Zach')
```

Every detection fires an event on the server, and every kick or ban another one with the screenshot:

```lua
AddEventHandler('warden:detected', function(source, kind, detail, action) end)
AddEventHandler('warden:punished', function(source, action, kind, detail, name, license, image) end)
```

## Addons

- [fivecord](https://github.com/1amZach/fivecord): when it's running, warden bans through it and logs to its `anticheat` channel with the screenshot. Bans then show up in `/bans` and `/lookup`, and fivecord's `/teleport` tells warden the move was on purpose. warden works the same without it.
- [fiveadmin](https://github.com/1amZach/fiveadmin): an in-game admin menu. It tells warden before staff noclip, spectate, teleport or spawn things, so they never get flagged.
- [fivepanel](https://github.com/1amZach/fivepanel): a web admin panel with a live feed of detections, their screenshots, and one-click bans.
- [fivelog](https://github.com/1amZach/fivelog): kick and ban logs show the player's last few actions before it happened, like kills, damage and items. Set how many with `Config.history`.

## Testing

```
lua5.4 test/run.lua
```

Runs the server side against a fake FiveM server.

## Support

Made by **IamZach**. Questions, bugs or ideas: [discord.gg/agn](https://discord.gg/agn)

## License

MIT
