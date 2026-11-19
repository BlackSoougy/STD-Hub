--=========================================================================
-- ASSERTIONS

local PASS, FAIL = 0, 0
local function ok(cond, label)
    if cond then
        PASS = PASS + 1
    else
        FAIL = FAIL + 1
        print("  FAIL: " .. label)
    end
end

local function hitsMatching(pat)
    local n = 0
    for _, u in ipairs(HITS) do
        if u:find(pat, 1, true) then n = n + 1 end
    end
    return n
end

if SCENARIO == 1 then
    ok(#LOADED == 1, "the hub is loaded once")
    ok(LOADED[1] == HUB_BODY, "the body that was loaded is the one the CDN sent")
    ok(FS["STD_Hub_cache.luau"] == HUB_BODY, "a successful fetch is written to the cache")
    ok(hitsMatching("raw.githubusercontent.com") == 1, "the first source is the only one tried")
    ok(hitsMatching("cdn.jsdelivr.net") == 0, "no mirror is touched when the first source works")
    ok(HITS[1]:find("?v=", 1, true) ~= nil, "the first request carries the cache-buster")

elseif SCENARIO == 2 then
    ok(#LOADED == 1, "a rate-limited first source still ends with a hub")
    ok(LOADED[1] == HUB_BODY, "the mirror's body is what gets loaded")
    ok(hitsMatching("raw.githubusercontent.com") == 1, "raw was tried once")
    ok(hitsMatching("cdn.jsdelivr.net") == 1, "jsDelivr was tried once")
    ok(FS["STD_Hub_cache.luau"] == HUB_BODY, "the mirror's body is cached too")

elseif SCENARIO == 3 then
    ok(#LOADED == 1, "with no network the cache is loaded")
    ok(LOADED[1] == HUB_BODY, "the cached bytes are the bytes that run")
    ok(hitsMatching("raw.githubusercontent.com") == 1, "raw was attempted before giving up")
    ok(hitsMatching("fastly.jsdelivr.net") == 1, "the last mirror was attempted too")

elseif SCENARIO == 4 then
    ok(#LOADED == 0, "no network and no cache loads nothing")
    ok(FS["STD_Hub_cache.luau"] == nil, "a failed fetch never writes a cache")

elseif SCENARIO == 5 then
    ok(#LOADED == 0, "an HTML captive portal never reaches loadstring")
    ok(FS["STD_Hub_cache.luau"] == nil, "a rejected body is not cached")
end

print(("  %d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then error("scenario " .. SCENARIO .. " failed", 0) end
