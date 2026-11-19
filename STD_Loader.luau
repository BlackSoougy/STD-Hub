--[[
  STD HUB - AUTOEXEC LOADER
  =========================

  This is the only file that belongs in the executor's autoexec folder. It
  waits for the game to actually be ready, starts the anti-AFK guard, and then
  loads the hub from disk.

  WHY A LOADER AND NOT THE HUB ITSELF
  -----------------------------------
  An autoexec script runs the moment the executor attaches, which on a cold
  join is long before the server has finished handing the client its character,
  its PlayerGui and its map. The hub does its tower scan and builds its ability
  table at load time, so loading it during that window produced
  "hub v7 loaded, 0 ability tower(s)" and a farm that sat there doing nothing
  until the next reload. The hub itself cannot fix that - by the time it is
  running, the scan has already happened - so the wait has to live in front of
  it, here.

  WHAT "READY" MEANS HERE
  -----------------------
  Three signals, and only the third one is really about the server:

    1. game:IsLoaded()   the DataModel has finished streaming in
    2. LocalPlayer       and its PlayerGui - the hub builds its window in there
    3. the server's state, whichever of these lands first:
         workspace.Towers            the lobby's map, and what the tower scan needs
         ReplicatedStorage.Remotes   the server's remote folder, present in every
                                     place including the event map

  The character is NOT waited for, and neither is the game's own GUI. Nothing
  the hub does at load touches the character, and a character wait is the single
  largest cost on a join - up to 90s on a slow spawn, for a signal that adds
  nothing. The game GUI appears later than either server signal anyway.

  Every wait polls at 0.1s and exits the instant it is satisfied, so a normal
  join costs well under a second. There is a 0.25s settle at the end, not the
  2.5s there used to be: the hub does its own pre-flight wait for Remotes and
  PlayerGui, so anything still arriving is covered there.

  FAILURE BEHAVIOUR
  -----------------
  Every wait has a timeout and nothing here can hang forever. If the tower
  folder never shows up the hub is loaded anyway - it rescans towers every two
  seconds, so a late map costs nothing but an empty picker for a moment.
]]

local Players = game:GetService("Players")

local STARTED = os.clock()
local OUT = {}

-- ITS OWN FILE, NOT THE HUB'S.
-- The hub keeps its whole log in memory and rewrites STD_Hub_log_<name>.txt from
-- that array on every flush, so anything appended to it from out here is gone on
-- the hub's next write - which is within a second of it loading. Two writers,
-- two files. STD_Loader_log.txt is only ever written by this script.
local LOG_FILE = "STD_Loader_log.txt"

local function flush()
    if not writefile then return end
    pcall(function() writefile(LOG_FILE, table.concat(OUT, "\n") .. "\n") end)
end

-- console + the log file. written through on every line, not at the end: the
-- interesting failure is the one that stops this script, and a log that only
-- lands at the bottom of a script that never reaches the bottom is no log
local function say(msg)
    OUT[#OUT + 1] = ("[loader %6.2fs] %s"):format(os.clock() - STARTED, msg)
    pcall(function() print("[STD loader] " .. msg) end)
    flush()
end

--=====================================================================
-- 1. WAIT FOR THE SERVER

local function waitReady()
    -- THE ONLY QUESTION IS "HAS THE SERVER SENT ITS STATE", NOT "IS THE GAME
    -- FINISHED LOADING". Everything below is polled at 0.1s and every branch
    -- exits the moment it is satisfied, so a normal join costs a fraction of a
    -- second instead of the ten it used to spend waiting on a character and a
    -- GUI the hub does not need to start.

    -- 1. the DataModel. at attach time this is usually already true; the wait
    -- exists for the case where the executor beats the place load
    if not game:IsLoaded() then
        local t = 0
        while not game:IsLoaded() and t < 20 do task.wait(0.1) t = t + 0.1 end
        say(("game loaded after %.1fs"):format(t))
    end

    -- 2. LocalPlayer and its PlayerGui. the hub builds its window inside
    -- PlayerGui, so that one really is required - but it exists from the first
    -- frame, unlike the character
    local t = 0
    local lp = Players.LocalPlayer
    while t < 20 do
        lp = lp or Players.LocalPlayer
        if lp and lp:FindFirstChildOfClass("PlayerGui") then break end
        task.wait(0.1)
        t = t + 0.1
    end
    if not lp then
        say("no LocalPlayer after 20s")
        return nil
    end

    -- 3. HAS THE SERVER SENT ITS STATE. Two signals, whichever lands first:
    -- workspace.Towers is the lobby's map (and what the hub's tower scan needs),
    -- ReplicatedStorage.Remotes is the server's own remote folder and exists in
    -- every place, including the event map where there is no Towers folder at
    -- all. Waiting only for Towers meant a twelve second stall on every load
    -- that was not in the lobby.
    -- The character is deliberately NOT waited for: nothing the hub does at
    -- load touches it, and a character wait is the single biggest cost on a
    -- join (up to 90s on a slow spawn). If both signals are late the hub still
    -- works - it rescans towers every 2s - so this timeout is short on purpose.
    local RS = game:GetService("ReplicatedStorage")
    local function serverUp()
        return workspace:FindFirstChild("Towers") ~= nil or RS:FindFirstChild("Remotes") ~= nil
    end
    t = 0
    while t < 12 and not serverUp() do
        task.wait(0.1)
        t = t + 0.1
    end
    local ws = workspace:FindFirstChild("Towers")
    if ws then
        local n = 0
        for _, c in ipairs(ws:GetChildren()) do n = n + 1 end
        say(("server up after %.1fs, %d tower(s) on it"):format(t, n))
    elseif RS:FindFirstChild("Remotes") then
        say(("server up after %.1fs (remotes, no tower folder here)"):format(t))
    else
        say(("nothing from the server after %.1fs - loading anyway, the hub rescans"):format(t))
    end

    -- a quarter of a second, not two and a half. the hub's own pre-flight waits
    -- for Remotes and PlayerGui itself, so this is only here to let the first
    -- replication burst finish
    task.wait(0.25)
    return lp
