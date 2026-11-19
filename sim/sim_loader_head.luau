--[[
  OFFLINE SIMULATION for the GitHub fetch path in STD_Loader.luau.
  Not shipped. The loader is concatenated verbatim between this head and
  sim_loader_tail.luau, so what runs here is the shipped code.

  The only question: when one CDN is rate-limited, does the loader still reach a
  hub - and when every CDN is dead, does it fall back to the cache instead of
  handing garbage to loadstring?
]]

local REAL_OS = os
local CLK = 0
os = {
    time  = REAL_OS.time,
    clock = function() return CLK end,
    date  = REAL_OS.date,
    difftime = REAL_OS.difftime,
}

local FS = {}
writefile = function(p, d) FS[p] = d end
readfile  = function(p) local d = FS[p]; if not d then error("no file " .. p, 2) end return d end

task = {
    wait  = function(t) CLK = CLK + (t or 0) end,
    spawn = function(f, ...)
        local co = coroutine.create(f)
        local ok, err = coroutine.resume(co, ...)
        if not ok then print("spawn error: " .. tostring(err)) end
    end,
    delay = function() end,
}
getgenv = function() return _G end

--=========================================================================
-- a body that passes looksLikeHub but is not 437KB
local HUB_BODY = string.rep("-- STD Hub build\n", 2000)   -- ~34KB
local GOOD = "STD"

local SCENARIO = __SCENARIO__

-- url -> response. false = the request itself errored (no internet)
local NET = {}
local function serve(pattern, body) NET[pattern] = body end

if SCENARIO == 1 then
    -- happy path: raw answers first time
    serve("raw.githubusercontent.com", HUB_BODY)
elseif SCENARIO == 2 then
    -- raw is rate-limited, jsDelivr carries it
    serve("raw.githubusercontent.com", '{"message":"API rate limit exceeded"}')
    serve("cdn.jsdelivr.net", HUB_BODY)
elseif SCENARIO == 3 then
    -- every CDN dead, but a previous run left a cache on disk
    FS["STD_Hub_cache.luau"] = HUB_BODY
elseif SCENARIO == 4 then
    -- every CDN dead and nothing on disk at all
elseif SCENARIO == 5 then
    -- a captive portal: 200, HTML, no STD anywhere
    serve("raw.githubusercontent.com", "<html><body>login to wifi</body></html>")
    serve("cdn.jsdelivr.net", "<html><body>login to wifi</body></html>")
    serve("raw.githack.com", "<html><body>login to wifi</body></html>")
end

local HITS = {}
local LOADED = {}
local ANTI = 0

game = {
    PlaceId = 1,
    IsLoaded = function() return true end,
    GetService = function(_, name)
        if name == "Players" then return PLAYERS end
        if name == "ReplicatedStorage" then return RS end
        return {}
    end,
    HttpGet = function(_, url, nocache)
        -- the anti-afk fetch is not part of this test; answer it with something
        -- that fails the size check, and keep it out of the hit log - it lives on
        -- raw.githubusercontent too and would otherwise be counted as a hub fetch
        if url:find("AntiAfk", 1, true) then return "x" end
        HITS[#HITS + 1] = url
        for pat, body in pairs(NET) do
            if url:find(pat, 1, true) then
                if body == false then error("connection refused") end
                return body
            end
        end
        error("connection refused")
    end,
}

PLAYERS = {
    LocalPlayer = {
        Name = "Alt3",
        FindFirstChildOfClass = function(_, c) if c == "PlayerGui" then return {} end return nil end,
    },
}
RS = { FindFirstChild = function(_, n) if n == "Remotes" then return {} end return nil end }
workspace = { FindFirstChild = function() return nil end }

-- the real loadstring is what the loader needs to be present; the hub body is
-- recorded instead of executed, because running a 437KB GUI hub under luau.exe
-- is not the thing under test
loadstring = function(src)
    if type(src) ~= "string" then return nil, "not a string" end
    return function() LOADED[#LOADED + 1] = src end
end

print(("=== scenario %d ==="):format(SCENARIO))

--=========================================================================
-- THE LOADER, VERBATIM
