-- LFM channels: the new /trade option alongside the existing ones - saved
-- state, availability, the status line, checkbox, and what actually gets sent.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

local built, buildErr = pcall(function() addon:ToggleWindow(true) end)
check("main window builds", built and addon.ui and addon.ui.lfmPanel ~= nil, buildErr)

-- Joined channels exactly as a 3.3.5 client reports them: GetChannelList()
-- returns id, name PAIRS (no third value - that arrived in a later
-- expansion), and GetChannelName(name) only resolves an exact, case-sensitive
-- name, so a lowercase alias like "trade" comes back 0 and the addon has to
-- find "Trade" by walking the list.
local joined = {}
local listStride = 2
function GetChannelList()
    local out = {}
    for _, c in ipairs(joined) do
        table.insert(out, c.id); table.insert(out, c.name)
        if listStride == 3 then table.insert(out, false) end
    end
    return unpack(out)
end
function GetChannelName(query)
    for _, c in ipairs(joined) do
        if c.name == query then
            return c.id, c.name
        end
    end
    return 0, nil
end

-- 1. Saved state ------------------------------------------------------------------
local channels = addon:GetLFMChannels()
check("trade channel saved default is off", channels.trade == false)
check("global default untouched (on)", channels.global == true)
check("SetLFMChannel accepts trade", addon:SetLFMChannel("trade", true) == true)
check("trade now on", addon:GetLFMChannels().trade == true)
check("SetLFMChannel still rejects unknown channels", addon:SetLFMChannel("officer", true) == false)

-- 2. Availability: out of town, Trade does not exist --------------------------------------
joined = { { id = 1, name = "General - Icecrown" }, { id = 3, name = "Global" } }
local avail = addon:GetLFMChannelAvailability()
check("general found by its zone-suffixed name", avail.general == true and avail.generalId == 1, avail.generalName)
check("global found", avail.global == true)
check("trade missing outside a city", avail.trade == false)

-- 3. Checkbox + status line ------------------------------------------------------------------
check("trade checkbox exists", addon.ui.lfmTradeCheck ~= nil)
check("trade checkbox label", (_G["RaidInspectorLFMTradeCheckText"] and _G["RaidInspectorLFMTradeCheckText"]:GetText()) == "/trade")
addon:SetActiveTab("lfm")
addon:RefreshMainWindow()
check("trade checkbox reflects saved state", addon.ui.lfmTradeCheck:GetChecked() == true)
local status = addon.ui.lfmChannelStatus:GetText() or ""
check("status line lists /trade", status:find("/trade", 1, true) ~= nil, status)
check("status line says trade is missing and city-only", status:find("missing", 1, true) ~= nil and status:find("city only", 1, true) ~= nil, status)

-- Clicking the box drives the setter.
addon.ui.lfmTradeCheck:SetChecked(false)
addon.ui.lfmTradeCheck:GetScript("OnClick")(addon.ui.lfmTradeCheck)
check("unticking the box turns trade off", addon:GetLFMChannels().trade == false)
addon.ui.lfmTradeCheck:SetChecked(true)
addon.ui.lfmTradeCheck:GetScript("OnClick")(addon.ui.lfmTradeCheck)
check("ticking the box turns trade on", addon:GetLFMChannels().trade == true)

