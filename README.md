# STD Hub

Sorcerer Tower Defense multi-box hub. One account is the king, the rest follow
him through portals, into events, and across server hops.

## Files

| file | what it is |
| --- | --- |
| `STD_Hub.luau` | the hub itself, ~430 KB, the only thing that draws a window |
| `STD_Loader.luau` | waits for the server, starts anti-AFK, fetches and runs the hub |
| `autoexec/STD_Hub.luau` | the only file that goes in the executor's autoexec folder |
| `sim/` | offline simulations for the loader's fetch path. not shipped to clients |

## Use

Paste this into the executor console, or save it as the autoexec file:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/OWNER/STD-Hub/main/STD_Loader.luau"))()
```

The loader does three things the hub cannot do for itself:

1. **Waits for the server.** An autoexec script runs the instant the executor
   attaches, long before the server has sent its map. The hub scans towers at
   load time, so loading it during that window produced a hub with zero towers
   that sat there doing nothing.
2. **Starts anti-AFK**, spawned rather than awaited, so a slow fetch never delays
   the hub.
3. **Fetches the hub from here**, with three mirrors and a disk cache. See below.

## The fetch chain

```
raw.githubusercontent  ->  cdn.jsdelivr  ->  fastly.jsdelivr  ->  STD_Hub_cache.luau  ->  hand-copied file
```

`raw.githubusercontent` is canonical but rate-limits a machine doing six
simultaneous joins, which is exactly what a multi-box is. The two jsDelivr edges serve
the same bytes off different CDNs. Every successful fetch is written to
`STD_Hub_cache.luau`, so a join with no internet still runs the last good build
instead of nothing.

A body is checked before it reaches `loadstring`: at least 20 KB, not HTML, not
JSON, and it must contain `STD`. A 429 response is 90 bytes of JSON and a captive
portal is an HTML page; both would otherwise fail inside the hub with a syntax
error naming the wrong cause.

## Updating

Push a new `STD_Hub.luau`. Nothing on the client changes - the loader fetches it
on the next join.

`local BUILD` in both `STD_Loader.luau` and `autoexec/STD_Hub.luau` is a
cache-buster (`?v=`). Bump it on every push: without it, raw.githubusercontent
keeps serving the previous build from its CDN for up to five minutes, which looks
exactly like a push that never landed. `push.py` stamps it automatically.

## Rebuilding from source

`STD_Hub.luau` is the deployed artifact. The working copy lives outside this
repo; this repo holds only what clients fetch.

## Simulations

`sim/` runs the loader's fetch path against a stubbed `game:HttpGet` and an
in-memory filesystem. Five scenarios: first source works, first source
rate-limited, every source dead with a cache present, every source dead with
nothing on disk, and a captive portal.

```sh
python sim/run.py
```