end

--=====================================================================
-- 2. ANTI-AFK

-- spawned, not awaited: it is a network fetch and a 190KB obfuscated chunk, and
-- the hub should not sit behind it. a failure here must never stop the hub, so
-- it is pcall'd twice - once around the fetch and once around the chunk
local function startAntiAfk()
    task.spawn(function()
        local url = "https://raw.githubusercontent.com/unrexl/Scripts/refs/heads/main/AntiAfk9b7m"
        local function attempt()
            local ok, err = pcall(function()
                local src = game:HttpGet(url)
                if type(src) ~= "string" or #src < 200 then
                    error("the URL returned " .. tostring(type(src)) .. ", not a script")
                end
                local chunk, cerr = loadstring(src)
                if not chunk then error("loadstring: " .. tostring(cerr)) end
                chunk()
            end)
            return ok, err
        end
        local ok, err = attempt()
        if not ok then
            -- one retry: the usual cause is a rate-limited raw.githubusercontent
            -- at exactly the wrong moment, and it clears in seconds
            say("anti-afk failed, retrying in 5s: " .. tostring(err))
            task.wait(5)
            ok, err = attempt()
        end
        say(ok and "anti-afk started" or ("anti-afk gave up: " .. tostring(err)))
    end)
end

--=====================================================================
-- 3. THE HUB

-- WHERE THE HUB COMES FROM
-- ------------------------
-- It lives in a public GitHub repo and is fetched over HTTPS at load time, so
-- every client on the machine runs the same build without anyone copying a file
-- around by hand. Three things matter here:
--
--   * THREE SOURCES, IN ORDER. raw.githubusercontent is canonical but it is also
--     the one that rate-limits a machine doing six simultaneous joins. jsDelivr
--     serves the same bytes off a different CDN, so a 429 on the first costs a
--     few hundred milliseconds instead of a dead client. The third entry is a
--     second jsDelivr edge: same bytes, different hostname, which is what saves
--     a client whose DNS has one of the two names blackholed.
--   * A DISK COPY IS WRITTEN ON EVERY SUCCESSFUL FETCH. If all three are
--     unreachable - no internet, DNS dead, GitHub down - the last good build is
--     loaded from STD_Hub_cache.luau. A stale hub beats an empty one, and the
--     cache is overwritten on the next join that does reach the network.
--   * THE BODY IS CHECKED BEFORE IT REACHES loadstring. A rate-limit JSON is 90
--     bytes and a captive portal is an HTML page; both would otherwise fail
--     inside the hub with a syntax error that names the wrong cause.
--
-- REPO is the only line that needs editing if the repo ever moves.
local REPO  = "BlackSoougy/STD-Hub"
local REF   = "main"
local BUILD = "2026-11-19"

local CACHE_FILE = "STD_Hub_cache.luau"

-- the ?v= separates the EXECUTOR's own http cache, which keys on the full URL.
-- It does not touch raw.githubusercontent's CDN: that cache keys on the path
-- alone, ignores the query string, and holds the previous build for up to five
-- minutes after a push. Measured, not assumed - the response carries
-- "Cache-Control: max-age=300" and a HIT, and a request with a fresh query
-- string still returns the old bytes. So expect exactly one stale join after an
-- update, and reload twice if the first one comes up as the old build.
local HUB_URLS = {
    ("https://raw.githubusercontent.com/%s/%s/STD_Hub.luau?v=%s"):format(REPO, REF, BUILD),
    ("https://cdn.jsdelivr.net/gh/%s@%s/STD_Hub.luau"):format(REPO, REF),
    ("https://fastly.jsdelivr.net/gh/%s@%s/STD_Hub.luau"):format(REPO, REF),
}

