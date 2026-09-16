-- Minimal WoW 3.3.5a API stub, good enough to load the real RaidInspector.lua
-- and drive its methods under plain Lua 5.1 (see run.py). Anything not
-- modelled comes back nil through the widget metatable rather than erroring,
-- so the addon's own guards get exercised.
--
-- Gotchas this stub already accounts for (do not re-discover them):
--   * the addon probes the global CanInspect(unit), not CanInspectUnit
--   * GetNow() is time(), not GetTime(), so the fake clock overrides time()
--   * FindUnitByName only walks raidN units when GetNumRaidMembers() > 0
--   * named frames created from Blizzard templates need their <name>Text-style
--     child regions to exist as globals
--   * the widget metatable returns nil for non-PascalCase keys, otherwise the
--     addon's own data fields (container.rows, row.key ...) come back as
--     fabricated functions

registeredEvents = {}
unregisteredEvents = {}
sentChat = {}
printed = {}
achComparisonUnit = nil
achComparisonCleared = 0
tooltipLines = {}
tooltipHyperlink = nil

local LAYOUT_NUMBERS = {
    GetStringHeight = 12, GetStringWidth = 80, GetHeight = 20, GetWidth = 200,
    GetVerticalScrollRange = 0, GetVerticalScroll = 0, GetNumLines = 3,
    GetScale = 1, GetEffectiveScale = 1, GetLeft = 0, GetRight = 200,
    GetTop = 200, GetBottom = 0, GetValue = 0, GetFrameLevel = 1,
}

local WidgetMT = {}

local function newWidget(kind, name)
    local w = {
        __widget = true, __kind = kind, __name = name,
        scripts = {}, events = {}, points = {}, children = {},
        shown = true, text = "",
    }
    setmetatable(w, WidgetMT)
    if name then _G[name] = w end
    return w
end

WidgetMT.__index = function(t, k)
    if type(k) ~= "string" or not string.find(k, "^%u") then
        return nil
    end

    local fn
    if LAYOUT_NUMBERS[k] then
        local v = LAYOUT_NUMBERS[k]
        fn = function() return v end
    elseif k == "CreateFontString" or k == "CreateTexture" or k == "CreateTitleRegion" then
        fn = function(self, nm) return newWidget(k, nm) end
    elseif k == "RegisterEvent" then
        fn = function(self, ev)
            self.events[ev] = true
            registeredEvents[ev] = (registeredEvents[ev] or 0) + 1
        end
    elseif k == "UnregisterEvent" then
        fn = function(self, ev)
            self.events[ev] = nil
            unregisteredEvents[ev] = (unregisteredEvents[ev] or 0) + 1
        end
    elseif k == "IsEventRegistered" then
        fn = function(self, ev) return self.events[ev] == true end
    elseif k == "SetScript" or k == "HookScript" then
        fn = function(self, s, f) self.scripts[s] = f end
    elseif k == "GetScript" then
        fn = function(self, s) return self.scripts[s] end
    elseif k == "SetText" or k == "SetFormattedText" then
        fn = function(self, txt) self.text = tostring(txt or "") end
    elseif k == "GetText" then
        fn = function(self) return self.text end
    elseif k == "GetFont" then
        fn = function() return "Fonts\\FRIZQT__.TTF", 12, "" end
    elseif k == "GetObjectType" then
        fn = function(self) return self.__kind or "Frame" end
    elseif k == "IsShown" or k == "IsVisible" then
        fn = function(self) return self.shown == true end
    elseif k == "Show" then
        fn = function(self) self.shown = true end
    elseif k == "Hide" then
        fn = function(self) self.shown = false end
    elseif k == "GetParent" then
        fn = function(self) return self.__parent end
    elseif k == "GetName" then
        fn = function(self) return self.__name end
    elseif k == "GetPoint" then
        fn = function() return "CENTER", nil, "CENTER", 0, 0 end
    elseif k == "GetChecked" then
        fn = function(self) return self.checked == true end
    elseif k == "SetChecked" then
        fn = function(self, v) self.checked = v and true or false end
    else
        fn = function() return nil end
    end

    rawset(t, k, fn)
    return fn
