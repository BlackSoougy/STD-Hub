--[[
  STD HUB - AUTOEXEC BOOTSTRAP
  ============================

  The only file that belongs in the executor's autoexec folder. It does one
  thing: fetch STD_Loader.luau from the repo and run it. Everything else - the
  ready-wait, the anti-AFK guard, the per-account stagger, the hub itself - lives
  in the repo, so a fix ships by pushing a commit instead of by copying files
  onto six machines.

  WHY IT IS NOT JUST ONE loadstring LINE
  --------------------------------------
  Because a one-line bootstrap fails silently. If raw.githubusercontent answers
  429 at the exact moment six clients attach, the client gets nothing, prints
  nothing, and looks identical to a hub that crashed. Three sources plus a log
  line turns that into something readable after the fact.

  THE ORDER
  ---------
    1. raw.githubusercontent  canonical, but rate-limits a burst of joins
    2. cdn.jsdelivr.net       same bytes, different CDN, different rate limit
    3. fastly.jsdelivr.net    second jsDelivr edge - survives a DNS blackhole on
                              either of the other two hostnames

  If all three fail the loader is not loaded and a line is appended to
  STD_Autoexec_log.txt. The hub's own cache is a separate layer: once the loader
  is running it can fall back to STD_Hub_cache.luau even with the network dead.

  REPO is the only line that needs editing if the repo moves.
]]

local REPO  = "BlackSoougy/STD-Hub"
local REF   = "main"
local BUILD = "2026-11-19"

local URLS = {
    ("https://raw.githubusercontent.com/%s/%s/STD_Loader.luau?v=%s"):format(REPO, REF, BUILD),
    ("https://cdn.jsdelivr.net/gh/%s@%s/STD_Loader.luau"):format(REPO, REF),
    ("https://fastly.jsdelivr.net/gh/%s@%s/STD_Loader.luau"):format(REPO, REF),
}

-- its own file. the loader rewrites STD_Loader_log.txt from the top on every
-- line, so anything written there from out here is gone within a second
local LOG = "STD_Autoexec_log.txt"
local OUT = {}

local function note(msg)
    OUT[#OUT + 1] = ("[autoexec %s] %s"):format(os.date("%H:%M:%S"), msg)
    pcall(function() print("[STD autoexec] " .. msg) end)
    if type(writefile) == "function" then
        pcall(function() writefile(LOG, table.concat(OUT, "\n") .. "\n") end)
    end
end

-- one argument on purpose. a second "nocache" flag is accepted by some
-- executors and raises an argument error on the rest, and probing for it means
-- asking a rate-limited source twice - which is the one request that must not be
-- repeated. the ?v= only separates the executor's own cache; raw's CDN ignores
-- the query string entirely and holds the old build for five minutes.
local function httpGet(url)
    return pcall(game.HttpGet, game, url)
end

if type(loadstring) ~= "function" then
    note("this executor has no loadstring - nothing can be fetched")
    return
end

local ran = false

for i, url in ipairs(URLS) do
    local ok, body = httpGet(url)
    if ok and type(body) == "string" and #body > 1000 and body:sub(1, 1) ~= "<" then
        local chunk, cerr = loadstring(body)
        if chunk then
            note(("loader %d KB from source %d"):format(math.floor(#body / 1024), i))
            local okRun, rerr = pcall(chunk)
            if okRun then
                ran = true
            else
                note("loader errored: " .. tostring(rerr))
            end
            break
        end
        note(("source %d did not compile: %s"):format(i, tostring(cerr)))
    else
        note(("source %d failed: %s"):format(i, tostring(ok and ("bad body, " .. #tostring(body) .. "b") or body)))
    end
end

if not ran then
    note("no loader from any source - if a hub is already live it is still running")
end