local function looksLikeHub(body)
    if type(body) ~= "string" or #body < 20000 then return false end
    if body:sub(1, 1) == "<" then return false end                 -- html
    if body:sub(1, 1) == "{" or body:sub(1, 1) == "[" then return false end
    return body:find("STD", 1, true) ~= nil
end

-- ONE ARGUMENT, DELIBERATELY.
-- Several executors accept a second "nocache" flag on HttpGet; the ones that do
-- not raise an argument error instead of ignoring it. Probing for that support
-- costs a second request against every source that fails, and a rate-limited
-- source is exactly the one that must not be asked twice. The ?v= on the first
-- URL does the same job without the gamble.
local function httpGet(url)
    return pcall(game.HttpGet, game, url)
end

local function fetchHub()
    for i, url in ipairs(HUB_URLS) do
        local t0 = os.clock()
        local ok, body = httpGet(url)
        if ok and looksLikeHub(body) then
            say(("hub %d KB from source %d in %.2fs"):format(math.floor(#body / 1024), i, os.clock() - t0))
            if type(writefile) == "function" then
                pcall(writefile, CACHE_FILE, body)
            end
            return body, "net" .. i
        end
        local why = ok and ("bad body, " .. tostring(#tostring(body)) .. "b") or tostring(body)
        say(("source %d failed in %.2fs: %s"):format(i, os.clock() - t0, why))
    end
    return nil
end

-- the hand-copied names stay as the last resort: a build dragged onto the
-- machine by hand should still run when the network is gone
local HUB_NAMES = { "STD_Hub_v7.luau", "STD_Hub.luau", "STD_Hub_v7.txt" }

local function readHub()
    if type(readfile) ~= "function" then return nil end
    local names = { CACHE_FILE }
    for _, n in ipairs(HUB_NAMES) do names[#names + 1] = n end
    for _, name in ipairs(names) do
        local okFile, src = pcall(readfile, name)
        if okFile and looksLikeHub(src) then
            return src, name
        end
    end
    return nil
end

local function loadHub(LP)
    if type(loadstring) ~= "function" then
        say("this executor has no loadstring - cannot run the hub")
        return false
    end
    local src, name = fetchHub()
    if not src then
        src, name = readHub()
        if src then
            say(("every source failed - falling back to the local copy %s"):format(name))
        end
    end
    if not src then
        say("no hub from the network and no local copy on disk - nothing to run")
        return false
    end

    -- A SMALL PER-ACCOUNT STAGGER.
    -- Six clients compiling 363KB and building a GUI in the same frame is six
    -- full Lua VMs and six GUI trees landing on one machine at once, and that is
    -- how a client ends up alive but never finishing its load - which is the
    -- state that turns into a 256 when something teleports it. The offset is
    -- derived from the account name, so it is stable across rejoins and needs no
    -- coordination: the clients spread themselves out
    local uname = LP and LP.Name or ""
    local jitter = 0
    for i = 1, #uname do jitter = (jitter * 31 + string.byte(uname, i)) % 1000 end
    jitter = jitter / 1000 * 0.9
    if jitter > 0.05 then
        say(("staggering %.2fs"):format(jitter))
        task.wait(jitter)
    end

    -- the hub destroys any previous instance itself, so a double load is
    -- survivable - but it is still worth saying out loud, because it means the
    -- file is in autoexec as well and this loader is not the only entry point
    if getgenv().STD_Hub then
        say("an STD_Hub instance is already live - replacing it")
    end

    local chunk, cerr = loadstring(src)
    if not chunk then
        say("hub did not compile: " .. tostring(cerr))
        return false
    end
    local okRun, rerr = pcall(chunk)
    if not okRun then
        say("hub errored while loading: " .. tostring(rerr))
        return false
    end
    say("hub loaded")
    return true
end

--=====================================================================
-- 4. RUN

local lp = waitReady()

if lp then
    startAntiAfk()

    -- one retry. a hub that fails to load is usually a partially written file
    -- from an interrupted copy, and a second read three seconds later is free
    if not loadHub(lp) then
        say("retrying the hub in 3s")
        task.wait(3)
        loadHub(lp)
    end
else
    say("no LocalPlayer - loading the hub without the anti-afk guard")
    loadHub(lp)
end

say("done")
flush()