end

-- Blizzard XML templates create named child regions (UICheckButtonTemplate
-- makes <name>Text, and so on). Addons index those globals directly.
local TEMPLATE_CHILD_SUFFIXES = {
    "Text", "Button", "Label", "Icon", "Border", "Title", "Header", "Close",
    "Left", "Middle", "Right", "ScrollBar", "ScrollChildFrame",
    "ScrollUpButton", "ScrollDownButton", "ScrollFrame", "EditBox",
}

function CreateFrame(kind, name, parent, template)
    local f = newWidget(kind, name)
    f.__parent = parent
    f.__template = template
    if name then
        local i
        for i = 1, #TEMPLATE_CHILD_SUFFIXES do
            local childName = name .. TEMPLATE_CHILD_SUFFIXES[i]
            if _G[childName] == nil then
                newWidget("FontString", childName)
            end
        end
    end
    return f
end

UIParent = newWidget("Frame", "UIParent")
WorldFrame = newWidget("Frame", "WorldFrame")
DEFAULT_CHAT_FRAME = newWidget("ChatFrame", "DEFAULT_CHAT_FRAME")
DEFAULT_CHAT_FRAME.AddMessage = function(self, msg)
    table.insert(printed, tostring(msg))
end

-- GameTooltip records what the addon puts in it so tests can assert on it.
GameTooltip = newWidget("GameTooltip", "GameTooltip")
GameTooltip.SetOwner = function() end
GameTooltip.ClearLines = function() tooltipLines = {}; tooltipHyperlink = nil end
GameTooltip.SetHyperlink = function(self, link) tooltipHyperlink = link end
GameTooltip.AddLine = function(self, txt) table.insert(tooltipLines, tostring(txt or "")) end
GameTooltip.AddDoubleLine = function(self, a, b) table.insert(tooltipLines, tostring(a or "") .. " | " .. tostring(b or "")) end
GameTooltip.SetBagItem = function() end
GameTooltip.Show = function(self) self.shown = true end
GameTooltip.Hide = function(self) self.shown = false end

SlashCmdList = {}
StaticPopupDialogs = {}
function StaticPopup_Show() end
function StaticPopup_Hide() end

-- The addon's GetNow() is time(); tests move the clock through _G.__now.
function time() return _G.__now or 1000 end
date = os.date
function GetTime() return _G.__now or 1000 end
function GetLocale() return "enUS" end
function GetRealmName() return "TestRealm" end
function GetCVar() return "TestRealm" end
function UnitFactionGroup() return "Alliance" end
function IsInGuild() return false end
function IsRaidLeader() return true end
function IsRaidOfficer() return true end
function GetNumRaidMembers() return _G.__numRaid or 0 end
function GetNumPartyMembers() return 0 end
function GetRaidRosterInfo() return nil end
function SendChatMessage(msg, chan, _, target)
    table.insert(sentChat, { msg = msg, chan = chan, target = target })
end
function SendAddonMessage() end
function GetChannelName() return 0 end
function JoinChannelByName() end
function IsAddOnLoaded(name) return _G.__loadedAddons and _G.__loadedAddons[name] == true end
function LoadAddOn(name)
    _G.__loadedAddons = _G.__loadedAddons or {}
    _G.__loadedAddons[name] = true
    _G.__loadAddOnCalls = (_G.__loadAddOnCalls or 0) + 1
    return true
end

-- Units ------------------------------------------------------------------
_G.__units = {}   -- unit token -> { name, realm, guid, inspectable, class, level }

function UnitExists(unit) return _G.__units[unit] ~= nil end
function UnitName(unit)
    local u = _G.__units[unit]
    if not u then return nil end
    return u.name, u.realm
end
function UnitGUID(unit)
    local u = _G.__units[unit]
    return u and u.guid or nil
end
function UnitClass(unit)
    local u = _G.__units[unit]
    return u and u.class or "WARRIOR", u and u.class or "WARRIOR"
end
function UnitLevel(unit)
    local u = _G.__units[unit]
    return u and u.level or 80