-- 4. Posting with Trade selected but not joined ------------------------------------------------
addon:SetLFMChannel("yell", false)
addon:SetLFMChannel("guild", false)
addon:SetLFMChannel("general", false)
addon:SetLFMChannel("global", false)
addon:SetLFMChannel("trade", true)
addon:SetLFMMessage("LFM ICC25 need 2 heals")
addon:SetLFMRepeatCount("1")
printed = {}
sentChat = {}
local selected, queued = addon:PostLFMMessage()
check("trade counted as selected", selected == 1, selected)
check("nothing queued when trade is not joined", queued == 0, queued)
check("told that trade only exists in a city", table.concat(printed, "\n"):find("only exists inside a city", 1, true) ~= nil, printed[1])
check("nothing sent", #sentChat == 0)

-- 5. In a city: Trade is joined and the post goes to its channel id -------------------------------
-- This is the exact situation from the bug report: Trade is channel 2 on a
-- pairs-returning client. A list walk that steps by three never sees it.
joined = { { id = 1, name = "General" }, { id = 2, name = "Trade" }, { id = 3, name = "Global" } }
avail = addon:GetLFMChannelAvailability()
check("trade found inside a city (channel 2 on a pairs client)", avail.trade == true and avail.tradeId == 2, avail.tradeId)
check("trade's joined name reported", avail.tradeName == "Trade", avail.tradeName)
check("global (channel 3) resolves to its real name, not the alias", avail.globalName == "Global", avail.globalName)
addon:RefreshMainWindow()
status = addon.ui.lfmChannelStatus:GetText() or ""
check("status line shows trade joined", status:find("/trade: joined (Trade)", 1, true) ~= nil, status)

-- Zone-suffixed names (stock client) and the later three-value layout must
-- both keep working.
joined = { { id = 1, name = "General - Dalaran" }, { id = 2, name = "Trade - Dalaran" }, { id = 3, name = "Global" } }
avail = addon:GetLFMChannelAvailability()
check("zone-suffixed Trade found", avail.trade == true and avail.tradeName == "Trade - Dalaran", avail.tradeName)
listStride = 3
avail = addon:GetLFMChannelAvailability()
check("three-value channel list still walks correctly", avail.trade == true and avail.tradeId == 2 and avail.global == true, avail.tradeId)
listStride = 2
joined = { { id = 1, name = "General" }, { id = 2, name = "Trade" }, { id = 3, name = "Global" } }
avail = addon:GetLFMChannelAvailability()
check("city-only hint gone when joined", status:find("city only", 1, true) == nil)

printed = {}
sentChat = {}
selected, queued = addon:PostLFMMessage()
-- The second return value is "still pending" (the sender drains the same
-- table), so assert on the report line and on what was actually sent.
check("one post queued for trade", table.concat(printed, " "):find("queued 1 post", 1, true) ~= nil, printed[1])
check("message sent to a CHANNEL", sentChat[1] and sentChat[1].chan == "CHANNEL", sentChat[1] and sentChat[1].chan)
check("...with Trade's channel id", sentChat[1] and sentChat[1].target == 2, sentChat[1] and sentChat[1].target)
check("...carrying the LFM text", sentChat[1] and sentChat[1].msg:find("LFM ICC25", 1, true) ~= nil)

-- 6. Trade alongside the others keeps the existing channels working -------------------------------
addon:SetLFMChannel("general", true)
addon:SetLFMChannel("global", true)
sentChat = {}
printed = {}
selected, queued = addon:PostLFMMessage()
check("three channels selected", selected == 3, selected)
check("three posts queued", table.concat(printed, " "):find("queued 3 post", 1, true) ~= nil, printed[#printed])
-- Drain the throttled queue.
_G.__now = (_G.__now or 1000)
for i = 1, 5 do
    _G.__now = _G.__now + 60
    addon:ProcessLFMPostQueue(true)
end
local ids = {}
for _, m in ipairs(sentChat) do ids[m.target] = true end
check("general, trade and global each got the post", ids[1] and ids[2] and ids[3], #sentChat)

-- 7. Nothing selected still says so, naming Trade --------------------------------------------------
addon:SetLFMChannel("general", false)
addon:SetLFMChannel("global", false)
addon:SetLFMChannel("trade", false)
printed = {}
selected, queued = addon:PostLFMMessage()
check("no channels -> nothing queued", queued == 0)
check("no-channels message lists Trade", (printed[1] or ""):find("Trade", 1, true) ~= nil, printed[1])

finish()
