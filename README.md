# STD Hub

Sorcerer Tower Defense multi-box hub. One account is the king, the rest follow
him through portals, into events, and across server hops.

## Files

| file | what it is |
| --- | --- |
| `STD_Hub.luau` | the hub itself, ~430 KB, the only thing that draws a window |
| `STD_Loader.luau` | waits for the server, starts anti-AFK, fetches and runs the hub |
| `autoexec/STD_Hub.luau` | the only file that goes in the executor's autoexec folder |
| `Library.lua` | the Obsidian UI library, ~555 KB, vendored so the hub does not depend on somebody else's repo |
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
JSON, and it must contain `hub v`. A 429 response is 90 bytes of JSON and a captive
portal is an HTML page; both would otherwise fail inside the hub with a syntax
error naming the wrong cause.

The `hub v` marker is what separates the current build from the 56 KB ancestor of
this hub that still sits in the executor workspace. That ancestor says "STD Hub"
in its header and would pass a looser check, so the loader would happily run a
month-old hub and report a successful load. Every build from v7 on carries
`hub v`; none of the ancestors do.

## The window

The UI library is fetched by the hub itself, before the window is built, from
this repo first and `deividcomsono/Obsidian` second:

```
STD-Hub raw  ->  cdn.jsdelivr  ->  fastly.jsdelivr  ->  Obsidian raw  ->  cdn.jsdelivr  ->  STD_Library_cache.lua
```

Two rounds, then the disk copy. A body has to be at least 100 KB and contain
`Obsidian`: a truncated library is worse than a missing one, because it compiles
far enough to start building the window and then dies in the middle of it.

Once the window exists, a supervisor checks it once a second and repairs it. The
four things that take it off the screen, none of which the hub can otherwise
notice:

| what happened | what the supervisor does |
| --- | --- |
| the ScreenGui was unparented | re-parents it to `gethui()` |
| the ScreenGui was disabled | re-enables it |
| something draws above DisplayOrder 998 | raises it to 9999 |
| the frame is off the viewport | recentres it |

Each repair is logged once, and one line is written at startup with everything
needed to tell the cases apart:

```
gui: screen=Obsidian parent=CoreGui enabled=true order=9999 frame=MainFrame
     visible=true pos=280,60 size=720x600 in-view=720x600 loaded=true coregui=[...]
```

`loaded=false`, or a loading GUI in `coregui`, means the window is fine and the
client has not finished joining - the loading screen draws above everything.

**F2** re-shows and re-centres the window. RightShift only toggles visibility,
which does nothing when what is hidden is a window sitting off the edge of the
screen.

## Updating

Push a new `STD_Hub.luau`. Nothing on the client changes - the loader fetches it
on the next join.

`local BUILD` in both `STD_Loader.luau` and `autoexec/STD_Hub.luau` is stamped
with the push date by `push.py`. It separates the executor's own http cache, but
it does **not** bust raw.githubusercontent: that CDN keys on the path, ignores
the query string, and serves the previous build for up to five minutes
(`Cache-Control: max-age=300`). Expect one stale join after an update.

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