end
function UnitIsPlayer() return true end
function UnitIsConnected() return true end
function UnitIsVisible(unit) return _G.__units[unit] ~= nil end
function UnitGuildName() return nil end
function CanInspect(unit)
    local u = _G.__units[unit]
    return u ~= nil and u.inspectable ~= false
end
function NotifyInspect(unit) _G.__lastNotifyInspect = unit end
function ClearInspectPlayer() _G.__clearInspectCount = (_G.__clearInspectCount or 0) + 1 end
function GetInventoryItemLink() return nil end
function GetInventoryItemTexture() return nil end

-- Talents ----------------------------------------------------------------
function GetNumTalentTabs() return 3 end
function GetTalentTabInfo() return "Spec", nil, nil, nil, 0 end
function GetTalentInfo() return "Talent", nil, nil, nil, 0, 5 end
function GetPrimaryTalentTree() return 1 end

-- Achievements -----------------------------------------------------------
_G.__achData = nil     -- achievement id -> true/false for the comparison unit
_G.__achPoints = nil

local ACH_NAMES = {
    [4530] = "The Frozen Throne",
    [4597] = "The Frozen Throne",
    [3917] = "Call of the Crusade (10 player)",
    [3916] = "Call of the Crusade (25 player)",
    [4817] = "The Twilight Destroyer (10 player)",
    [4815] = "The Twilight Destroyer (25 player)",
}

function GetAchievementInfo(id)
    local nm = ACH_NAMES[id]
    if not nm then return nil end
    return id, nm, 10, false, 1, 1, 2010, "desc", 0, "icon"
end
function SetAchievementComparisonUnit(unit) achComparisonUnit = unit; return true end
function ClearAchievementComparisonUnit()
    achComparisonUnit = nil
    achComparisonCleared = achComparisonCleared + 1
end
function GetAchievementComparisonInfo(id)
    if not _G.__achData then return nil end
    if _G.__achData[id] then return true, 1, 1, 2010, 0 end
    return false, nil, nil, nil, 0
end
function GetComparisonAchievementPoints() return _G.__achPoints end
function GetAchievementNumCriteria() return 0 end
function GetAchievementCriteriaInfo() return nil end
function GetAchievementLink() return nil end

-- Items ------------------------------------------------------------------
-- __itemInfo: id -> { name, quality, ilvl }. Anything else is "not cached".
_G.__itemInfo = {}
function GetItemInfo(idOrLink)
    local id = tonumber(idOrLink) or tonumber(string.match(tostring(idOrLink), "item:(%d+)"))
    local info = id and _G.__itemInfo[id]
    if not info then return nil end
    local link = "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:80|h[" .. info.name .. "]|h|r"
    return info.name, link, info.quality or 4, info.ilvl or 264, 80, "Armor", "Plate", 1, "INVTYPE_HEAD", "icon"
end
function GetItemQualityColor(q)
    local hex = ({ [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" })[q] or "ffffff"
    return 1, 1, 1, "|cff" .. hex
end
function GetContainerNumSlots() return 0 end
function GetContainerItemLink() return nil end
function GetContainerItemInfo() return nil end
function UseContainerItem() end
function GetSendMailItem() return nil end
function ChatEdit_InsertLink(link) _G.__insertedLink = link; return true end
function ChatEdit_GetActiveWindow() return nil end
function HandleModifiedItemClick() return false end

-- Misc UI ----------------------------------------------------------------
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_Initialize(frame, fn) frame.__init = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) _G.__dropdownButtons = _G.__dropdownButtons or {}; table.insert(_G.__dropdownButtons, info) end
function UIDropDownMenu_SetSelectedValue(frame, v) frame.__selected = v end
function UIDropDownMenu_SetText(frame, t) frame.__text = t end
function UIDropDownMenu_GetSelectedValue(frame) return frame.__selected end
function ToggleDropDownMenu() end
function CloseDropDownMenus() end
function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_SetOffset() end
function PlaySound() end
function IsShiftKeyDown() return _G.__shiftDown == true end
function IsControlKeyDown() return false end
function InCombatLockdown() return false end

RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
ITEM_BIND_ON_EQUIP = "Binds when equipped"
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
