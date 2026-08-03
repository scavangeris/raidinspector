local addonName = ...

RaidInspector = RaidInspector or {}
RaidInspectorDB = RaidInspectorDB or {}

local addon = RaidInspector
addon.name = addonName or "RaidInspector"
addon.version = "0.16.0-alpha"

local events = CreateFrame("Frame")
local FRESHNESS_TTL_SECONDS = 30 * 60
local RAID_HISTORY_RETENTION_SECONDS = 30 * 24 * 60 * 60
local INSPECT_THROTTLE_SECONDS = 2
local INSPECT_TIMEOUT_SECONDS = 8
local INSPECT_TALENT_MIN_WAIT_SECONDS = 1
local INSPECT_TALENT_GRACE_SECONDS = 3
local INSPECT_RETRY_INTERVAL_SECONDS = 15

-- Failure reasons that are transient (out of range, unit token gone, no reply in
-- time). Entries stuck on one of these are swept back into the inspect queue by
-- addon:RetryPendingInspects() as soon as the player becomes inspectable again.
local INSPECT_RETRY_REASONS = {
    ["cannot-inspect"] = true,
    ["unit-not-found"] = true,
    ["unit-changed"] = true,
    ["inspect-timeout"] = true,
    -- The inspect "succeeded" but the client handed back no gear at all, which
    -- is what an out-of-range unit looks like. Treated as transient so the
    -- player is re-inspected instead of being left with an empty item list.
    ["inspect-empty"] = true,
}

-- Autoscan: re-runs the raid scan on its own while enabled.
local AUTOSCAN_IDLE_SECONDS = 10
local AUTOSCAN_ROSTER_DEBOUNCE_SECONDS = 2
local DEFAULT_LFM_POST_DELAY_SECONDS = 10
local LFM_GENERAL_ALIASES = { "general" }
local LFM_GLOBAL_ALIASES = { "global", "globalchat", "world", "worldchat" }
local LFM_NEED_GROUPS = {
    {
        key = "warrior",
        label = "Warrior",
        output = "Warrior",
        classToken = "WARRIOR",
        items = {
            { key = "warrior_prot", label = "Prot", output = "prot" },
            { key = "warrior_fury", label = "Fury", output = "fury" },
            { key = "warrior_arms", label = "Arms", output = "arms" },
        },
    },
    {
        key = "paladin",
        label = "Paladin",
        output = "Paladin",
        classToken = "PALADIN",
        items = {
            { key = "paladin_holy", label = "Holy", output = "holy" },
            { key = "paladin_prot", label = "Prot", output = "prot" },
            { key = "paladin_ret", label = "Ret", output = "ret" },
        },
    },
    {
        key = "deathknight",
        label = "Death Knight",
        output = "Death Knight",
        classToken = "DEATHKNIGHT",
        items = {
            { key = "dk_blood", label = "Blood", output = "blood" },
            { key = "dk_frost", label = "Frost", output = "frost" },
            { key = "dk_unholy", label = "Unholy", output = "unholy" },
        },
    },
    {
        key = "druid",
        label = "Druid",
        output = "Druid",
        classToken = "DRUID",
        items = {
            { key = "druid_balance", label = "Balance", output = "balance" },
            { key = "druid_feral", label = "Feral", output = "feral" },
            { key = "druid_resto", label = "Resto", output = "resto" },
        },
    },
    {
        key = "priest",
        label = "Priest",
        output = "Priest",
        classToken = "PRIEST",
        items = {
            { key = "priest_disc", label = "Disc", output = "disc" },
            { key = "priest_holy", label = "Holy", output = "holy" },
            { key = "priest_shadow", label = "Shadow", output = "shadow" },
        },
    },
    {
        key = "shaman",
        label = "Shaman",
        output = "Shaman",
        classToken = "SHAMAN",
        items = {
            { key = "shaman_elemental", label = "Elemental", output = "elemental" },
            { key = "shaman_enh", label = "Enh", output = "enh" },
            { key = "shaman_resto", label = "Resto", output = "resto" },
        },
    },
    {
        key = "hunter",
        label = "Hunter",
        output = "Hunter",
        classToken = "HUNTER",
        items = {
            { key = "hunter_bm", label = "BM", output = "bm" },
            { key = "hunter_mm", label = "MM", output = "mm" },
            { key = "hunter_surv", label = "Surv", output = "surv" },
        },
    },
    {
        key = "rogue",
        label = "Rogue",
        output = "Rogue",
        classToken = "ROGUE",
        items = {
            { key = "rogue_assa", label = "Assa", output = "assa" },
            { key = "rogue_combat", label = "Combat", output = "combat" },
            { key = "rogue_sub", label = "Sub", output = "sub" },
        },
    },
    {
        key = "mage",
        label = "Mage",
        output = "Mage",
        classToken = "MAGE",
        items = {
            { key = "mage_arcane", label = "Arcane", output = "arcane" },
            { key = "mage_fire", label = "Fire", output = "fire" },
            { key = "mage_frost", label = "Frost", output = "frost" },
        },
    },
    {
        key = "warlock",
        label = "Warlock",
        output = "Warlock",
        classToken = "WARLOCK",
        items = {
            { key = "warlock_aff", label = "Affli", output = "affli" },
            { key = "warlock_demo", label = "Demo", output = "demo" },
            { key = "warlock_destro", label = "Destro", output = "destro" },
        },
    },
}
local LFM_ROLE_ROWS = {
    { key = "tank", label = "Tank" },
    { key = "healer", label = "Healer" },
    { key = "melee", label = "Melee" },
    { key = "ranged", label = "Ranged" },
}
local DEFAULT_LFM_REPEAT_COUNT = 1
local MIN_LFM_POST_DELAY_SECONDS = 1
local MAX_LFM_POST_DELAY_SECONDS = 3600
local MAX_LFM_REPEAT_COUNT = 99
local MAX_LFM_ROLE_CLASSES_LENGTH = 60
local REPORT_SNAPSHOT_LIMIT = 200
local REPORT_FILE_QUEUE_LIMIT = 25
local OVERVIEW_ROW_HEIGHT = 20
local OVERVIEW_VISIBLE_ROWS = 14
local OVERVIEW_BOTTOM_INSET = 28
local DETAIL_ROW_HEIGHT = 21
local WINDOW_WIDTH = 1180
local WINDOW_HEIGHT = 610
local PANEL_SIDE_MARGIN = 24
local RIGHT_PANEL_X = 474

local RAID_ACHIEVEMENT_KEYS = { "icc10", "icc25", "toc10", "toc25", "rs10", "rs25" }

local SORT_MODES = { "recent", "gs", "issues", "name", "ms" }
local FILTER_MODES = { "all", "snapshot", "ready", "queued", "issues" }
local ITEM_LIST_FILTER_MODES = { "all", "issues", "missing-enchant", "missing-gems" }

local MAIN_TAB_LABELS = {
    inspector = "Inspector",
    lfm = "LFM",
}

local SORT_LABELS = {
    recent = "Recent",
    gs = "GS",
    issues = "Issues",
    name = "Name",
    ms = "MS Changes",
}

-- MS (main spec) tracking: raid members announce a spec change by typing
-- "MS <spec>" in raid chat while registering is on.
local MS_MAX_SPEC_LENGTH = 24
local MS_REPORT_LINE_LENGTH = 230

-- Words that follow "MS" when the raid leader is opening/closing the window
-- rather than a player declaring a spec (e.g. the "MS CHANGE CLOSE" warning).
-- These must never be stored as somebody's main spec.
local MS_CONTROL_PHRASES = {
    ["change"] = true,
    ["changes"] = true,
    ["change close"] = true,
    ["changes close"] = true,
    ["change closed"] = true,
    ["change open"] = true,
    ["changes open"] = true,
    ["change now"] = true,
    ["change time"] = true,
    ["open"] = true,
    ["opened"] = true,
    ["close"] = true,
    ["closed"] = true,
    ["closing"] = true,
    ["start"] = true,
    ["stop"] = true,
    ["now"] = true,
    -- Loot-rule chatter said during the very window this feature runs in:
    -- "MS only", "ms rolls first", "ms or os?", "MS over OS".
    ["only"] = true,
    ["roll"] = true,
    ["rolls"] = true,
    ["rolling"] = true,
    ["or"] = true,
    ["over"] = true,
    ["before"] = true,
    ["after"] = true,
    ["and"] = true,
    ["vs"] = true,
    ["prio"] = true,
    ["priority"] = true,
    -- Our own broadcast header ("MS changes (3): ...") - see SanitizeSpecText.
    ["changed"] = true,
}

local FILTER_LABELS = {
    all = "All",
    snapshot = "Snapshot",
    ready = "Ready",
    queued = "Queued",
    issues = "Issues",
}

local ITEM_LIST_FILTER_LABELS = {
    all = "All Slots",
    issues = "Issues Only",
    ["missing-enchant"] = "Missing Enchant",
    ["missing-gems"] = "Missing Gems",
}

-- Bindable action buttons (screenshot: PallyPower-style keybinds).
local KEYBIND_ACTIONS = {
    { key = "target", label = "Target", button = "RaidInspectorTargetButton" },
    { key = "raid", label = "Raid", button = "RaidInspectorRaidButton" },
    { key = "share", label = "Share", button = "RaidInspectorSyncButton" },
    { key = "saveall", label = "Save All", button = "RaidInspectorReportButton" },
    { key = "clear", label = "Clear", button = "RaidInspectorClearButton" },
}
local MIN_WINDOW_SCALE = 0.5
local MAX_WINDOW_SCALE = 1.5
local DEFAULT_WINDOW_SCALE = 1.0

-- Fixed columns for the gear detail list (aligned fields).
local DETAIL_COLUMNS = {
    { key = "slot", header = "Slot", x = 4, width = 72 },
    { key = "name", header = "Item Name", x = 78, width = 312, truncate = true },
    { key = "ilvl", header = "iLvl", x = 394, width = 44 },
    { key = "enchant", header = "Enchant", x = 440, width = 92 },
    { key = "gems", header = "Gems", x = 534, width = 104 },
}

local SLOT_ORDER = {
    "HeadSlot",
    "NeckSlot",
    "ShoulderSlot",
    "BackSlot",
    "ChestSlot",
    "WristSlot",
    "HandsSlot",
    "WaistSlot",
    "LegsSlot",
    "FeetSlot",
    "Finger0Slot",
    "Finger1Slot",
    "Trinket0Slot",
    "Trinket1Slot",
    "MainHandSlot",
    "SecondaryHandSlot",
    "RangedSlot",
}

local INSPECT_SLOT_MAP = {
    { id = 1, slot = "HeadSlot" },
    { id = 2, slot = "NeckSlot" },
    { id = 3, slot = "ShoulderSlot" },
    { id = 15, slot = "BackSlot" },
    { id = 5, slot = "ChestSlot" },
    { id = 9, slot = "WristSlot" },
    { id = 10, slot = "HandsSlot" },
    { id = 6, slot = "WaistSlot" },
    { id = 7, slot = "LegsSlot" },
    { id = 8, slot = "FeetSlot" },
    { id = 11, slot = "Finger0Slot" },
    { id = 12, slot = "Finger1Slot" },
    { id = 13, slot = "Trinket0Slot" },
    { id = 14, slot = "Trinket1Slot" },
    { id = 16, slot = "MainHandSlot" },
    { id = 17, slot = "SecondaryHandSlot" },
    { id = 18, slot = "RangedSlot" },
}

local SLOT_LABELS = {
    HeadSlot = "Head",
    NeckSlot = "Neck",
    ShoulderSlot = "Shoulder",
    BackSlot = "Back",
    ChestSlot = "Chest",
    WristSlot = "Wrist",
    HandsSlot = "Hands",
    WaistSlot = "Waist",
    LegsSlot = "Legs",
    FeetSlot = "Feet",
    Finger0Slot = "Ring 1",
    Finger1Slot = "Ring 2",
    Trinket0Slot = "Trinket 1",
    Trinket1Slot = "Trinket 2",
    MainHandSlot = "Main Hand",
    SecondaryHandSlot = "Off Hand",
    RangedSlot = "Ranged/Relic",
}

local SLOT_ALIASES = {
    head = "HeadSlot",
    headslot = "HeadSlot",
    neck = "NeckSlot",
    neckslot = "NeckSlot",
    shoulder = "ShoulderSlot",
    shoulders = "ShoulderSlot",
    shoulderslot = "ShoulderSlot",
    back = "BackSlot",
    cloak = "BackSlot",
    backslot = "BackSlot",
    chest = "ChestSlot",
    chestslot = "ChestSlot",
    wrist = "WristSlot",
    wrists = "WristSlot",
    wristslot = "WristSlot",
    hands = "HandsSlot",
    handslot = "HandsSlot",
    handsslot = "HandsSlot",
    gloves = "HandsSlot",
    gloveslot = "HandsSlot",
    waist = "WaistSlot",
    beltslot = "WaistSlot",
    waistslot = "WaistSlot",
    legs = "LegsSlot",
    legslot = "LegsSlot",
    legsslot = "LegsSlot",
    feet = "FeetSlot",
    footslot = "FeetSlot",
    feetslot = "FeetSlot",
    boots = "FeetSlot",
    finger0 = "Finger0Slot",
    finger0slot = "Finger0Slot",
    finger1 = "Finger1Slot",
    finger1slot = "Finger1Slot",
    trinket0 = "Trinket0Slot",
    trinket0slot = "Trinket0Slot",
    trinket1 = "Trinket1Slot",
    trinket1slot = "Trinket1Slot",
    mainhand = "MainHandSlot",
    mainhandslot = "MainHandSlot",
    secondaryhand = "SecondaryHandSlot",
    offhand = "SecondaryHandSlot",
    offhandslot = "SecondaryHandSlot",
    secondaryhandslot = "SecondaryHandSlot",
    ranged = "RangedSlot",
    rangedslot = "RangedSlot",
    relic = "RangedSlot",
}

local ENCHANTABLE_SLOTS = {
    HeadSlot = true,
    ShoulderSlot = true,
    BackSlot = true,
    ChestSlot = true,
    WristSlot = true,
    HandsSlot = true,
    LegsSlot = true,
    FeetSlot = true,
    MainHandSlot = true,
    SecondaryHandSlot = true,
    RangedSlot = true,
}

local OPTIONAL_ENCHANT_SLOTS = {
    SecondaryHandSlot = true,
    RangedSlot = true,
}

local GS_SCALE = 1.8618
local GS_FORMULA_A = {
    [4] = { A = 91.45, B = 0.65 },
    [3] = { A = 81.375, B = 0.8125 },
    [2] = { A = 73.0, B = 1.0 },
}
local GS_FORMULA_B = {
    [4] = { A = 26.0, B = 1.2 },
    [3] = { A = 0.75, B = 1.8 },
    [2] = { A = 8.0, B = 2.0 },
    [1] = { A = 0.0, B = 2.25 },
}
local GS_SLOT_CONFIG = {
    HeadSlot = { slotMod = 1.0, enchantable = true },
    NeckSlot = { slotMod = 0.5625, enchantable = false },
    ShoulderSlot = { slotMod = 0.75, enchantable = true },
    BackSlot = { slotMod = 0.5625, enchantable = true },
    ChestSlot = { slotMod = 1.0, enchantable = true },
    WristSlot = { slotMod = 0.5625, enchantable = true },
    HandsSlot = { slotMod = 0.75, enchantable = true },
    WaistSlot = { slotMod = 0.75, enchantable = false },
    LegsSlot = { slotMod = 1.0, enchantable = true },
    FeetSlot = { slotMod = 0.75, enchantable = true },
    Finger0Slot = { slotMod = 0.5625, enchantable = false },
    Finger1Slot = { slotMod = 0.5625, enchantable = false },
    Trinket0Slot = { slotMod = 0.5625, enchantable = false },
    Trinket1Slot = { slotMod = 0.5625, enchantable = false },
    MainHandSlot = { slotMod = 1.0, enchantable = true },
    SecondaryHandSlot = { slotMod = 1.0, enchantable = false },
    RangedSlot = { slotMod = 0.3164, enchantable = false },
}

local GS_EQUIPLOC_CONFIG = {
    INVTYPE_RELIC = { slotMod = 0.3164, enchantable = false },
    INVTYPE_TRINKET = { slotMod = 0.5625, enchantable = false },
    INVTYPE_2HWEAPON = { slotMod = 2.0, enchantable = true },
    INVTYPE_WEAPONMAINHAND = { slotMod = 1.0, enchantable = true },
    INVTYPE_WEAPONOFFHAND = { slotMod = 1.0, enchantable = true },
    INVTYPE_RANGED = { slotMod = 0.3164, enchantable = true },
    INVTYPE_THROWN = { slotMod = 0.3164, enchantable = false },
    INVTYPE_RANGEDRIGHT = { slotMod = 0.3164, enchantable = false },
    INVTYPE_SHIELD = { slotMod = 1.0, enchantable = true },
    INVTYPE_WEAPON = { slotMod = 1.0, enchantable = true },
    INVTYPE_HOLDABLE = { slotMod = 1.0, enchantable = false },
    INVTYPE_HEAD = { slotMod = 1.0, enchantable = true },
    INVTYPE_NECK = { slotMod = 0.5625, enchantable = false },
    INVTYPE_SHOULDER = { slotMod = 0.75, enchantable = true },
    INVTYPE_CHEST = { slotMod = 1.0, enchantable = true },
    INVTYPE_ROBE = { slotMod = 1.0, enchantable = true },
    INVTYPE_WAIST = { slotMod = 0.75, enchantable = false },
    INVTYPE_LEGS = { slotMod = 1.0, enchantable = true },
    INVTYPE_FEET = { slotMod = 0.75, enchantable = true },
    INVTYPE_WRIST = { slotMod = 0.5625, enchantable = true },
    INVTYPE_HAND = { slotMod = 0.75, enchantable = true },
    INVTYPE_FINGER = { slotMod = 0.5625, enchantable = false },
    INVTYPE_CLOAK = { slotMod = 0.5625, enchantable = true },
}

local function GetFauxScrollOffset(scrollFrame)
    if not scrollFrame then
        return 0
    end
    if FauxScrollFrame_GetOffset then
        return tonumber(FauxScrollFrame_GetOffset(scrollFrame)) or 0
    end
    return 0
end

local function SetFauxScrollOffset(scrollFrame, offset, lineHeight)
    if not scrollFrame then
        return
    end
    local normalized = math.max(0, tonumber(offset) or 0)
    if FauxScrollFrame_SetOffset then
        FauxScrollFrame_SetOffset(scrollFrame, normalized)
    else
        local row = tonumber(lineHeight) or 14
        scrollFrame:SetVerticalScroll(normalized * row)
    end
end

local function ColorText(text, color)
    return "|cff" .. color .. tostring(text) .. "|r"
end

local function RGBToHexColorCode(red, green, blue)
    local r = math.max(0, math.min(255, math.floor(((tonumber(red) or 0) * 255) + 0.5)))
    local g = math.max(0, math.min(255, math.floor(((tonumber(green) or 0) * 255) + 0.5)))
    local b = math.max(0, math.min(255, math.floor(((tonumber(blue) or 0) * 255) + 0.5)))
    return string.format("%02x%02x%02x", r, g, b)
end

local function NormalizeClassKey(value)
    local text = tostring(value or "")
    text = string.upper(text)
    return (string.gsub(text, "%s+", ""))
end

local function ResolveClassToken(classValue)
    local normalized = NormalizeClassKey(classValue)
    if normalized == "" then
        return nil
    end

    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[normalized] then
        return normalized
    end

    local sourceTables = { LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }
    local index
    for index = 1, #sourceTables do
        local source = sourceTables[index]
        if type(source) == "table" then
            local token, localizedName
            for token, localizedName in pairs(source) do
                if NormalizeClassKey(localizedName) == normalized then
                    return token
                end
            end
        end
    end

    return nil
end

local function GetClassColorCode(classValue)
    local token = ResolveClassToken(classValue)
    if not token then
        return nil
    end

    local colorInfo = nil
    if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[token] then
        colorInfo = CUSTOM_CLASS_COLORS[token]
    elseif RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
        colorInfo = RAID_CLASS_COLORS[token]
    end

    if not colorInfo then
        return nil
    end

    local colorStr = tostring(colorInfo.colorStr or "")
    if string.len(colorStr) >= 6 then
        return string.sub(colorStr, string.len(colorStr) - 5)
    end

    return RGBToHexColorCode(colorInfo.r, colorInfo.g, colorInfo.b)
end

local function ColorClassText(text, classValue)
    local colorCode = GetClassColorCode(classValue)
    if not colorCode then
        return tostring(text)
    end
    return ColorText(text, colorCode)
end

local function EscapeChatMessage(text)
    local value = tostring(text or "")
    return string.gsub(value, "|", "||")
end

local function NormalizeChannelAliasToken(value)
    local token = string.lower(tostring(value or ""))
    token = string.gsub(token, "|c%x%x%x%x%x%x%x%x", "")
    token = string.gsub(token, "|r", "")
    token = string.gsub(token, "[^a-z0-9]+", "")
    return token
end

local function FindJoinedChannelByAlias(aliasList)
    if type(aliasList) ~= "table" then
        return nil, nil
    end

    local exactAliases = {}
    local normalizedAliases = {}
    local i
    for i = 1, #aliasList do
        local alias = tostring(aliasList[i] or "")
        if alias ~= "" then
            local lowered = string.lower(alias)
            table.insert(exactAliases, lowered)
            local normalizedAlias = NormalizeChannelAliasToken(lowered)
            if normalizedAlias ~= "" then
                normalizedAliases[normalizedAlias] = true
            end
        end
    end

    if #exactAliases == 0 then
        return nil, nil
    end

    if type(GetChannelName) == "function" then
        for i = 1, #exactAliases do
            local alias = exactAliases[i]
            local ok, id = pcall(GetChannelName, alias)
            local channelId = ok and tonumber(id) or nil
            if channelId and channelId > 0 then
                local channelsByName = { GetChannelList() }
                local j
                for j = 1, #channelsByName, 3 do
                    if tonumber(channelsByName[j]) == channelId then
                        return channelId, tostring(channelsByName[j + 1] or alias)
                    end
                end
                return channelId, alias
            end
        end
    end

    if type(GetChannelList) ~= "function" then
        return nil, nil
    end

    local channels = { GetChannelList() }
    for i = 1, #channels, 3 do
        local channelId = tonumber(channels[i])
        local channelName = tostring(channels[i + 1] or "")
        if channelId and channelId > 0 and channelName ~= "" then
            local normalizedName = string.lower(channelName)
            local idx
            for idx = 1, #exactAliases do
                local alias = exactAliases[idx]
                if string.find(normalizedName, alias, 1, true) then
                    return channelId, channelName
                end
            end

            local normalizedToken = NormalizeChannelAliasToken(channelName)
            if normalizedAliases[normalizedToken] then
                return channelId, channelName
            end

            local normalizedAlias
            for normalizedAlias in pairs(normalizedAliases) do
                if string.find(normalizedToken, normalizedAlias, 1, true) then
                    return channelId, channelName
                end
            end
        end
    end

    return nil, nil
end

local function SetFontStringBold(fontString, enabled)
    if not fontString or not fontString.GetFont or not fontString.SetFont then
        return
    end

    local fontName, fontHeight = fontString:GetFont()
    if not fontName or not fontHeight then
        return
    end

    if enabled then
        fontString:SetFont(fontName, fontHeight, "OUTLINE")
    else
        fontString:SetFont(fontName, fontHeight, "")
    end
end

local GS_LITE_QUALITY = {
    [1000] = {
        Red = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Green = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Blue = { A = 0.55, B = 0, C = 0.00045, D = 1 },
    },
    [2000] = {
        Red = { A = 1.00, B = 1000, C = 0.00088, D = -1 },
        Green = { A = 1.00, B = 0, C = 0.0, D = 0 },
        Blue = { A = 1.00, B = 1000, C = 0.001, D = -1 },
    },
    [3000] = {
        Red = { A = 0.12, B = 2000, C = 0.00012, D = -1 },
        Green = { A = 1.00, B = 2000, C = 0.00050, D = -1 },
        Blue = { A = 0.00, B = 2000, C = 0.001, D = 1 },
    },
    [4000] = {
        Red = { A = 0.00, B = 3000, C = 0.00069, D = 1 },
        Green = { A = 0.50, B = 3000, C = 0.00022, D = -1 },
        Blue = { A = 1.00, B = 3000, C = 0.00003, D = -1 },
    },
    [5000] = {
        Red = { A = 0.69, B = 4000, C = 0.00025, D = 1 },
        Green = { A = 0.28, B = 4000, C = 0.00019, D = 1 },
        Blue = { A = 0.97, B = 4000, C = 0.00096, D = -1 },
    },
    [6000] = {
        Red = { A = 0.94, B = 5000, C = 0.00006, D = 1 },
        Green = { A = 0.47, B = 5000, C = 0.00047, D = -1 },
        Blue = { A = 0.00, B = 0, C = 0.0, D = 0 },
    },
}

local function Clamp01(value)
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

local function GetGearScoreLiteColorRGB(score)
    local itemScore = tonumber(score)
    if not itemScore then
        return 0.1, 0.1, 0.1
    end

    if itemScore > 5999 then
        itemScore = 5999
    end

    local i
    for i = 0, 6 do
        local minScore = i * 1000
        local maxScore = (i + 1) * 1000
        if itemScore > minScore and itemScore <= maxScore then
            local q = GS_LITE_QUALITY[maxScore]
            if not q then
                break
            end

            -- Preserve GearScoreLite channel math/order for visual parity.
            local red = q.Red.A + (((itemScore - q.Red.B) * q.Red.C) * q.Red.D)
            local blue = q.Green.A + (((itemScore - q.Green.B) * q.Green.C) * q.Green.D)
            local green = q.Blue.A + (((itemScore - q.Blue.B) * q.Blue.C) * q.Blue.D)
            return Clamp01(red), Clamp01(green), Clamp01(blue)
        end
    end

    return 0.1, 0.1, 0.1
end

local function GetGearScoreColorCode(score)
    local red, green, blue = GetGearScoreLiteColorRGB(score)
    local r = math.floor((red * 255) + 0.5)
    local g = math.floor((green * 255) + 0.5)
    local b = math.floor((blue * 255) + 0.5)
    return string.format("%02x%02x%02x", r, g, b)
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Raid Inspector|r: " .. tostring(msg))
end

local function SafeInvoke(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        Print((label or "operation") .. " failed: " .. tostring(err))
    end
    return ok
end

local function Trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function GetNow()
    return time()
end

local function CanInspectUnit(unit)
    if not CanInspect then
        return false
    end

    -- 3.3.5 clients commonly expose CanInspect(unit) only.
    local ok, result = pcall(CanInspect, unit, false)
    if ok then
        return result and true or false
    end

    local okLegacy, resultLegacy = pcall(CanInspect, unit)
    if okLegacy then
        return resultLegacy and true or false
    end

    return false
end

local function GetInspectTalentGroup(unit)
    if type(GetActiveTalentGroup) ~= "function" or not UnitExists(unit) then
        return nil
    end

    local isInspect = not UnitIsUnit("player", unit)
    local ok, group = pcall(GetActiveTalentGroup, isInspect)
    if ok and tonumber(group) and tonumber(group) > 0 then
        return tonumber(group)
    end

    ok, group = pcall(GetActiveTalentGroup)
    if ok and tonumber(group) and tonumber(group) > 0 then
        return tonumber(group)
    end

    return nil
end

local function GetInspectTalentTabCount(unit)
    if type(GetNumTalentTabs) ~= "function" or not UnitExists(unit) then
        return 0
    end

    local isInspect = not UnitIsUnit("player", unit)
    local ok, count = pcall(GetNumTalentTabs, isInspect)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    ok, count = pcall(GetNumTalentTabs)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    return 0
end

local function GetInspectTalentTabInfo(unit, index, explicitGroup)
    if type(GetTalentTabInfo) ~= "function" or not UnitExists(unit) then
        return nil, 0
    end

    local isInspect = not UnitIsUnit("player", unit)
    local group = explicitGroup or GetInspectTalentGroup(unit)

    local ok, name, _, points = pcall(GetTalentTabInfo, index, isInspect, nil, group)
    if ok and name then
        return name, tonumber(points) or 0
    end

    ok, name, _, points = pcall(GetTalentTabInfo, index, isInspect)
    if ok and name then
        return name, tonumber(points) or 0
    end

    ok, name, _, points = pcall(GetTalentTabInfo, index)
    if ok and name then
        return name, tonumber(points) or 0
    end

    return nil, 0
end

local function NormalizeTalentToken(text)
    local lowered = string.lower(tostring(text or ""))
    lowered = string.gsub(lowered, "[^a-z0-9]+", "")
    return lowered
end

local function GetInspectTalentCount(unit, tabIndex, explicitGroup)
    if type(GetNumTalents) ~= "function" or not UnitExists(unit) then
        return 0
    end

    local isInspect = not UnitIsUnit("player", unit)
    local group = explicitGroup or GetInspectTalentGroup(unit)

    local ok, count = pcall(GetNumTalents, tabIndex, isInspect, nil, group)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    ok, count = pcall(GetNumTalents, tabIndex, isInspect, group)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    ok, count = pcall(GetNumTalents, tabIndex, isInspect)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    ok, count = pcall(GetNumTalents, tabIndex)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    return 0
end

local function GetInspectTalentInfo(unit, tabIndex, talentIndex, explicitGroup)
    if type(GetTalentInfo) ~= "function" or not UnitExists(unit) then
        return nil, 0, 0
    end

    local isInspect = not UnitIsUnit("player", unit)
    local group = explicitGroup or GetInspectTalentGroup(unit)

    local ok, name, _, _, _, rank, maxRank = pcall(GetTalentInfo, tabIndex, talentIndex, isInspect, nil, group)
    if ok and name then
        return name, tonumber(rank) or 0, tonumber(maxRank) or 0
    end

    ok, name, _, _, _, rank, maxRank = pcall(GetTalentInfo, tabIndex, talentIndex, isInspect, group)
    if ok and name then
        return name, tonumber(rank) or 0, tonumber(maxRank) or 0
    end

    ok, name, _, _, _, rank, maxRank = pcall(GetTalentInfo, tabIndex, talentIndex, isInspect)
    if ok and name then
        return name, tonumber(rank) or 0, tonumber(maxRank) or 0
    end

    ok, name, _, _, _, rank, maxRank = pcall(GetTalentInfo, tabIndex, talentIndex)
    if ok and name then
        return name, tonumber(rank) or 0, tonumber(maxRank) or 0
    end

    return nil, 0, 0
end

local function BuildInspectTalentTabMap(unit, tabIndex, explicitGroup)
    local talentCount = GetInspectTalentCount(unit, tabIndex, explicitGroup)
    local talents = {}
    local i
    for i = 1, talentCount do
        local talentName, rank, maxRank = GetInspectTalentInfo(unit, tabIndex, i, explicitGroup)
        local key = NormalizeTalentToken(talentName)
        if key ~= "" then
            talents[key] = {
                name = talentName,
                rank = rank,
                maxRank = maxRank,
            }
        end
    end
    return talents
end

local function BuildInspectTalentSnapshot(unit, explicitGroup)
    local numTabs = GetInspectTalentTabCount(unit)
    if numTabs <= 0 then
        return nil
    end

    local snapshot = {
        group = explicitGroup,
        totalPoints = 0,
        bestName = nil,
        bestPoints = -1,
        bestIndex = nil,
        points = {},
        tabs = {},
    }

    local i
    for i = 1, numTabs do
        local name, spent = GetInspectTalentTabInfo(unit, i, explicitGroup)
        spent = tonumber(spent) or 0
        snapshot.points[#snapshot.points + 1] = spent
        snapshot.tabs[i] = {
            name = name,
            spent = spent,
            talents = BuildInspectTalentTabMap(unit, i, explicitGroup),
        }
        snapshot.totalPoints = snapshot.totalPoints + spent
        if name and spent > snapshot.bestPoints then
            snapshot.bestName = tostring(name)
            snapshot.bestPoints = spent
            snapshot.bestIndex = i
        end
    end

    return snapshot
end

local function DetectUnitSpecFromTalents(unit)
    if not UnitExists(unit) then
        return nil
    end

    local triedGroups = {}
    local candidateGroups = {}
    local activeGroup = GetInspectTalentGroup(unit)
    if activeGroup and activeGroup >= 1 then
        candidateGroups[#candidateGroups + 1] = activeGroup
        triedGroups[activeGroup] = true
    end
    if not triedGroups[1] then
        candidateGroups[#candidateGroups + 1] = 1
        triedGroups[1] = true
    end
    if not triedGroups[2] then
        candidateGroups[#candidateGroups + 1] = 2
        triedGroups[2] = true
    end
    candidateGroups[#candidateGroups + 1] = nil

    local bestSnapshot = nil
    local i
    for i = 1, #candidateGroups do
        local snapshot = BuildInspectTalentSnapshot(unit, candidateGroups[i])
        if snapshot and snapshot.totalPoints > 0 then
            if not bestSnapshot or snapshot.totalPoints > bestSnapshot.totalPoints then
                bestSnapshot = snapshot
            end
        end
    end

    if not bestSnapshot or not bestSnapshot.bestName or bestSnapshot.bestPoints <= 0 then
        return nil
    end

    local pointText = {}
    for i = 1, #bestSnapshot.points do
        pointText[#pointText + 1] = tostring(bestSnapshot.points[i])
    end

    local _, englishClass = UnitClass(unit)
    local classToken = ResolveClassToken(englishClass)
    local bestName = bestSnapshot.bestName
    local bestNameToken = NormalizeTalentToken(bestName)
    local bestTab = bestSnapshot.tabs and bestSnapshot.tabs[tonumber(bestSnapshot.bestIndex) or 0]

    if bestNameToken == "feralcombat" or bestNameToken == "feral" then
        local feralTab = bestTab
        local thickHide = feralTab and feralTab.talents and feralTab.talents["thickhide"]
        if type(thickHide) == "table" and tonumber(thickHide.maxRank) and tonumber(thickHide.maxRank) > 0 then
            if tonumber(thickHide.rank) >= tonumber(thickHide.maxRank) then
                bestName = "Feral Tank"
            else
                bestName = "Feral DPS"
            end
        end
    end

    if classToken == "DEATHKNIGHT" and bestNameToken == "blood" then
        local bloodTalents = bestTab and bestTab.talents or nil
        local vampiricBlood = bloodTalents and bloodTalents["vampiricblood"]
        local willOfNecropolis = bloodTalents and bloodTalents["willofthenecropolis"]
        local improvedRuneTap = bloodTalents and bloodTalents["improvedrunetap"]
        local heartStrike = bloodTalents and bloodTalents["heartstrike"]

        local hasTankMarkers = (type(vampiricBlood) == "table" and tonumber(vampiricBlood.rank) and tonumber(vampiricBlood.rank) > 0)
            or (type(willOfNecropolis) == "table" and tonumber(willOfNecropolis.rank) and tonumber(willOfNecropolis.rank) > 0)
            or (type(improvedRuneTap) == "table" and tonumber(improvedRuneTap.rank) and tonumber(improvedRuneTap.rank) > 0)

        local hasHeartStrike = type(heartStrike) == "table" and tonumber(heartStrike.rank) and tonumber(heartStrike.rank) > 0

        if hasTankMarkers then
            bestName = "Blood Tank"
        elseif hasHeartStrike then
            bestName = "Blood DPS"
        end
    end

    if classToken == "PALADIN" and bestNameToken == "protection" then
        local protTalents = bestTab and bestTab.talents or nil
        local holyShield = protTalents and protTalents["holyshield"]
        local ardentDefender = protTalents and protTalents["ardentdefender"]
        local touchedByLight = protTalents and protTalents["touchedbythelight"]

        local hasTankMarkers = (type(holyShield) == "table" and tonumber(holyShield.rank) and tonumber(holyShield.rank) > 0)
            or (type(ardentDefender) == "table" and tonumber(ardentDefender.rank) and tonumber(ardentDefender.rank) > 0)
            or (type(touchedByLight) == "table" and tonumber(touchedByLight.rank) and tonumber(touchedByLight.rank) > 0)

        if hasTankMarkers then
            bestName = "Protection Tank"
        else
            bestName = "Protection DPS"
        end
    end

    if classToken == "PALADIN" and bestNameToken == "holy" then
        local holyTalents = bestTab and bestTab.talents or nil
        local beaconOfLight = holyTalents and holyTalents["beaconoflight"]
        local sacredCleansing = holyTalents and holyTalents["sacredcleansing"]

        local hasHealerMarkers = (type(beaconOfLight) == "table" and tonumber(beaconOfLight.rank) and tonumber(beaconOfLight.rank) > 0)
            or (type(sacredCleansing) == "table" and tonumber(sacredCleansing.rank) and tonumber(sacredCleansing.rank) > 0)

        if hasHealerMarkers then
            bestName = "Holy Healer"
        else
            bestName = "Holy DPS"
        end
    end

    return tostring(bestName) .. " (" .. table.concat(pointText, "/") .. ")"
end

local function HasInspectTalentData(unit)
    if not UnitExists(unit) then
        return false
    end

    local activeGroup = GetInspectTalentGroup(unit)
    local groups = { activeGroup, 1, 2, nil }
    local seen = {}
    local i
    for i = 1, #groups do
        local group = groups[i]
        local key = tostring(group)
        if not seen[key] then
            seen[key] = true
            local snapshot = BuildInspectTalentSnapshot(unit, group)
            if snapshot and snapshot.totalPoints > 0 then
                return true
            end
        end
    end

    return false
end

local function MakePlayerKey(name, realm)
    return string.lower(name .. "-" .. realm)
end

local function EnsureTable(tbl, key, defaultValue)
    if tbl[key] == nil then
        tbl[key] = defaultValue
    end
end

-- True when both tables hold exactly the same set of player keys.
local function MemberSetsMatch(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end

    local key
    for key in pairs(a) do
        if not b[key] then
            return false
        end
    end
    for key in pairs(b) do
        if not a[key] then
            return false
        end
    end

    return true
end

local function EnsureLFMNeedDefaults(lfmState)
    EnsureTable(lfmState, "needs", {})
    EnsureTable(lfmState.needs, "groups", {})
    EnsureTable(lfmState.needs, "items", {})

    local i
    for i = 1, #LFM_NEED_GROUPS do
        local group = LFM_NEED_GROUPS[i]
        EnsureTable(lfmState.needs.groups, group.key, false)

        local j
        for j = 1, #group.items do
            local item = group.items[j]
            EnsureTable(lfmState.needs.items, item.key, false)
        end
    end
end

local function EnsureLFMRoleDefaults(lfmState)
    EnsureTable(lfmState, "roles", {})

    local i
    for i = 1, #LFM_ROLE_ROWS do
        local roleKey = LFM_ROLE_ROWS[i].key
        EnsureTable(lfmState.roles, roleKey, {})
        EnsureTable(lfmState.roles[roleKey], "count", "")
        EnsureTable(lfmState.roles[roleKey], "classes", "")
    end
end

local function CopyTable(src)
    if type(src) ~= "table" then
        return src
    end

    local out = {}
    local k
    for k in pairs(src) do
        if type(src[k]) == "table" then
            out[k] = CopyTable(src[k])
        else
            out[k] = src[k]
        end
    end
    return out
end

local function ParseKey(key)
    local name, realm = string.match(key or "", "^(.+)%-(.+)$")
    return name, realm
end

local function FormatTimestampForFileName(timestamp)
    local ts = tonumber(timestamp) or GetNow()
    if type(date) == "function" then
        return date("%Y-%m-%d_%H-%M-%S", ts)
    end
    return tostring(ts)
end

local function FormatTimestampForDisplay(timestamp)
    local ts = tonumber(timestamp) or 0
    if ts <= 0 then
        return "-"
    end
    if type(date) == "function" then
        return date("%Y-%m-%d %H:%M:%S", ts)
    end
    return tostring(ts)
end

local function BuildReportFileName(timestamp)
    return "raidinspector-report-" .. FormatTimestampForFileName(timestamp)
end

local function SortSavedReportItems(items)
    table.sort(items, function(a, b)
        local aCreated = tonumber(a and a.createdAt) or tonumber(a and a.report and a.report.createdAt) or 0
        local bCreated = tonumber(b and b.createdAt) or tonumber(b and b.report and b.report.createdAt) or 0
        if aCreated ~= bCreated then
            return aCreated > bCreated
        end
        return string.lower(tostring(a and a.fileName or "")) < string.lower(tostring(b and b.fileName or ""))
    end)
end

local function SafeText(value)
    if value == nil then
        return "?"
    end
    return tostring(value)
end

local function FormatStatusReason(reason)
    local map = {
        ["queued-manual"] = "queued",
        ["queued-target"] = "target queued",
        ["queued-snapshot"] = "raid queued",
        ["queued-refresh"] = "refresh queued",
        ["waiting-inspect"] = "waiting inspect",
        ["inspecting"] = "inspecting",
        ["cannot-inspect"] = "not inspectable, retrying",
        ["unit-not-found"] = "unit not found, retrying",
        ["unit-changed"] = "unit changed, retrying",
        ["inspect-timeout"] = "inspect timeout, retrying",
        ["inspect-empty"] = "out of range, retrying",
        ["inspect-build-failed"] = "inspect build failed",
        ["local-only"] = "not in current target, party, or raid",
    }
    if not reason or reason == "" then
        return ""
    end
    return map[reason] or tostring(reason)
end

local function FlagText(value)
    if value == true then
        return "Y"
    end
    if value == false then
        return "N"
    end
    return "?"
end

local function HasAnyKnownRaidAchievementFlags(raid)
    if type(raid) ~= "table" then
        return false
    end

    local rk
    for _, rk in ipairs(RAID_ACHIEVEMENT_KEYS) do
        local v = raid[rk]
        if v == true or v == false then
            return true
        end
    end

    return false
end

local function ResolveAchievementPointsSource(result)
    if type(result) ~= "table" then
        return "-"
    end

    if result.achievementPointsSource and tostring(result.achievementPointsSource) ~= "" then
        return tostring(result.achievementPointsSource)
    end

    if result.achievementPoints == nil then
        return "-"
    end

    if result.source and tostring(result.source) ~= "" then
        return tostring(result.source)
    end

    return "unknown"
end

local function ResolveRaidAchievementsSource(result)
    if type(result) ~= "table" then
        return "-"
    end

    local raid = result.raidAchievements
    if type(raid) == "table" and raid.source and tostring(raid.source) ~= "" then
        return tostring(raid.source)
    end

    if HasAnyKnownRaidAchievementFlags(raid) then
        return "unknown"
    end

    return "-"
end

local function FormatRaidAchievements(ach)
    if type(ach) ~= "table" then
        return "ICC10:? ICC25:? TOC10:? TOC25:? RS10:? RS25:?"
    end

    return "ICC10:" .. FlagText(ach.icc10)
        .. " ICC25:" .. FlagText(ach.icc25)
        .. " TOC10:" .. FlagText(ach.toc10)
        .. " TOC25:" .. FlagText(ach.toc25)
        .. " RS10:" .. FlagText(ach.rs10)
        .. " RS25:" .. FlagText(ach.rs25)
end

local function NormalizeSlot(slot)
    local raw = string.lower((slot or "")):gsub("_", "")
    return SLOT_ALIASES[raw]
end

local function GetRecordedEnchantId(item)
    local enchantId = tonumber(item and item.enchantId)
    if enchantId and enchantId > 0 then
        return enchantId
    end
    return nil
end

local function IsLowTierEnchant(item)
    local enchantId = GetRecordedEnchantId(item)
    local ilvl = tonumber(item.ilvl) or 0
    if not enchantId then
        return false
    end

    -- Heuristic: very low enchant IDs on high ilvl items are usually outdated enchants.
    return ilvl >= 200 and enchantId < 3000
end

local function ParseItemLinkData(link)
    local itemString = string.match(link or "", "item:([%-%d:]+)")
    if not itemString then
        return nil, nil, {}
    end

    local fields = {}
    local part
    for part in string.gmatch(itemString, "([^:]+)") do
        table.insert(fields, part)
    end

    local itemId = tonumber(fields[1] or "")
    local enchantId = tonumber(fields[2] or "")
    local gems = {}
    local i
    for i = 3, 6 do
        local gemId = tonumber(fields[i] or "")
        if gemId and gemId > 0 then
            table.insert(gems, gemId)
        end
    end

    return itemId, enchantId, gems
end

local function GetSocketCountFromItemLink(link)
    if not GetItemStats then
        return 0
    end

    local stats = GetItemStats(link)
    if type(stats) ~= "table" then
        return 0
    end

    local total = 0
    local k
    for k in pairs(stats) do
        if type(k) == "string" and string.find(k, "EMPTY_SOCKET_") then
            total = total + (tonumber(stats[k]) or 0)
        end
    end
    return total
end

local resilienceScanTooltip

-- PvP gear is identified by carrying a resilience rating. We try GetItemStats
-- first (pattern-matching any RESILIENCE stat key, since the exact key can vary),
-- then fall back to scanning a hidden tooltip for a resilience line.
local function ItemLinkHasResilience(link)
    if type(link) ~= "string" or link == "" then
        return false
    end

    if GetItemStats then
        local stats = GetItemStats(link)
        if type(stats) == "table" then
            local key, value
            for key, value in pairs(stats) do
                if type(key) == "string" and string.find(key, "RESILIENCE") and (tonumber(value) or 0) > 0 then
                    return true
                end
            end
        end
    end

    if not resilienceScanTooltip then
        resilienceScanTooltip = CreateFrame("GameTooltip", "RaidInspectorResilienceScanTooltip", UIParent, "GameTooltipTemplate")
    end

    resilienceScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    resilienceScanTooltip:ClearLines()
    resilienceScanTooltip:SetHyperlink(link)

    local lineCount = resilienceScanTooltip:NumLines() or 0
    local i
    for i = 1, lineCount do
        local fontString = _G["RaidInspectorResilienceScanTooltipTextLeft" .. tostring(i)]
        local text = fontString and fontString:GetText()
        if text and string.find(string.lower(text), "resilience", 1, true) then
            resilienceScanTooltip:Hide()
            return true
        end
    end

    resilienceScanTooltip:Hide()
    return false
end

local function EstimateGearScoreLiteItem(item)
    local slot = item.slot
    local cfg = slot and GS_SLOT_CONFIG[slot]
    local ilvl = tonumber(item.ilvl)
    if not cfg or not ilvl or ilvl <= 0 then
        return nil
    end

    local rarity = tonumber(item.quality or item.rarity)
    if not rarity then
        rarity = 4
    end

    local qualityScale = 1.0
    if rarity == 5 then
        qualityScale = 1.3
        rarity = 4
    elseif rarity == 0 or rarity == 1 then
        qualityScale = 0.005
        rarity = 2
    elseif rarity == 7 then
        rarity = 3
        ilvl = 187.05
    end

    local tableRef = ilvl > 120 and GS_FORMULA_A or GS_FORMULA_B
    local formula = tableRef[rarity]
    if not formula then
        return nil
    end

    local score = math.floor((((ilvl - formula.A) / formula.B) * cfg.slotMod * GS_SCALE * qualityScale) + 0.5)
    if score < 0 then
        score = 0
    end

    if cfg.enchantable and not GetRecordedEnchantId(item) then
        local percent = 1 + ((-2 * cfg.slotMod) / 100)
        score = math.floor((score * percent) + 0.5)
    end

    if score < 0 then
        score = 0
    end
    return score
end

local function GetGearScoreLiteEnchantPercent(itemLink, itemEquipLoc)
    local cfg = GS_EQUIPLOC_CONFIG[itemEquipLoc]
    if not cfg or not cfg.enchantable then
        return 1
    end

    local _, enchantId = ParseItemLinkData(itemLink)
    if enchantId and enchantId > 0 then
        return 1
    end

    -- Mirror GearScoreLite percent rounding exactly.
    local percent = math.floor((-2 * cfg.slotMod) * 100) / 100
    return 1 + (percent / 100)
end

local function EstimateGearScoreLiteFromItemLink(itemLink)
    if not itemLink or itemLink == "" then
        return nil
    end

    local _, _, itemRarity, itemLevel, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
    local cfg = itemEquipLoc and GS_EQUIPLOC_CONFIG[itemEquipLoc]
    if not cfg or not itemRarity or not itemLevel then
        return nil
    end

    local rarity = tonumber(itemRarity)
    local ilvl = tonumber(itemLevel)
    if not rarity or not ilvl then
        return nil
    end

    local qualityScale = 1
    if rarity == 5 then
        qualityScale = 1.3
        rarity = 4
    elseif rarity == 1 or rarity == 0 then
        qualityScale = 0.005
        rarity = 2
    elseif rarity == 7 then
        rarity = 3
        ilvl = 187.05
    end

    if rarity < 2 or rarity > 4 then
        return nil
    end

    local tableRef = ilvl > 120 and GS_FORMULA_A or GS_FORMULA_B
    local formula = tableRef[rarity]
    if not formula then
        return nil
    end

    local score = math.floor(((ilvl - formula.A) / formula.B) * cfg.slotMod * GS_SCALE * qualityScale)
    if score < 0 then
        score = 0
    end

    local enchantPercent = GetGearScoreLiteEnchantPercent(itemLink, itemEquipLoc)
    score = math.floor(score * enchantPercent)
    if score < 0 then
        score = 0
    end

    return score
end

local function EstimateGearScoreFromUnit(unit, classToken)
    if not UnitExists(unit) then
        return nil, "none"
    end

    local isHunter = string.lower(tostring(classToken or "")) == "hunter"
    local total = 0
    local itemCount = 0
    local titanGrip = 1

    local mhLink = GetInventoryItemLink(unit, 16)
    local ohLink = GetInventoryItemLink(unit, 17)

    if mhLink and ohLink then
        local _, _, _, _, _, _, _, _, mhEquipLoc = GetItemInfo(mhLink)
        if mhEquipLoc == "INVTYPE_2HWEAPON" then
            titanGrip = 0.5
        end
    end

    if ohLink then
        local _, _, _, _, _, _, _, _, ohEquipLoc = GetItemInfo(ohLink)
        if ohEquipLoc == "INVTYPE_2HWEAPON" then
            titanGrip = 0.5
        end

        local offScore = EstimateGearScoreLiteFromItemLink(ohLink)
        if offScore then
            local score = offScore
            if isHunter then
                score = score * 0.3164
            end
            total = total + (score * titanGrip)
            itemCount = itemCount + 1
        end
    end

    local slotId
    for slotId = 1, 18 do
        if slotId ~= 4 and slotId ~= 17 then
            local itemLink = GetInventoryItemLink(unit, slotId)
            if itemLink then
                local itemScore = EstimateGearScoreLiteFromItemLink(itemLink)
                if itemScore then
                    local score = itemScore
                    if slotId == 16 and isHunter then
                        score = score * 0.3164
                    elseif slotId == 18 and isHunter then
                        score = score * 5.3224
                    end
                    if slotId == 16 then
                        score = score * titanGrip
                    end
                    total = total + score
                    itemCount = itemCount + 1
                end
            end
        end
    end

    if itemCount <= 0 then
        return nil, "none"
    end

    return math.floor(total), "estimated-gearscorelite"
end

local function EstimateGearScoreFromItems(items, classToken)
    local classLower = string.lower(tostring(classToken or ""))
    local isHunter = classLower == "hunter"
    local totalLite = 0
    local liteCount = 0
    local ilvls = {}
    local i

    for i = 1, #items do
        local item = items[i]
        local lite = EstimateGearScoreLiteItem(item)
        if lite then
            local score = lite
            if isHunter and item.slot == "MainHandSlot" then
                score = score * 0.3164
            elseif isHunter and item.slot == "RangedSlot" then
                score = score * 5.3224
            end
            totalLite = totalLite + score
            liteCount = liteCount + 1
        end

        local ilvl = tonumber(item.ilvl)
        if ilvl and ilvl > 0 then
            table.insert(ilvls, ilvl)
        end
    end

    if liteCount > 0 then
        return math.floor(totalLite + 0.5), "estimated-gearscorelite"
    end

    if #ilvls == 0 then
        return nil, "none"
    end

    local sum = 0
    for i = 1, #ilvls do
        sum = sum + ilvls[i]
    end

    local avg = sum / #ilvls
    return math.floor(avg * 20 + 0.5), "estimated-ilvl"
end

local function AnalyzeItemIssues(items)
    local missingEnchant = 0
    local missingGems = 0
    local itemsWithoutSlot = 0
    local itemsWithSockets = 0
    local totalSockets = 0
    local filledSockets = 0
    local pvpItems = 0
    local i

    for i = 1, #items do
        local item = items[i]
        local slot = item.slot
        local socketCount = tonumber(item.socketCount) or 0
        local gemCount = type(item.gems) == "table" and #item.gems or 0

        if not slot or slot == "" then
            itemsWithoutSlot = itemsWithoutSlot + 1
        elseif ENCHANTABLE_SLOTS[slot] and not OPTIONAL_ENCHANT_SLOTS[slot] and not GetRecordedEnchantId(item) then
            missingEnchant = missingEnchant + 1
        end

        if socketCount > 0 then
            itemsWithSockets = itemsWithSockets + 1
            totalSockets = totalSockets + socketCount
            filledSockets = filledSockets + math.min(socketCount, gemCount)
            if gemCount < socketCount then
                missingGems = missingGems + (socketCount - gemCount)
            end
        end

        if item.isPvp then
            pvpItems = pvpItems + 1
        end
    end

    return {
        missingEnchant = missingEnchant,
        missingGems = missingGems,
        itemsWithoutSlot = itemsWithoutSlot,
        itemsAnalyzed = #items,
        itemsWithSockets = itemsWithSockets,
        totalSockets = totalSockets,
        filledSockets = filledSockets,
        pvpItems = pvpItems,
    }
end

function addon:InitInspectRuntime()
    addon.inspectQueue = addon.inspectQueue or {}
    addon.inspectQueuedKeys = addon.inspectQueuedKeys or {}
    addon.inspectCurrent = nil
    addon.inspectLastRequestAt = addon.inspectLastRequestAt or 0
    addon.inspectTickAccum = 0
    addon.inspectRetryAccum = 0

    addon.autoScanAccum = 0
    addon.autoScanRosterAccum = 0
    addon.autoScanRosterDirty = false

    addon.lfmPostQueue = addon.lfmPostQueue or {}
    addon.lfmPostSentCount = addon.lfmPostSentCount or 0
    addon.lfmPostSelectedCount = addon.lfmPostSelectedCount or 0
    addon.lfmPostNextAt = addon.lfmPostNextAt or 0
end

function addon:ProcessLFMPostQueue(force)
    if not addon.lfmPostQueue or #addon.lfmPostQueue == 0 then
        addon.lfmPostNextAt = 0
        return false
    end

    local now = GetNow()
    local nextAt = tonumber(addon.lfmPostNextAt) or 0
    if not force and now < nextAt then
        return false
    end

    local entry = table.remove(addon.lfmPostQueue, 1)
    if type(entry) ~= "table" then
        return false
    end

    if entry.chatType == "CHANNEL" then
        SendChatMessage(entry.message, "CHANNEL", nil, entry.channelId)
    else
        SendChatMessage(entry.message, entry.chatType)
    end

    addon.lfmPostSentCount = (tonumber(addon.lfmPostSentCount) or 0) + 1
    local postDelaySeconds = addon:GetLFMPostDelaySeconds()

    if #addon.lfmPostQueue > 0 then
        addon.lfmPostNextAt = now + postDelaySeconds
        Print("lfm: next post in " .. tostring(postDelaySeconds) .. "s (" .. tostring(#addon.lfmPostQueue) .. " remaining)")
    else
        addon.lfmPostNextAt = 0
        local selectedCount = tonumber(addon.lfmPostSelectedCount) or addon.lfmPostSentCount
        Print("lfm: posted " .. tostring(addon.lfmPostSentCount) .. "/" .. tostring(selectedCount) .. " queued post(s)")
    end

    addon:RefreshMainWindow()
    return true
end

function addon:CancelLFMPostQueue()
    local pending = addon.lfmPostQueue and #addon.lfmPostQueue or 0
    addon.lfmPostQueue = {}
    addon.lfmPostNextAt = 0

    if pending > 0 then
        Print("lfm: cancelled " .. tostring(pending) .. " pending post(s)")
    else
        Print("lfm: no pending posts to cancel")
    end

    addon:RefreshMainWindow()
    return pending
end

function addon:GetInspectLinkCount(unit)
    local count = 0
    local i
    for i = 1, #INSPECT_SLOT_MAP do
        if GetInventoryItemLink(unit, INSPECT_SLOT_MAP[i].id) then
            count = count + 1
        end
    end
    return count
end

-- "Has gear" means the scan actually read something off the unit. Used to tell
-- a real result apart from the empty shell an out-of-range inspect produces.
local function ResultHasGear(result)
    if type(result) ~= "table" then
        return false
    end
    if type(result.items) == "table" and #result.items > 0 then
        return true
    end
    return (tonumber(result.gearScore) or 0) > 0
end

local function ResultHasNoGear(result)
    return not ResultHasGear(result)
end

function addon:FinalizeInspectCurrent(success, failureReason)
    if not addon.inspectCurrent then
        return
    end

    local current = addon.inspectCurrent
    local talentDataReady = current.talentReadySeen == true
    if not talentDataReady and UnitExists(current.unit) then
        talentDataReady = HasInspectTalentData(current.unit)
    end
    addon.inspectCurrent = nil

    local req = addon:GetLatestRequestForKey(current.key)
    if success and UnitExists(current.unit) then
        local ok, resultOrErr = pcall(
            addon.BuildLocalInspectResult,
            addon,
            current.unit,
            current.key,
            current.name,
            current.realm,
            talentDataReady
        )
        if ok and type(resultOrErr) == "table" then
            local previous = RaidInspectorDB.results[current.key]

            -- An inspect on a unit that has drifted out of range still reports
            -- success, but every GetInventoryItemLink comes back nil, so the
            -- "result" is an empty shell. Writing that over a good scan is what
            -- made gear vanish from the item list. Keep the gear we already
            -- have and mark the attempt for retry instead.
            if ResultHasNoGear(resultOrErr) then
                if ResultHasGear(previous) then
                    if req then
                        req.status = "error"
                        req.statusReason = "inspect-empty"
                        req.updatedAt = GetNow()
                    end
                    addon:RefreshActiveRaidHistoryEntry()
                    if ClearInspectPlayer then
                        ClearInspectPlayer()
                    end
                    addon:RefreshMainWindow()
                    return
                end

                -- Nothing cached either: store the shell so the row exists, but
                -- flag it so RetryPendingInspects picks it up (no GS -> rescan).
                RaidInspectorDB.results[current.key] = resultOrErr
                if req then
                    req.status = "error"
                    req.statusReason = "inspect-empty"
                    req.updatedAt = GetNow()
                end
                addon:RefreshActiveRaidHistoryEntry()
                if ClearInspectPlayer then
                    ClearInspectPlayer()
                end
                addon:RefreshMainWindow()
                return
            end

            if type(previous) == "table" then
                if resultOrErr.achievementPoints == nil and previous.achievementPoints ~= nil then
                    resultOrErr.achievementPoints = previous.achievementPoints
                    resultOrErr.achievementPointsSource = previous.achievementPointsSource
                end
                if (type(resultOrErr.raidAchievements) ~= "table" or next(resultOrErr.raidAchievements) == nil)
                    and type(previous.raidAchievements) == "table" then
                    resultOrErr.raidAchievements = CopyTable(previous.raidAchievements)
                end
                if (type(resultOrErr.specificAchievements) ~= "table"
                    or (resultOrErr.specificAchievements.icc10FrozenThrone == nil
                        and resultOrErr.specificAchievements.icc10Kingslayer == nil))
                    and type(previous.specificAchievements) == "table"
                    and (
                        previous.specificAchievements.icc10FrozenThrone == true
                        or previous.specificAchievements.icc10FrozenThrone == false
                        or previous.specificAchievements.icc10Kingslayer == true
                        or previous.specificAchievements.icc10Kingslayer == false
                    ) then
                    resultOrErr.specificAchievements = CopyTable(previous.specificAchievements)
                end
            end
            RaidInspectorDB.results[current.key] = resultOrErr
            if req then
                req.status = "ready"
                req.statusReason = nil
                req.updatedAt = GetNow()
            end

            addon:RefreshActiveRaidHistoryEntry()
        else
            Print("inspect build failed: " .. tostring(resultOrErr))
            if req then
                req.status = "error"
                req.statusReason = "inspect-build-failed"
                req.updatedAt = GetNow()
            end
        end
    elseif req then
        -- A cached result from an earlier scan is not evidence that this attempt
        -- worked, so the failure is recorded either way. The result itself stays
        -- in the DB and keeps rendering; only the status reflects this attempt,
        -- so the row reads [error] next to the age instead of claiming "ready".
        req.status = "error"
        req.statusReason = failureReason or "inspect-timeout"
        req.updatedAt = GetNow()
    end

    addon:RefreshActiveRaidHistoryEntry()

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    addon:RefreshMainWindow()
end

function addon:QueueLiveInspectUnit(unit, queueRequest)
    if not UnitExists(unit) then
        return false, "unit-not-found"
    end

    if not CanInspectUnit(unit) then
        return false, "cannot-inspect"
    end

    local unitName, unitRealm = UnitName(unit)
    if not unitName or unitName == "" then
        return false, "bad-unit-name"
    end

    local realm = unitRealm
    if not realm or realm == "" then
        realm = GetRealmName() or ""
    end
    if realm == "" then
        return false, "bad-realm"
    end

    if queueRequest ~= false then
        addon:QueueInspect(unitName, realm, { allowDuplicate = false, silent = true })
    end

    local key = MakePlayerKey(unitName, realm)
    if addon.inspectQueuedKeys[key] then
        return false, "already-queued"
    end
    if addon.inspectCurrent and addon.inspectCurrent.key == key then
        return false, "already-active"
    end

    table.insert(addon.inspectQueue, {
        unit = unit,
        guid = UnitGUID(unit),
        key = key,
        name = unitName,
        realm = realm,
        queuedAt = GetNow(),
    })
    addon.inspectQueuedKeys[key] = true

    local req = addon:GetLatestRequestForKey(key)
    if req then
        req.status = "queued"
        req.statusReason = "waiting-inspect"
        req.updatedAt = GetNow()
    end

    return true
end

function addon:BuildLocalInspectResult(unit, key, name, realm, inspectTalentsReady)
    local items = {}
    local enchants = {}
    local gemsBySlot = {}
    local i

    for i = 1, #INSPECT_SLOT_MAP do
        local slotMap = INSPECT_SLOT_MAP[i]
        local itemLink = GetInventoryItemLink(unit, slotMap.id)
        if itemLink then
            local itemId, enchantId, gems = ParseItemLinkData(itemLink)
            local itemName, _, itemQuality, ilvl = GetItemInfo(itemLink)
            local socketCount = GetSocketCountFromItemLink(itemLink)

            local item = {
                slot = slotMap.slot,
                name = itemName,
            }
            if ItemLinkHasResilience(itemLink) then
                item.isPvp = true
            end
            if itemId then
                item.itemId = itemId
            end
            if ilvl and ilvl > 0 then
                item.ilvl = ilvl
            end
            if itemQuality and itemQuality >= 0 then
                item.quality = itemQuality
            end
            if enchantId and enchantId > 0 then
                item.enchantId = enchantId
                enchants[slotMap.slot] = enchantId
            end
            if socketCount and socketCount > 0 then
                item.socketCount = socketCount
            end
            if gems and #gems > 0 then
                item.gems = gems
                gemsBySlot[slotMap.slot] = gems
            end

            table.insert(items, item)
        end
    end

    local now = GetNow()
    local issueSummary = AnalyzeItemIssues(items)
    local localizedClass, englishClass = UnitClass(unit)
    local detectedSpec = nil
    if inspectTalentsReady then
        detectedSpec = DetectUnitSpecFromTalents(unit)
    end
    local estimatedGS, estimatedSource = EstimateGearScoreFromUnit(unit, englishClass)
    if not estimatedGS then
        estimatedGS, estimatedSource = EstimateGearScoreFromItems(items, englishClass)
    end

    return {
        name = name,
        realm = realm,
        class = localizedClass,
        spec = detectedSpec,
        guild = GetGuildInfo(unit),
        level = UnitLevel(unit),
        items = items,
        enchants = enchants,
        gems = gemsBySlot,
        gearScore = estimatedGS,
        gearScoreSource = estimatedSource,
        estimatedGearScore = estimatedGS,
        achievementPoints = nil,
        achievementPointsSource = nil,
        raidAchievements = {},
        specificAchievements = {},
        issuesCount = issueSummary.missingEnchant + issueSummary.missingGems,
        issueSummary = issueSummary,
        source = "local-inspect",
        fetchedAt = now,
        updatedAt = now,
    }
end

function addon:IsAutoScanEnabled()
    return RaidInspectorDB.settings
        and RaidInspectorDB.settings.autoScan
        and RaidInspectorDB.settings.autoScan.enabled == true
end

function addon:SetAutoScanEnabled(enabled)
    if not RaidInspectorDB.settings then
        return false
    end

    EnsureTable(RaidInspectorDB.settings, "autoScan", {})
    RaidInspectorDB.settings.autoScan.enabled = enabled and true or false

    addon.autoScanAccum = 0
    addon.autoScanRosterAccum = 0
    addon.autoScanRosterDirty = false

    if RaidInspectorDB.settings.autoScan.enabled then
        Print("autoscan: ON (rescans on raid join/leave, and every "
            .. AUTOSCAN_IDLE_SECONDS .. "s once the queue is idle)")
        -- Kick off the first scan immediately rather than waiting a full cycle.
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            addon:RunAutoScan()
        else
            Print("autoscan: waiting, you are not in a raid")
        end
    else
        Print("autoscan: OFF")
    end

    addon:RefreshMainWindow()
    return RaidInspectorDB.settings.autoScan.enabled
end

function addon:ToggleAutoScan()
    return addon:SetAutoScanEnabled(not addon:IsAutoScanEnabled())
end

-- The one scan autoscan performs: quiet, reuses the raid history entry, and
-- prunes players who have left the raid.
function addon:RunAutoScan()
    return addon:QueueRaidSnapshot({ silent = true, reuseHistory = true, pruneMissing = true })
end

-- Drives autoscan from addon:OnUpdate. Two triggers:
--   1. roster change (someone joined/left) - rescans once the roster settles;
--   2. idle - rescans every AUTOSCAN_IDLE_SECONDS, but only once the inspect
--      queue has drained, so it never fights the work already in flight.
function addon:ProcessAutoScan()
    if not addon:IsAutoScanEnabled() then
        addon.autoScanAccum = 0
        addon.autoScanRosterAccum = 0
        addon.autoScanRosterDirty = false
        return false
    end

    if addon:GetSelectedSavedReportFile() ~= "" then
        addon.autoScanAccum = 0
        addon.autoScanRosterAccum = 0
        return false
    end

    if not GetNumRaidMembers or GetNumRaidMembers() <= 0 then
        addon.autoScanAccum = 0
        addon.autoScanRosterAccum = 0
        addon.autoScanRosterDirty = false
        return false
    end

    if addon.autoScanRosterDirty then
        -- Roster events fire in bursts, so wait for them to settle first.
        if (addon.autoScanRosterAccum or 0) < AUTOSCAN_ROSTER_DEBOUNCE_SECONDS then
            return false
        end
        addon.autoScanRosterDirty = false
        addon.autoScanRosterAccum = 0
        addon.autoScanAccum = 0
        addon:RunAutoScan()
        return true
    end

    if addon.inspectCurrent or (addon.inspectQueue and #addon.inspectQueue > 0) then
        addon.autoScanAccum = 0
        return false
    end

    if (addon.autoScanAccum or 0) < AUTOSCAN_IDLE_SECONDS then
        return false
    end

    addon.autoScanAccum = 0
    addon:RunAutoScan()
    return true
end

-- Current raid/party member keys, in the same format the list uses, or nil when
-- we are not in a group (so an empty roster can never be mistaken for
-- "everyone left").
function addon:GetGroupMemberKeys()
    local members = {}
    local found = false
    local i

    local raidCount = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if raidCount > 0 then
        for i = 1, raidCount do
            local rosterName = GetRaidRosterInfo(i)
            if rosterName and rosterName ~= "" then
                local name = rosterName
                local realm = GetRealmName() or ""
                local splitName, splitRealm = string.match(rosterName, "^([^%-]+)%-(.+)$")
                if splitName and splitRealm then
                    name = splitName
                    realm = splitRealm
                end
                members[MakePlayerKey(name, realm)] = true
                found = true
            end
        end
        return found and members or nil
    end

    local partyCount = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    if partyCount > 0 then
        local realm = GetRealmName() or ""
        for i = 1, partyCount do
            local name = UnitName("party" .. tostring(i))
            if name and name ~= "" then
                members[MakePlayerKey(name, realm)] = true
                found = true
            end
        end
        local selfName = UnitName("player")
        if selfName and selfName ~= "" then
            members[MakePlayerKey(selfName, realm)] = true
        end
        return found and members or nil
    end

    return nil
end

-- Drops players who have left or been kicked, whether or not autoscan is on.
-- Only keys we have actually seen in the group are eligible, so a player added
-- by hand with /ri inspect (who was never in the raid) is never auto-removed.
function addon:PruneDepartedGroupMembers()
    if addon:GetSelectedSavedReportFile() ~= "" then
        -- A saved report is a snapshot; the live roster must not edit it.
        return 0
    end

    local members = addon:GetGroupMemberKeys()
    if not members then
        -- Not in a group: leaving the raid yourself must not wipe the list.
        return 0
    end

    addon.rosterSeenKeys = addon.rosterSeenKeys or {}

    local departed = {}
    local removedCount = 0
    local key

    for key in pairs(addon.rosterSeenKeys) do
        if not members[key] then
            departed[key] = true
        end
    end

    for key in pairs(members) do
        addon.rosterSeenKeys[key] = true
    end

    for key in pairs(departed) do
        addon.rosterSeenKeys[key] = nil
        if addon:RemoveOverviewEntryByKey(key, true) then
            removedCount = removedCount + 1
        end
    end

    if removedCount > 0 then
        Print("removed " .. tostring(removedCount) .. " who left the group")
        addon:RefreshMainWindow()
    end

    return removedCount
end

function addon:OnRosterChanged()
    -- Removal tracks the group regardless of autoscan; only the rescan below
    -- is an autoscan feature.
    SafeInvoke("roster-prune", function()
        addon:PruneDepartedGroupMembers()
    end)

    if not addon:IsAutoScanEnabled() then
        return
    end
    addon.autoScanRosterDirty = true
    addon.autoScanRosterAccum = 0
end

-- Sweeps every entry that failed for a transient reason (most often "not
-- inspectable", i.e. the player was out of range) and re-queues the ones that
-- have become inspectable again. Called on a timer from addon:OnUpdate, so a
-- player who walks into range is picked up without any manual refresh.
function addon:RetryPendingInspects()
    if not RaidInspectorDB.requests or not RaidInspectorDB.results or not addon.inspectQueuedKeys then
        return 0
    end

    if addon:GetSelectedSavedReportFile() ~= "" then
        return 0
    end

    local latestByKey = addon:GetLatestRequestMap()
    local requeued = 0
    local key

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local reason = tostring(req.statusReason or "")
        -- Cached data for the key is deliberately not a reason to skip: a failed
        -- attempt on someone we already know is exactly the entry whose data has
        -- gone stale, and the status reasons above all advertise "retrying".
        -- A successful scan leaves status "ready", so this never re-queues one.
        -- No gear/GS cached means the scan never really landed - including rows
        -- left behind by an older build that stored an empty result as "ready".
        -- Those are retried regardless of status, so a player only has to come
        -- into range once; a scan that did return gear is still never re-queued.
        local missingGear = ResultHasNoGear(RaidInspectorDB.results[key])
        local retryable = (INSPECT_RETRY_REASONS[reason] or missingGear)
            and (req.status == "error" or req.status == "queued" or missingGear)
            and not addon.inspectQueuedKeys[key]
            and not (addon.inspectCurrent and addon.inspectCurrent.key == key)

        if retryable then
            -- Only re-queue units that are inspectable right now, otherwise the
            -- entry would just burn a queue slot and fail again immediately.
            -- QueueLiveInspectUnit sets the request to queued/waiting-inspect
            -- itself, keyed off the unit, so no extra state write is needed here.
            local unit = addon:FindUnitByName(req.name)
            if unit and CanInspectUnit(unit) then
                if addon:QueueLiveInspectUnit(unit, false) then
                    requeued = requeued + 1
                end
            end
        end
    end

    if requeued > 0 then
        addon:ProcessInspectQueue(false)
        addon:RefreshMainWindow()
    end

    return requeued
end

function addon:ProcessInspectQueue(force)
    if addon.inspectCurrent then
        return
    end

    if not addon.inspectQueue or #addon.inspectQueue == 0 then
        return
    end

    if not force and (GetNow() - (addon.inspectLastRequestAt or 0)) < INSPECT_THROTTLE_SECONDS then
        return
    end

    local entry = table.remove(addon.inspectQueue, 1)
    if not entry then
        return
    end

    addon.inspectQueuedKeys[entry.key] = nil

    -- As in addon:FinalizeInspectCurrent, these failures are recorded whether or
    -- not older data is cached for the key. Skipping the write used to leave the
    -- request on "queued"/"waiting-inspect", which the overview then displayed as
    -- "ready" because a result existed.
    if not UnitExists(entry.unit) then
        local reqMissing = addon:GetLatestRequestForKey(entry.key)
        if reqMissing then
            reqMissing.status = "error"
            reqMissing.statusReason = "unit-not-found"
            reqMissing.updatedAt = GetNow()
        end
        return
    end

    if entry.guid and UnitGUID(entry.unit) ~= entry.guid then
        local reqGuid = addon:GetLatestRequestForKey(entry.key)
        if reqGuid then
            reqGuid.status = "error"
            reqGuid.statusReason = "unit-changed"
            reqGuid.updatedAt = GetNow()
        end
        return
    end

    if not CanInspectUnit(entry.unit) then
        local reqInspect = addon:GetLatestRequestForKey(entry.key)
        if reqInspect then
            reqInspect.status = "error"
            reqInspect.statusReason = "cannot-inspect"
            reqInspect.updatedAt = GetNow()
        end
        return
    end

    addon.inspectCurrent = {
        unit = entry.unit,
        guid = entry.guid,
        key = entry.key,
        name = entry.name,
        realm = entry.realm,
        startedAt = GetNow(),
        lastPollAt = 0,
        inspectReadySeen = false,
        inspectReadyAt = 0,
        talentReadySeen = false,
        talentReadyAt = 0,
        itemsReadyAt = 0,
    }

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
    NotifyInspect(entry.unit)

    addon.inspectLastRequestAt = GetNow()

    local req = addon:GetLatestRequestForKey(entry.key)
    if req then
        req.status = "queued"
        req.statusReason = "inspecting"
        req.updatedAt = GetNow()
    end
end

function addon:OnInspectReady(guid)
    if not addon.inspectCurrent then
        return
    end

    if guid and addon.inspectCurrent.guid and guid ~= addon.inspectCurrent.guid then
        return
    end

    addon.inspectCurrent.inspectReadySeen = true
    addon.inspectCurrent.inspectReadyAt = GetNow()
end

function addon:OnInspectTalentReady()
    if not addon.inspectCurrent then
        return
    end

    if addon.inspectCurrent.guid and UnitGUID(addon.inspectCurrent.unit) ~= addon.inspectCurrent.guid then
        return
    end

    addon.inspectCurrent.talentReadySeen = true
    addon.inspectCurrent.talentReadyAt = GetNow()
end

function addon:OnUpdate(elapsed)
    local delta = elapsed or 0
    addon.inspectRetryAccum = (addon.inspectRetryAccum or 0) + delta
    addon.autoScanAccum = (addon.autoScanAccum or 0) + delta
    addon.autoScanRosterAccum = (addon.autoScanRosterAccum or 0) + delta
    addon.inspectTickAccum = (addon.inspectTickAccum or 0) + delta
    if addon.inspectTickAccum < 0.2 then
        return
    end
    addon.inspectTickAccum = 0

    if addon.inspectRetryAccum >= INSPECT_RETRY_INTERVAL_SECONDS then
        addon.inspectRetryAccum = 0
        addon:RetryPendingInspects()
    end

    addon:ProcessAutoScan()

    if addon.inspectCurrent then
        local now = GetNow()
        if UnitExists(addon.inspectCurrent.unit) and (now - (addon.inspectCurrent.lastPollAt or 0)) >= 1 then
            addon.inspectCurrent.lastPollAt = now
            if addon:GetInspectLinkCount(addon.inspectCurrent.unit) > 0 then
                if not addon.inspectCurrent.itemsReadyAt or addon.inspectCurrent.itemsReadyAt <= 0 then
                    addon.inspectCurrent.itemsReadyAt = now
                end
            end

            local itemsReadyAt = tonumber(addon.inspectCurrent.itemsReadyAt) or 0
            if itemsReadyAt > 0 then
                local talentReadySeen = addon.inspectCurrent.talentReadySeen == true
                local talentReadyAt = tonumber(addon.inspectCurrent.talentReadyAt) or 0
                local talentWaitElapsed = talentReadySeen
                    and talentReadyAt > 0
                    and (now - talentReadyAt) >= INSPECT_TALENT_MIN_WAIT_SECONDS
                local talentGraceElapsed = talentReadySeen
                    and talentReadyAt > 0
                    and (now - talentReadyAt) >= INSPECT_TALENT_GRACE_SECONDS
                local eventMissingTooLong = (now - itemsReadyAt) >= INSPECT_TALENT_GRACE_SECONDS

                if talentReadySeen then
                    if talentWaitElapsed and (HasInspectTalentData(addon.inspectCurrent.unit) or talentGraceElapsed) then
                        addon:FinalizeInspectCurrent(true, nil)
                        addon:ProcessInspectQueue(false)
                        addon:ProcessLFMPostQueue(false)
                        return
                    end
                elseif eventMissingTooLong then
                    addon:FinalizeInspectCurrent(true, nil)
                    addon:ProcessInspectQueue(false)
                    addon:ProcessLFMPostQueue(false)
                    return
                end
            end
        end

        if (now - addon.inspectCurrent.startedAt) > INSPECT_TIMEOUT_SECONDS then
            if (tonumber(addon.inspectCurrent.itemsReadyAt) or 0) > 0 then
                addon:FinalizeInspectCurrent(true, nil)
            else
                addon:FinalizeInspectCurrent(false, "inspect-timeout")
            end
        end
    end

    addon:ProcessInspectQueue(false)

    addon:ProcessLFMPostQueue(false)
end

function addon:InitDatabase()
    EnsureTable(RaidInspectorDB, "meta", {})
    EnsureTable(RaidInspectorDB, "settings", {})
    EnsureTable(RaidInspectorDB.settings, "window", {})
    EnsureTable(RaidInspectorDB.settings.window, "point", "CENTER")
    EnsureTable(RaidInspectorDB.settings.window, "x", 0)
    EnsureTable(RaidInspectorDB.settings.window, "y", 0)
    EnsureTable(RaidInspectorDB.settings.window, "scale", 1.0)

    EnsureTable(RaidInspectorDB.settings, "keybinds", {})

    EnsureTable(RaidInspectorDB.settings, "overview", {})
    EnsureTable(RaidInspectorDB.settings.overview, "sortMode", "recent")
    EnsureTable(RaidInspectorDB.settings.overview, "filterMode", "all")

    EnsureTable(RaidInspectorDB.settings, "autoScan", {})
    EnsureTable(RaidInspectorDB.settings.autoScan, "enabled", false)

    EnsureTable(RaidInspectorDB, "state", {})
    EnsureTable(RaidInspectorDB.state, "nextRequestId", 1)
    EnsureTable(RaidInspectorDB.state, "lastSnapshot", {})
    EnsureTable(RaidInspectorDB.state.lastSnapshot, "at", 0)
    EnsureTable(RaidInspectorDB.state.lastSnapshot, "historyId", 0)
    EnsureTable(RaidInspectorDB.state.lastSnapshot, "members", {})
    EnsureTable(RaidInspectorDB.state, "ui", {})
    EnsureTable(RaidInspectorDB.state.ui, "selectedKey", "")
    EnsureTable(RaidInspectorDB.state.ui, "selectedSavedReportFile", "")
    EnsureTable(RaidInspectorDB.state.ui, "itemListFilterMode", "all")
    EnsureTable(RaidInspectorDB.state.ui, "buttonMode", "advanced")
    EnsureTable(RaidInspectorDB.state.ui, "activeTab", "inspector")
    EnsureTable(RaidInspectorDB.state.ui, "minimap", {})
    EnsureTable(RaidInspectorDB.state.ui.minimap, "angle", 220)
    EnsureTable(RaidInspectorDB.state.ui, "exportChannels", {})
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "raid", true)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "say", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "whisper", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "guild", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "rw", false)
    EnsureTable(RaidInspectorDB.state.ui, "lfm", {})
    EnsureTable(RaidInspectorDB.state.ui.lfm, "message", "")
    EnsureTable(RaidInspectorDB.state.ui.lfm, "channels", {})
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "yell", false)
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "guild", false)
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "general", true)
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "global", true)
    EnsureTable(RaidInspectorDB.state.ui.lfm, "postDelaySeconds", DEFAULT_LFM_POST_DELAY_SECONDS)
    EnsureTable(RaidInspectorDB.state.ui.lfm, "repeatCount", DEFAULT_LFM_REPEAT_COUNT)
    EnsureLFMNeedDefaults(RaidInspectorDB.state.ui.lfm)
    EnsureLFMRoleDefaults(RaidInspectorDB.state.ui.lfm)

    EnsureTable(RaidInspectorDB, "requests", {})
    EnsureTable(RaidInspectorDB, "results", {})
    EnsureTable(RaidInspectorDB, "reportSnapshots", {})
    EnsureTable(RaidInspectorDB.reportSnapshots, "nextId", 1)
    EnsureTable(RaidInspectorDB.reportSnapshots, "items", {})
    EnsureTable(RaidInspectorDB, "reportFileQueue", {})
    EnsureTable(RaidInspectorDB.reportFileQueue, "nextId", 1)
    EnsureTable(RaidInspectorDB.reportFileQueue, "items", {})
    EnsureTable(RaidInspectorDB, "savedReportFiles", {})
    EnsureTable(RaidInspectorDB.savedReportFiles, "generatedAt", 0)
    EnsureTable(RaidInspectorDB.savedReportFiles, "items", {})
    EnsureTable(RaidInspectorDB, "raidScanHistory", {})
    EnsureTable(RaidInspectorDB.raidScanHistory, "nextId", 1)
    EnsureTable(RaidInspectorDB.raidScanHistory, "scans", {})

    -- MS records live outside `results` so a rescan or Clear never drops them.
    EnsureTable(RaidInspectorDB, "msTracking", {})
    EnsureTable(RaidInspectorDB.msTracking, "enabled", false)
    EnsureTable(RaidInspectorDB.msTracking, "entries", {})
    EnsureTable(RaidInspectorDB.msTracking, "nextSeq", 1)
    EnsureTable(RaidInspectorDB.msTracking, "startedAt", 0)

    RaidInspectorDB.meta.schemaVersion = 5
    RaidInspectorDB.meta.lastLoadedAt = GetNow()
    addon:MigrateReportFileQueueToSavedReports()
    addon:PruneRaidScanHistory()
end

function addon:GetSortMode()
    local mode = RaidInspectorDB.settings.overview.sortMode
    if SORT_LABELS[mode] then
        return mode
    end
    RaidInspectorDB.settings.overview.sortMode = "recent"
    return "recent"
end

function addon:GetFilterMode()
    local mode = RaidInspectorDB.settings.overview.filterMode
    if FILTER_LABELS[mode] then
        return mode
    end
    RaidInspectorDB.settings.overview.filterMode = "all"
    return "all"
end

function addon:GetWindowScale()
    local scale = tonumber(RaidInspectorDB.settings.window.scale)
    if not scale then
        return DEFAULT_WINDOW_SCALE
    end
    if scale < MIN_WINDOW_SCALE then
        scale = MIN_WINDOW_SCALE
    elseif scale > MAX_WINDOW_SCALE then
        scale = MAX_WINDOW_SCALE
    end
    return scale
end

function addon:SetWindowScale(scale)
    scale = tonumber(scale) or DEFAULT_WINDOW_SCALE
    if scale < MIN_WINDOW_SCALE then
        scale = MIN_WINDOW_SCALE
    elseif scale > MAX_WINDOW_SCALE then
        scale = MAX_WINDOW_SCALE
    end
    RaidInspectorDB.settings.window.scale = scale
    if addon.ui and addon.ui.frame then
        addon.ui.frame:SetScale(scale)
    end
    return scale
end

function addon:GetKeybinds()
    EnsureTable(RaidInspectorDB.settings, "keybinds", {})
    return RaidInspectorDB.settings.keybinds
end

function addon:SetKeybind(actionKey, keyString)
    local binds = addon:GetKeybinds()
    binds[actionKey] = tostring(keyString or "")
    addon:ApplyKeybinds()
end

function addon:ClearKeybind(actionKey)
    local binds = addon:GetKeybinds()
    binds[actionKey] = nil
    addon:ApplyKeybinds()
end

-- Applies the saved keybinds as override bindings owned by the main frame, so
-- they never touch the player's saved global bindings.
function addon:ApplyKeybinds()
    if not addon.ui or not addon.ui.frame then
        return
    end
    if type(ClearOverrideBindings) ~= "function" or type(SetOverrideBindingClick) ~= "function" then
        return
    end

    local owner = addon.ui.frame
    ClearOverrideBindings(owner)

    local binds = addon:GetKeybinds()
    local i
    for i = 1, #KEYBIND_ACTIONS do
        local def = KEYBIND_ACTIONS[i]
        local key = binds[def.key]
        if type(key) == "string" and key ~= "" then
            SetOverrideBindingClick(owner, true, key, def.button)
        end
    end
end

function addon:GetItemListFilterMode()
    local mode = RaidInspectorDB.state.ui.itemListFilterMode
    if ITEM_LIST_FILTER_LABELS[mode] then
        return mode
    end
    RaidInspectorDB.state.ui.itemListFilterMode = "all"
    return "all"
end

function addon:GetButtonMode()
    -- The Advanced/Easy selector was removed; the addon always uses the easy layout.
    RaidInspectorDB.state.ui.buttonMode = "easy"
    return "easy"
end

function addon:GetActiveTab()
    local tab = RaidInspectorDB.state.ui.activeTab
    if MAIN_TAB_LABELS[tab] then
        return tab
    end
    RaidInspectorDB.state.ui.activeTab = "inspector"
    return "inspector"
end

function addon:GetLFMState()
    EnsureTable(RaidInspectorDB.state.ui, "lfm", {})
    EnsureTable(RaidInspectorDB.state.ui.lfm, "message", "")
    EnsureTable(RaidInspectorDB.state.ui.lfm, "channels", {})
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "yell", false)
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "guild", false)
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "general", true)
    EnsureTable(RaidInspectorDB.state.ui.lfm.channels, "global", true)
    EnsureTable(RaidInspectorDB.state.ui.lfm, "postDelaySeconds", DEFAULT_LFM_POST_DELAY_SECONDS)
    EnsureTable(RaidInspectorDB.state.ui.lfm, "repeatCount", DEFAULT_LFM_REPEAT_COUNT)
    EnsureLFMNeedDefaults(RaidInspectorDB.state.ui.lfm)
    EnsureLFMRoleDefaults(RaidInspectorDB.state.ui.lfm)
    return RaidInspectorDB.state.ui.lfm
end

function addon:GetLFMChannels()
    local state = addon:GetLFMState()
    return state.channels
end

function addon:SetLFMChannel(channel, enabled)
    if channel ~= "yell" and channel ~= "guild" and channel ~= "general" and channel ~= "global" then
        return false
    end

    local channels = addon:GetLFMChannels()
    channels[channel] = enabled and true or false
    return true
end

function addon:GetLFMMessage()
    local state = addon:GetLFMState()
    return tostring(state.message or "")
end

function addon:SetLFMMessage(message)
    local state = addon:GetLFMState()
    state.message = tostring(message or "")
    return true
end

function addon:GetLFMPostDelaySeconds()
    local state = addon:GetLFMState()
    local value = tonumber(state.postDelaySeconds)
    if not value then
        state.postDelaySeconds = DEFAULT_LFM_POST_DELAY_SECONDS
        return DEFAULT_LFM_POST_DELAY_SECONDS
    end

    value = math.floor(value)
    if value < MIN_LFM_POST_DELAY_SECONDS then
        value = MIN_LFM_POST_DELAY_SECONDS
    elseif value > MAX_LFM_POST_DELAY_SECONDS then
        value = MAX_LFM_POST_DELAY_SECONDS
    end
    return value
end

function addon:SetLFMPostDelaySeconds(seconds)
    local value = tonumber(seconds)
    if not value then
        return false
    end

    value = math.floor(value)
    if value < MIN_LFM_POST_DELAY_SECONDS then
        value = MIN_LFM_POST_DELAY_SECONDS
    elseif value > MAX_LFM_POST_DELAY_SECONDS then
        value = MAX_LFM_POST_DELAY_SECONDS
    end

    local state = addon:GetLFMState()
    state.postDelaySeconds = value
    return true
end

function addon:GetLFMRepeatCount()
    local state = addon:GetLFMState()
    local value = tonumber(state.repeatCount)
    if not value then
        state.repeatCount = DEFAULT_LFM_REPEAT_COUNT
        return DEFAULT_LFM_REPEAT_COUNT
    end

    value = math.floor(value)
    if value < 1 then
        value = 1
    elseif value > MAX_LFM_REPEAT_COUNT then
        value = MAX_LFM_REPEAT_COUNT
    end
    return value
end

function addon:SetLFMRepeatCount(count)
    local value = tonumber(count)
    if not value then
        return false
    end

    value = math.floor(value)
    if value < 1 then
        value = 1
    elseif value > MAX_LFM_REPEAT_COUNT then
        value = MAX_LFM_REPEAT_COUNT
    end

    local state = addon:GetLFMState()
    state.repeatCount = value
    return true
end

function addon:GetLFMRoleState()
    local state = addon:GetLFMState()
    EnsureLFMRoleDefaults(state)
    return state.roles
end

function addon:SetLFMRoleCount(roleKey, value)
    local roles = addon:GetLFMRoleState()
    if not roles[roleKey] then
        return false
    end

    -- Keep only digits so the suffix stays clean (e.g. "1", "10").
    local digits = string.gsub(tostring(value or ""), "%D", "")
    roles[roleKey].count = digits
    return true
end

function addon:SetLFMRoleClasses(roleKey, value)
    local roles = addon:GetLFMRoleState()
    if not roles[roleKey] then
        return false
    end

    local text = Trim(tostring(value or ""))
    if #text > MAX_LFM_ROLE_CLASSES_LENGTH then
        text = string.sub(text, 1, MAX_LFM_ROLE_CLASSES_LENGTH)
    end
    roles[roleKey].classes = text
    return true
end

-- ===== LFM presets (save / load / delete / import / export) =====

local LFM_COMM_PREFIX = "RInspLFM"
local LFM_PRESET_FIELDS = 10

-- Length-prefixed encoding ("<len>:<data>...") so fields can contain any bytes
-- (achievement links include '|', ':' etc.) without needing escaping.
local function SerializeFields(fields)
    local parts = {}
    local i
    for i = 1, #fields do
        local s = tostring(fields[i] or "")
        parts[#parts + 1] = tostring(#s) .. ":" .. s
    end
    return table.concat(parts)
end

local function DeserializeFields(str, expectedCount)
    local fields = {}
    local pos = 1
    local n = #str
    while pos <= n and #fields < expectedCount do
        local colon = string.find(str, ":", pos, true)
        if not colon then
            break
        end
        local len = tonumber(string.sub(str, pos, colon - 1))
        if not len then
            break
        end
        local dataStart = colon + 1
        local dataEnd = dataStart + len - 1
        if dataEnd > n then
            break
        end
        fields[#fields + 1] = string.sub(str, dataStart, dataEnd)
        pos = dataEnd + 1
    end
    while #fields < expectedCount do
        fields[#fields + 1] = ""
    end
    return fields
end

-- Hex-encode the payload so the addon message contains only [0-9a-f]. This
-- avoids the client/server mangling of '|' colour/hyperlink escapes that live
-- inside achievement links, which otherwise corrupt or drop the message.
local function ToHex(s)
    return (string.gsub(tostring(s or ""), ".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

local function FromHex(h)
    return (string.gsub(tostring(h or ""), "%x%x", function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

local function PresetToFields(preset)
    local roles = preset.roles or {}
    local function rc(k, f)
        local t = roles[k] or {}
        return tostring(t[f] or "")
    end
    return {
        tostring(preset.name or ""),
        tostring(preset.message or ""),
        rc("tank", "count"), rc("tank", "classes"),
        rc("healer", "count"), rc("healer", "classes"),
        rc("melee", "count"), rc("melee", "classes"),
        rc("ranged", "count"), rc("ranged", "classes"),
    }
end

local function FieldsToPreset(fields)
    return {
        name = fields[1] or "",
        message = fields[2] or "",
        roles = {
            tank = { count = fields[3] or "", classes = fields[4] or "" },
            healer = { count = fields[5] or "", classes = fields[6] or "" },
            melee = { count = fields[7] or "", classes = fields[8] or "" },
            ranged = { count = fields[9] or "", classes = fields[10] or "" },
        },
    }
end

function addon:GetLFMPresets()
    EnsureTable(RaidInspectorDB, "lfmPresets", {})
    EnsureTable(RaidInspectorDB.lfmPresets, "items", {})
    return RaidInspectorDB.lfmPresets.items
end

function addon:FindLFMPreset(name)
    name = Trim(tostring(name or ""))
    if name == "" then
        return nil
    end
    local items = addon:GetLFMPresets()
    local i
    for i = 1, #items do
        if items[i].name == name then
            return items[i], i
        end
    end
    return nil
end

function addon:SaveLFMPresetObject(preset)
    if type(preset) ~= "table" then
        return false
    end
    local name = Trim(tostring(preset.name or ""))
    if name == "" then
        Print("lfm: preset needs a name")
        return false
    end
    preset.name = name
    local items = addon:GetLFMPresets()
    local existing, idx = addon:FindLFMPreset(name)
    if existing then
        items[idx] = preset
    else
        items[#items + 1] = preset
    end
    return true
end

function addon:SaveLFMPreset(name)
    name = Trim(tostring(name or ""))
    if name == "" then
        Print("lfm: enter a preset name")
        return false
    end

    addon:CommitLFMInputsFromUI()
    local roles = addon:GetLFMRoleState()
    local function copyRole(k)
        local t = roles[k] or {}
        return { count = tostring(t.count or ""), classes = tostring(t.classes or "") }
    end

    addon:SaveLFMPresetObject({
        name = name,
        message = addon:GetLFMMessage(),
        roles = {
            tank = copyRole("tank"),
            healer = copyRole("healer"),
            melee = copyRole("melee"),
            ranged = copyRole("ranged"),
        },
    })

    addon.ui = addon.ui or {}
    addon.ui.lfmSelectedPreset = name
    Print("lfm: saved preset '" .. name .. "'")
    addon:RefreshMainWindow()
    return true
end

function addon:DeleteLFMPreset(name)
    local existing, idx = addon:FindLFMPreset(name)
    if not existing then
        return false
    end
    table.remove(addon:GetLFMPresets(), idx)
    if addon.ui and addon.ui.lfmSelectedPreset == name then
        addon.ui.lfmSelectedPreset = nil
    end
    Print("lfm: deleted preset '" .. tostring(name) .. "'")
    addon:RefreshMainWindow()
    return true
end

function addon:LoadLFMPreset(name)
    local preset = addon:FindLFMPreset(name)
    if not preset then
        return false
    end

    addon:SetLFMMessage(preset.message or "")
    local roles = preset.roles or {}
    local i
    for i = 1, #LFM_ROLE_ROWS do
        local key = LFM_ROLE_ROWS[i].key
        local t = roles[key] or {}
        addon:SetLFMRoleCount(key, t.count or "")
        addon:SetLFMRoleClasses(key, t.classes or "")
    end

    addon.ui = addon.ui or {}
    addon.ui.lfmSelectedPreset = name
    if addon.ui.lfmMessageBox then
        addon.ui.lfmMessageBox:SetText(preset.message or "")
    end
    if addon.ui.lfmRoleRows then
        for i = 1, #addon.ui.lfmRoleRows do
            local entry = addon.ui.lfmRoleRows[i]
            local t = roles[entry.key] or {}
            if entry.countBox then
                entry.countBox:SetText(tostring(t.count or ""))
            end
            if entry.classBox then
                entry.classBox:SetText(tostring(t.classes or ""))
            end
        end
    end

    addon:RefreshMainWindow()
    return true
end

-- Sends the named preset to another player over addon whispers (chunked to fit
-- the 255-byte addon-message limit; reassembled on the receiving side).
function addon:ExportLFMPresetTo(presetName, recipient)
    recipient = Trim(tostring(recipient or ""))
    if recipient == "" then
        Print("lfm: enter a character name to send the preset to")
        return
    end
    local preset = addon:FindLFMPreset(presetName)
    if not preset then
        Print("lfm: select a preset to export first")
        return
    end
    if type(SendAddonMessage) ~= "function" then
        Print("lfm: addon messaging is unavailable")
        return
    end

    local data = ToHex(SerializeFields(PresetToFields(preset)))
    addon.lfmExportSeq = (tonumber(addon.lfmExportSeq) or 0) + 1
    local seq = addon.lfmExportSeq
    local recipientToken = string.gsub(recipient, "%s+", "")
    local CHUNK = 200
    local total = math.max(1, math.ceil(#data / CHUNK))

    -- Build the chunk bodies once, then send over every available channel so the
    -- preset reaches the target even when the server blocks WHISPER addon msgs.
    -- Format: "<seq> <idx> <cnt> <recipient> <hexChunk>"; only the named
    -- recipient acts on it, and duplicates from multiple channels are de-duped.
    local bodies = {}
    local idx
    for idx = 1, total do
        local chunk = string.sub(data, ((idx - 1) * CHUNK) + 1, idx * CHUNK)
        bodies[idx] = tostring(seq) .. " " .. tostring(idx) .. " " .. tostring(total)
            .. " " .. recipientToken .. " " .. chunk
    end

    local function sendAll(channel, target)
        for idx = 1, #bodies do
            if target then
                SendAddonMessage(LFM_COMM_PREFIX, bodies[idx], channel, target)
            else
                SendAddonMessage(LFM_COMM_PREFIX, bodies[idx], channel)
            end
        end
    end

    sendAll("WHISPER", recipient)
    if IsInGuild and IsInGuild() then
        sendAll("GUILD")
    end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        sendAll("RAID")
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        sendAll("PARTY")
    end

    Print("lfm: sent preset '" .. tostring(preset.name) .. "' to " .. recipient .. " (they click Import to accept)")
end

local MAX_PENDING_IMPORTS = 20
local MAX_VISIBLE_IMPORT_ROWS = 12

-- Queues a received preset. Re-sends of the same preset from the same sender
-- replace the earlier copy instead of stacking up.
function addon:QueuePendingImport(sender, preset)
    addon.lfmPendingImports = addon.lfmPendingImports or {}
    local list = addon.lfmPendingImports
    local i
    for i = 1, #list do
        local p = list[i]
        if p.from == sender and p.preset and preset and p.preset.name == preset.name then
            list[i] = { from = sender, preset = preset }
            return #list
        end
    end
    if #list >= MAX_PENDING_IMPORTS then
        table.remove(list, 1)
    end
    list[#list + 1] = { from = sender, preset = preset }
    return #list
end

function addon:OnCommReceived(prefix, message, channel, sender)
    if prefix ~= LFM_COMM_PREFIX then
        return
    end
    local seqStr, idxStr, cntStr, recipient, chunk = string.match(tostring(message or ""), "^(%d+) (%d+) (%d+) (%S+) (.*)$")
    if not seqStr then
        return
    end
    local seq, idx, cnt = tonumber(seqStr), tonumber(idxStr), tonumber(cntStr)
    if not seq or not idx or not cnt or cnt < 1 then
        return
    end

    -- Only the addressed character processes it (needed because we also broadcast
    -- over guild/raid so the message still arrives when whispers are blocked).
    local myName = UnitName("player") or ""
    if string.lower(recipient) ~= string.lower(myName) then
        return
    end

    sender = tostring(sender or "?")
    -- Strip any realm suffix a channel might append (e.g. "Name-Realm").
    sender = string.match(sender, "^([^%-]+)") or sender

    local now = (GetTime and GetTime()) or 0
    addon.lfmCommBuffers = addon.lfmCommBuffers or {}

    -- Drop stale / long-completed transfers so buffers do not accumulate.
    local key, b
    for key, b in pairs(addon.lfmCommBuffers) do
        if b.done and (now - (b.doneAt or 0)) > 120 then
            addon.lfmCommBuffers[key] = nil
        elseif not b.done and (now - (b.startedAt or 0)) > 300 then
            addon.lfmCommBuffers[key] = nil
        end
    end

    local bufKey = sender .. "#" .. tostring(seq)
    local buf = addon.lfmCommBuffers[bufKey]
    if buf and buf.done then
        return -- already assembled (a duplicate arriving on another channel)
    end
    if not buf then
        buf = { count = cnt, parts = {}, received = 0, startedAt = now }
        addon.lfmCommBuffers[bufKey] = buf
    end
    if not buf.parts[idx] then
        buf.parts[idx] = chunk
        buf.received = buf.received + 1
    end
    if buf.received >= buf.count then
        local data = FromHex(table.concat(buf.parts))
        buf.parts = nil
        buf.done = true
        buf.doneAt = now
        local preset = FieldsToPreset(DeserializeFields(data, LFM_PRESET_FIELDS))
        local pendingCount = addon:QueuePendingImport(sender, preset)
        Print("lfm: received preset '" .. tostring(preset.name) .. "' from " .. sender
            .. " (" .. tostring(pendingCount) .. " pending) - open the LFM tab and click Import")
        if addon.ui and addon.ui.importDialog and addon.ui.importDialog:IsShown() then
            addon:RefreshImportDialog()
        end
    end
end

function addon:HasPendingImport()
    return type(addon.lfmPendingImports) == "table" and #addon.lfmPendingImports > 0
end

local function RemovePendingEntry(entry)
    local list = addon.lfmPendingImports or {}
    local i
    for i = 1, #list do
        if list[i] == entry then
            table.remove(list, i)
            return true
        end
    end
    return false
end

function addon:AcceptImportEntry(entry)
    if type(entry) ~= "table" or not RemovePendingEntry(entry) then
        return
    end
    if addon:SaveLFMPresetObject(entry.preset) then
        addon.ui = addon.ui or {}
        addon.ui.lfmSelectedPreset = entry.preset and entry.preset.name or nil
        Print("lfm: imported preset '" .. tostring(entry.preset and entry.preset.name) .. "' from " .. tostring(entry.from))
        addon:RefreshMainWindow()
    end
    addon:RefreshImportDialog()
end

function addon:DeclineImportEntry(entry)
    if type(entry) ~= "table" or not RemovePendingEntry(entry) then
        return
    end
    Print("lfm: declined preset '" .. tostring(entry.preset and entry.preset.name) .. "' from " .. tostring(entry.from))
    addon:RefreshImportDialog()
end

function addon:AcceptAllImports()
    local list = addon.lfmPendingImports or {}
    if #list == 0 then
        return
    end
    local count = 0
    while #list > 0 do
        local entry = table.remove(list, 1)
        if addon:SaveLFMPresetObject(entry.preset) then
            addon.ui = addon.ui or {}
            addon.ui.lfmSelectedPreset = entry.preset and entry.preset.name or nil
            count = count + 1
        end
    end
    Print("lfm: imported " .. tostring(count) .. " preset(s)")
    addon:RefreshMainWindow()
    addon:RefreshImportDialog()
end

function addon:DeclineAllImports()
    local list = addon.lfmPendingImports or {}
    local n = #list
    addon.lfmPendingImports = {}
    if n > 0 then
        Print("lfm: declined " .. tostring(n) .. " pending preset(s)")
    end
    addon:RefreshImportDialog()
end

function addon:PromptImportPreset()
    if not addon:HasPendingImport() then
        Print("lfm: no pending preset invitations")
        return
    end
    addon:ShowImportDialog()
end

StaticPopupDialogs["RAIDINSPECTOR_SAVE_PRESET"] = {
    text = "Save the current LFM message + Need table as a preset.\nName:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local editBox = _G[self:GetName() .. "EditBox"]
        if editBox then
            editBox:SetText("")
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self)
        local editBox = _G[self:GetName() .. "EditBox"]
        addon:SaveLFMPreset(editBox and editBox:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        addon:SaveLFMPreset(self:GetText() or "")
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["RAIDINSPECTOR_EXPORT_PRESET"] = {
    text = "Send preset '%s' to which character?",
    button1 = "Send",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self)
        local editBox = _G[self:GetName() .. "EditBox"]
        if editBox then
            editBox:SetText("")
            editBox:SetFocus()
        end
    end,
    OnAccept = function(self)
        local editBox = _G[self:GetName() .. "EditBox"]
        addon:ExportLFMPresetTo(self.data, editBox and editBox:GetText() or "")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}


function addon:GetLFMNeedState()
    local state = addon:GetLFMState()
    EnsureLFMNeedDefaults(state)
    return state.needs
end

function addon:SetLFMNeedGroup(groupKey, enabled)
    local i
    for i = 1, #LFM_NEED_GROUPS do
        if LFM_NEED_GROUPS[i].key == groupKey then
            local needs = addon:GetLFMNeedState()
            needs.groups[groupKey] = enabled and true or false
            return true
        end
    end
    return false
end

function addon:SetLFMNeedItem(itemKey, enabled)
    local i
    for i = 1, #LFM_NEED_GROUPS do
        local group = LFM_NEED_GROUPS[i]
        local j
        for j = 1, #group.items do
            local item = group.items[j]
            if item.key == itemKey then
                local needs = addon:GetLFMNeedState()
                needs.items[itemKey] = enabled and true or false
                return true
            end
        end
    end
    return false
end

function addon:BuildLFMNeedSuffix()
    local roles = addon:GetLFMRoleState()
    local out = {}

    local i
    for i = 1, #LFM_ROLE_ROWS do
        local row = LFM_ROLE_ROWS[i]
        local data = roles[row.key] or {}
        local count = Trim(tostring(data.count or ""))
        local classes = Trim(tostring(data.classes or ""))

        if count ~= "" or classes ~= "" then
            local segment
            if count ~= "" then
                segment = count .. " " .. row.label
            else
                segment = row.label
            end
            if classes ~= "" then
                segment = segment .. " (" .. classes .. ")"
            end
            out[#out + 1] = segment
        end
    end

    return table.concat(out, ", ")
end

function addon:GetLFMChannelAvailability()
    local generalId, generalName = FindJoinedChannelByAlias(LFM_GENERAL_ALIASES)
    local globalId, globalName = FindJoinedChannelByAlias(LFM_GLOBAL_ALIASES)

    return {
        yell = true,
        guild = IsInGuild() and true or false,
        general = generalId and true or false,
        global = globalId and true or false,
        generalId = generalId,
        globalId = globalId,
        generalName = generalName,
        globalName = globalName,
    }
end

function addon:GetExportChannels()
    EnsureTable(RaidInspectorDB.state.ui, "exportChannels", {})
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "raid", true)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "say", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "whisper", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "guild", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "rw", false)
    return RaidInspectorDB.state.ui.exportChannels
end

function addon:SetExportChannel(channel, enabled)
    if channel ~= "raid" and channel ~= "say" and channel ~= "whisper"
        and channel ~= "guild" and channel ~= "rw" then
        return false
    end

    local channels = addon:GetExportChannels()
    channels[channel] = enabled and true or false
    return true
end

-- ---------------------------------------------------------------------------
-- MS (main spec) tracking
--
-- While registering is on, every raid/party chat line is checked for an
-- "MS <spec>" declaration. Matches are stored per player in their own table so
-- they survive scans, reloads and the Clear button - only an explicit MS clear
-- wipes them.
-- ---------------------------------------------------------------------------

function addon:GetMSTracking()
    EnsureTable(RaidInspectorDB, "msTracking", {})
    EnsureTable(RaidInspectorDB.msTracking, "enabled", false)
    EnsureTable(RaidInspectorDB.msTracking, "entries", {})
    EnsureTable(RaidInspectorDB.msTracking, "nextSeq", 1)
    EnsureTable(RaidInspectorDB.msTracking, "startedAt", 0)
    return RaidInspectorDB.msTracking
end

function addon:IsMSTrackingEnabled()
    return addon:GetMSTracking().enabled == true
end

function addon:GetMainSpecRecord(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end
    local record = addon:GetMSTracking().entries[key]
    if type(record) ~= "table" then
        return nil
    end
    return record
end

-- Chat authors arrive as "Name" on a single-realm server and occasionally as
-- "Name-Realm"; normalize both to the same key the inspect list uses.
local function SplitChatAuthor(author)
    local text = Trim(author or "")
    if text == "" then
        return nil, nil
    end

    local name, realm = string.match(text, "^(.+)%-(.+)$")
    if name and realm then
        return Trim(name), Trim(realm)
    end

    local currentRealm = (type(GetRealmName) == "function" and GetRealmName()) or "Unknown"
    return text, currentRealm
end

-- Accepts "MS resto", "ms: heal", "ms - ret", "mainspec tank", "main spec dps".
-- Returns the cleaned spec text, or nil when the line is not an MS declaration
-- (or is one of the leader's open/close control announcements).
-- Cuts to at most MS_MAX_SPEC_LENGTH bytes without slicing a multi-byte UTF-8
-- sequence in half - ruRU/deDE realms would otherwise store an invalid byte
-- that renders as a glyph artefact and gets sent verbatim to chat.
local function TruncateSpecText(spec)
    if string.len(spec) <= MS_MAX_SPEC_LENGTH then
        return spec
    end

    local cut = MS_MAX_SPEC_LENGTH
    while cut > 1 do
        local nextByte = string.byte(spec, cut + 1)
        -- 0x80-0xBF is a UTF-8 continuation byte: back off to its lead byte.
        if not nextByte or nextByte < 128 or nextByte >= 192 then
            break
        end
        cut = cut - 1
    end

    return Trim(string.sub(spec, 1, cut))
end

-- The single gate every recorded spec passes through, whether it came from
-- chat, /ri ms set, or the right-click editor. Returns nil to reject.
local function SanitizeSpecText(text)
    local spec = Trim(text or "")
    if spec == "" then
        return nil
    end

    -- Colour/link escapes would corrupt the overview row (which wraps the spec
    -- in its own |cff..|r) and the outgoing chat line.
    if string.find(spec, "|", 1, true) then
        return nil
    end

    spec = Trim(string.gsub(spec, "%s+", " "))
    -- Drop trailing chat punctuation ("ms resto!!" / "ms heal.").
    spec = Trim(string.gsub(spec, "[%.%!%?,;:]+$", ""))
    if spec == "" then
        return nil
    end

    -- A spec starts with a letter, which rejects loot-rule chatter that happens
    -- to follow "MS" ("MS > OS", "MS = main spec"). Only ASCII is tested: %a is
    -- locale-dependent and would throw away every Cyrillic spec on a ruRU realm,
    -- so any high byte (a UTF-8 lead) is accepted as a letter.
    local firstByte = string.byte(spec, 1)
    if firstByte and firstByte < 128 and not string.find(spec, "^%a") then
        return nil
    end

    -- Check the FIRST WORD, not the whole string: the leader's announcements
    -- ("MS CHANGE CLOSE") and this addon's own broadcast ("MS changes (3):
    -- Bob=resto, ...") both carry extra text that a whole-string lookup misses.
    -- Without this the share output is re-read by our own chat hook and stored
    -- as the sharer's main spec, re-triggering on every share.
    local firstWord = string.lower(string.match(spec, "^(%a+)") or "")
    if MS_CONTROL_PHRASES[firstWord] or MS_CONTROL_PHRASES[string.lower(spec)] then
        return nil
    end

    return TruncateSpecText(spec)
end

local function ParseMainSpecMessage(text)
    local body = Trim(text or "")
    if body == "" then
        return nil
    end

    -- Require a real separator after "ms" so words like "msg" never match.
    local spec = string.match(body, "^[Mm][Ss]%s*[:%-]+%s*(.+)$")
        or string.match(body, "^[Mm][Ss]%s+(.+)$")
        or string.match(body, "^[Mm]ain%s*[Ss]pec%s*[:%-]*%s*(.+)$")
    if not spec then
        return nil
    end

    return SanitizeSpecText(spec)
end

-- Stores one MS declaration. Returns the record plus whether it actually
-- changed anything, so repeated identical lines stay quiet.
-- realmOverride keeps a manual edit on the exact key the row already uses,
-- instead of re-deriving it from the player's current realm.
function addon:RecordMainSpecChange(playerName, specText, sourceLabel, realmOverride)
    local name, realm = SplitChatAuthor(playerName)
    if not name then
        return nil, false
    end

    if realmOverride and realmOverride ~= "" then
        realm = realmOverride
    end

    -- Every path lands here, so the manual editor and /ri ms set get the same
    -- escape-stripping and length cap as a parsed chat line.
    local spec = SanitizeSpecText(specText)
    if not spec then
        return nil, false
    end

    local tracking = addon:GetMSTracking()
    local key = MakePlayerKey(name, realm)
    local existing = tracking.entries[key]
    local previousSpec = type(existing) == "table" and existing.spec or nil

    if previousSpec and string.lower(previousSpec) == string.lower(spec) then
        -- Same spec re-announced: refresh the timestamp, do not count a change.
        existing.at = GetNow()
        existing.source = sourceLabel or existing.source
        return existing, false
    end

    local record = {
        key = key,
        name = name,
        realm = realm,
        spec = spec,
        previousSpec = previousSpec,
        at = GetNow(),
        seq = tonumber(tracking.nextSeq) or 1,
        source = sourceLabel or "manual",
        changeCount = (type(existing) == "table" and (tonumber(existing.changeCount) or 0) or 0) + 1,
    }

    tracking.nextSeq = record.seq + 1
    tracking.entries[key] = record
    return record, true
end

function addon:RemoveMainSpecRecord(key)
    local tracking = addon:GetMSTracking()
    if type(key) ~= "string" or key == "" or tracking.entries[key] == nil then
        return false
    end
    tracking.entries[key] = nil
    return true
end

-- Recorded MS entries, newest declaration first.
function addon:GetMainSpecRecords()
    local tracking = addon:GetMSTracking()
    local records = {}
    local key, record
    for key, record in pairs(tracking.entries) do
        if type(record) == "table" then
            table.insert(records, record)
        end
    end

    table.sort(records, function(a, b)
        local aSeq = tonumber(a and a.seq) or 0
        local bSeq = tonumber(b and b.seq) or 0
        if aSeq ~= bSeq then
            return aSeq > bSeq
        end
        return string.lower(tostring(a and a.name or "")) < string.lower(tostring(b and b.name or ""))
    end)

    return records
end

function addon:GetMainSpecCount()
    local count = 0
    local _, record
    for _, record in pairs(addon:GetMSTracking().entries) do
        if type(record) == "table" then
            count = count + 1
        end
    end
    return count
end

function addon:SetMSTrackingEnabled(enabled)
    local tracking = addon:GetMSTracking()
    tracking.enabled = enabled and true or false

    if tracking.enabled then
        tracking.startedAt = GetNow()
        Print("MS registering: ON - raid/party lines like \"MS resto\" are now recorded")
    else
        Print("MS registering: OFF (" .. tostring(addon:GetMainSpecCount()) .. " recorded)")
    end

    addon:RefreshMSButton()
    addon:RefreshMainWindow()
    return tracking.enabled
end

function addon:ToggleMSTracking()
    return addon:SetMSTrackingEnabled(not addon:IsMSTrackingEnabled())
end

function addon:ClearMainSpecRecords()
    local removed = addon:GetMainSpecCount()
    local tracking = addon:GetMSTracking()
    tracking.entries = {}
    tracking.nextSeq = 1
    Print("MS list cleared (" .. tostring(removed) .. " removed)")
    addon:RefreshMainWindow()
    return removed
end

function addon:RequestClearMainSpecRecords()
    if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table" then
        addon:ClearMainSpecRecords()
        return
    end

    StaticPopup_Hide("RAIDINSPECTOR_CONFIRM_CLEAR_MS")
    StaticPopup_Show("RAIDINSPECTOR_CONFIRM_CLEAR_MS")
end

-- Raid chat hook. Only listens while registering is on.
function addon:OnRaidChatMessage(event, message, author)
    if not addon:IsMSTrackingEnabled() then
        return
    end

    local spec = ParseMainSpecMessage(message)
    if not spec then
        return
    end

    local record, changed = addon:RecordMainSpecChange(author, spec, event)
    if not record or not changed then
        return
    end

    if record.previousSpec then
        Print("MS: " .. record.name .. " " .. tostring(record.previousSpec) .. " -> " .. record.spec)
    else
        Print("MS: " .. record.name .. " = " .. record.spec)
    end

    addon:RefreshMainWindow()
end

-- Packs every recorded MS into as few chat lines as possible (chat caps a
-- message at 255 characters, so long raids need several lines).
function addon:BuildMainSpecReportLines()
    local records = addon:GetMainSpecRecords()
    if #records == 0 then
        return {}
    end

    local lines = {}
    local header = "MS changes (" .. tostring(#records) .. "): "
    local current = header
    local isFirstOnLine = true

    local i
    for i = 1, #records do
        local record = records[i]
        local piece = tostring(record.name) .. "=" .. tostring(record.spec)
        local candidate = current .. (isFirstOnLine and "" or ", ") .. piece

        if string.len(candidate) > MS_REPORT_LINE_LENGTH and not isFirstOnLine then
            table.insert(lines, current)
            current = "MS changes (cont.): " .. piece
            -- A single oversized entry still has to fit inside one chat message.
            if string.len(current) > MS_REPORT_LINE_LENGTH then
                current = string.sub(current, 1, MS_REPORT_LINE_LENGTH)
            end
        else
            current = candidate
        end
        isFirstOnLine = false
    end

    if current ~= header then
        table.insert(lines, current)
    end

    return lines
end

function addon:ShareMainSpecChanges()
    local lines = addon:BuildMainSpecReportLines()
    if #lines == 0 then
        Print("MS: nothing recorded yet")
        return 0
    end

    -- Check the channel selection once up front; otherwise SendSummaryMessage
    -- repeats its "no channels selected" / "whisper target missing" warning
    -- for every line of a multi-line report.
    local channels = addon:GetExportChannels()
    if not (channels.raid or channels.say or channels.guild or channels.rw) then
        if channels.whisper then
            Print("MS: WHISPER is not a target for the MS list - tick Raid/Say/Guild/RW")
        else
            Print("MS: no channels selected (Raid/Say/Guild/RW)")
        end
        return 0
    end

    -- Whisper is per-player and meaningless for a roster-wide list; skip it so
    -- it cannot warn once per line.
    local restoreWhisper = channels.whisper
    channels.whisper = false

    local i
    for i = 1, #lines do
        addon:SendSummaryMessage(lines[i])
    end

    channels.whisper = restoreWhisper
    return #lines
end

function addon:PrintMainSpecRecords()
    local records = addon:GetMainSpecRecords()
    Print("MS registering: " .. (addon:IsMSTrackingEnabled() and "ON" or "OFF")
        .. ", recorded=" .. tostring(#records))

    local i
    for i = 1, #records do
        local record = records[i]
        local changeText = ""
        if record.previousSpec then
            changeText = " (was " .. tostring(record.previousSpec) .. ")"
        end
        Print("  " .. tostring(record.name) .. " = " .. tostring(record.spec) .. changeText)
    end
end

function addon:RefreshTabVisibility()
    if not addon.ui or not addon.ui.frame then
        return
    end

    local activeTab = addon:GetActiveTab()
    local inspectorVisible = activeTab == "inspector"

    local function SetWidgetVisible(widget, visible)
        if not widget then
            return
        end
        if visible then
            widget:Show()
        else
            widget:Hide()
        end
    end

    local inspectorWidgets = {
        addon.ui.shareChannelsRow,
        addon.ui.shareChannelsLabel,
        addon.ui.raidShareCheck,
        addon.ui.sayShareCheck,
        addon.ui.whisperShareCheck,
        addon.ui.guildShareCheck,
        addon.ui.rwShareCheck,
        addon.ui.savedReportsRow,
        addon.ui.savedReportsLabel,
        addon.ui.savedReportDropDown,
        addon.ui.sortRow,
        addon.ui.sortLabel,
        addon.ui.sortDropDown,
        addon.ui.actionPanel,
        addon.ui.targetButton,
        addon.ui.raidButton,
        addon.ui.autoScanButton,
        addon.ui.syncButton,
        addon.ui.reportButton,
        addon.ui.clearButton,
        addon.ui.msButton,
        addon.ui.msShareButton,
        addon.ui.msClearButton,
        addon.ui.rowsViewport,
        addon.ui.overviewScroll,
        addon.ui.compositionHeader,
        addon.ui.compositionSummary,
        addon.ui.detailHeader,
        addon.ui.detailScore,
        addon.ui.detailMeta,
        addon.ui.detailAudit,
        addon.ui.itemFilterLabel,
        addon.ui.itemFilterDropDown,
        addon.ui.detailHeaderRow,
        addon.ui.detailContainer,
        addon.ui.detailScroll,
    }

    local i
    for i = 1, #inspectorWidgets do
        SetWidgetVisible(inspectorWidgets[i], inspectorVisible)
    end

    SetWidgetVisible(addon.ui.lfmPanel, not inspectorVisible)

    if addon.ui.inspectorTabButton then
        if inspectorVisible then
            addon.ui.inspectorTabButton:SetText("|cff66ff66Inspector|r")
        else
            addon.ui.inspectorTabButton:SetText("|cffbbbbbbInspector|r")
        end
    end

    if addon.ui.lfmTabButton then
        if inspectorVisible then
            addon.ui.lfmTabButton:SetText("|cffbbbbbbLFM|r")
        else
            addon.ui.lfmTabButton:SetText("|cff66ff66LFM|r")
        end
    end

    if addon.ui.subtitle then
        if inspectorVisible then
            addon.ui.subtitle:SetText("Raid overview + selected player details")
        else
            addon.ui.subtitle:SetText("LFM composer + multi-channel posting")
        end
    end
end

function addon:SetActiveTab(tab)
    if not MAIN_TAB_LABELS[tab] then
        return false
    end

    RaidInspectorDB.state.ui.activeTab = tab
    addon:RefreshTabVisibility()
    return true
end

function addon:GetReportSnapshots()
    EnsureTable(RaidInspectorDB, "reportSnapshots", {})
    EnsureTable(RaidInspectorDB.reportSnapshots, "nextId", 1)
    EnsureTable(RaidInspectorDB.reportSnapshots, "items", {})
    return RaidInspectorDB.reportSnapshots
end

function addon:GetReportFileQueue()
    EnsureTable(RaidInspectorDB, "reportFileQueue", {})
    EnsureTable(RaidInspectorDB.reportFileQueue, "nextId", 1)
    EnsureTable(RaidInspectorDB.reportFileQueue, "items", {})
    return RaidInspectorDB.reportFileQueue
end

function addon:GetSavedReportFiles()
    EnsureTable(RaidInspectorDB, "savedReportFiles", {})
    EnsureTable(RaidInspectorDB.savedReportFiles, "generatedAt", 0)
    EnsureTable(RaidInspectorDB.savedReportFiles, "items", {})
    return RaidInspectorDB.savedReportFiles
end

function addon:MigrateReportFileQueueToSavedReports()
    local queue = RaidInspectorDB.reportFileQueue
    if type(queue) ~= "table" or type(queue.items) ~= "table" or #queue.items == 0 then
        return 0
    end

    local savedReports = addon:GetSavedReportFiles()
    local migrated = 0
    local i
    for i = 1, #queue.items do
        local item = queue.items[i]
        if type(item) == "table" and type(item.report) == "table" then
            local createdAt = tonumber(item.createdAt) or tonumber(item.report.createdAt) or GetNow()
            local fileName = tostring(item.fileName or item.report.fileName or BuildReportFileName(createdAt))
            if not addon:FindSavedReportFileItem(fileName) then
                savedReports.items[#savedReports.items + 1] = {
                    createdAt = createdAt,
                    fileName = fileName,
                    label = tostring(item.label or item.report.reportLabel or "Raid Inspector Report"),
                    report = CopyTable(item.report),
                }
                migrated = migrated + 1
            end
        end
    end

    if migrated > 0 then
        savedReports.generatedAt = GetNow()
        SortSavedReportItems(savedReports.items)
        while #savedReports.items > REPORT_FILE_QUEUE_LIMIT do
            table.remove(savedReports.items)
        end
    end

    RaidInspectorDB.reportFileQueue = {
        nextId = tonumber(queue.nextId) or 1,
        items = {},
    }

    return migrated
end

function addon:GetSelectedSavedReportFile()
    return tostring(RaidInspectorDB.state.ui.selectedSavedReportFile or "")
end

function addon:FindSavedReportFileItem(fileName)
    local target = string.lower(Trim(fileName or ""))
    if target == "" then
        return nil
    end

    local savedReports = addon:GetSavedReportFiles()
    local i
    for i = 1, #savedReports.items do
        local item = savedReports.items[i]
        if string.lower(tostring(item.fileName or "")) == target then
            return item
        end
    end

    return nil
end

function addon:GetActiveSavedReport()
    return addon:FindSavedReportFileItem(addon:GetSelectedSavedReportFile())
end

function addon:SetSelectedSavedReportFile(fileName)
    local normalized = Trim(fileName or "")
    if normalized == "" then
        RaidInspectorDB.state.ui.selectedSavedReportFile = ""
        addon:SetSelectedKey("")
        addon:RefreshMainWindow()
        return true
    end

    local item = addon:FindSavedReportFileItem(normalized)
    if not item then
        return false
    end

    RaidInspectorDB.state.ui.selectedSavedReportFile = tostring(item.fileName or normalized)
    addon:SetSelectedKey("")
    addon:RefreshMainWindow()
    return true
end

function addon:GetSavedReportPlayerCount(item)
    if type(item) ~= "table" or type(item.report) ~= "table" then
        return 0
    end

    local report = item.report
    if type(report.order) == "table" then
        return #report.order
    end

    local count = 0
    local _
    for _ in pairs(report.players or {}) do
        count = count + 1
    end
    return count
end

function addon:BuildSavedReportMenuLabel(item)
    local createdAt = tonumber(item and item.createdAt) or tonumber(item and item.report and item.report.createdAt) or 0
    local label = Trim(item and (item.label or item.reportLabel or item.fileName) or "")
    if label == "" then
        label = tostring(item and item.fileName or "saved report")
    end
    return label .. " [" .. tostring(addon:GetSavedReportPlayerCount(item)) .. "]"
        .. " @ " .. FormatTimestampForDisplay(createdAt)
end

function addon:GetRaidScanHistory()
    EnsureTable(RaidInspectorDB, "raidScanHistory", {})
    EnsureTable(RaidInspectorDB.raidScanHistory, "nextId", 1)
    EnsureTable(RaidInspectorDB.raidScanHistory, "scans", {})
    return RaidInspectorDB.raidScanHistory
end

function addon:PruneRaidScanHistory()
    local history = addon:GetRaidScanHistory()
    local cutoff = GetNow() - RAID_HISTORY_RETENTION_SECONDS
    local kept = {}
    local activeHistoryId = tonumber(RaidInspectorDB.state.lastSnapshot and RaidInspectorDB.state.lastSnapshot.historyId) or 0
    local activeKept = false
    local i

    for i = 1, #history.scans do
        local entry = history.scans[i]
        local snapshotAt = tonumber(entry and entry.snapshotAt) or tonumber(entry and entry.updatedAt) or 0
        if snapshotAt >= cutoff then
            kept[#kept + 1] = entry
            if activeHistoryId > 0 and tonumber(entry.id) == activeHistoryId then
                activeKept = true
            end
        end
    end

    history.scans = kept
    if activeHistoryId > 0 and not activeKept and RaidInspectorDB.state.lastSnapshot then
        RaidInspectorDB.state.lastSnapshot.historyId = 0
    end
end

function addon:BuildStoredSummaryPayload(key, req, result, state, statusReason)
    local nameFromKey, realmFromKey = ParseKey(key or "")
    local payload = {
        key = key,
        name = (req and req.name) or (result and result.name) or nameFromKey or "Unknown",
        realm = (req and req.realm) or (result and result.realm) or realmFromKey or "Unknown",
        state = state or (req and req.status) or "queued",
        statusReason = statusReason or (req and req.statusReason) or nil,
        requestId = req and tonumber(req.id) or nil,
        requestedAt = req and tonumber(req.requestedAt) or nil,
        updatedAt = req and tonumber(req.updatedAt) or 0,
    }

    if type(result) == "table" then
        payload.class = result.class
        payload.spec = result.spec
        payload.guild = result.guild
        payload.level = result.level
        payload.source = result.source
        payload.error = result.error
        payload.items = CopyTable(result.items or {})
        payload.enchants = CopyTable(result.enchants or {})
        payload.gems = CopyTable(result.gems or {})
        payload.gearScore = result.gearScore
        payload.gearScoreSource = result.gearScoreSource
        payload.estimatedGearScore = result.estimatedGearScore
        payload.issuesCount = tonumber(result.issuesCount) or 0
        payload.issueSummary = CopyTable(result.issueSummary or {})
        payload.achievementPoints = result.achievementPoints
        payload.achievementPointsSource = result.achievementPointsSource
        payload.raidAchievements = CopyTable(result.raidAchievements or {})
        payload.specificAchievements = CopyTable(result.specificAchievements or {})
        payload.raw = CopyTable(result.raw)
        payload.updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or payload.updatedAt or 0
    end

    -- MS lives outside `results`, so it has to be pulled from the MS list by
    -- key. Saving it into the payload is what lets a saved report keep the
    -- specs that were recorded at the time it was saved.
    local msRecord = addon:GetMainSpecRecord(payload.key)
    if msRecord then
        payload.mainSpec = msRecord.spec
        payload.mainSpecAt = tonumber(msRecord.at) or 0
        payload.mainSpecPrevious = msRecord.previousSpec
    end

    return payload
end

function addon:BuildReportEntryFromPayload(payload, index)
    if type(payload) ~= "table" then
        return nil
    end

    local key = string.lower(tostring(payload.key or MakePlayerKey(payload.name or "Unknown", payload.realm or "Unknown")))
    local state = tostring(payload.state or ((payload.error and "error") or "ready"))
    if state ~= "error" and not payload.error then
        state = "ready"
    end

    local updatedAt = tonumber(payload.updatedAt) or 0
    local req = {
        id = tonumber(payload.requestId) or tonumber(index) or 0,
        name = payload.name or "Unknown",
        realm = payload.realm or "Unknown",
        key = key,
        status = state,
        statusReason = payload.statusReason,
        requestedAt = tonumber(payload.requestedAt) or updatedAt,
        updatedAt = updatedAt,
    }

    local result = {
        name = payload.name or "Unknown",
        realm = payload.realm or "Unknown",
        class = payload.class,
        spec = payload.spec,
        guild = payload.guild,
        level = payload.level,
        source = payload.source or "saved-report",
        error = payload.error,
        items = CopyTable(payload.items or {}),
        enchants = CopyTable(payload.enchants or {}),
        gems = CopyTable(payload.gems or {}),
        gearScore = payload.gearScore,
        gearScoreSource = payload.gearScoreSource,
        estimatedGearScore = payload.estimatedGearScore,
        issuesCount = tonumber(payload.issuesCount) or 0,
        issueSummary = CopyTable(payload.issueSummary or {}),
        achievementPoints = payload.achievementPoints,
        achievementPointsSource = payload.achievementPointsSource,
        raidAchievements = CopyTable(payload.raidAchievements or {}),
        specificAchievements = CopyTable(payload.specificAchievements or {}),
        raw = CopyTable(payload.raw),
        -- Restored from the report itself, not the live MS list, so an old
        -- report shows the specs it was saved with.
        mainSpec = payload.mainSpec,
        mainSpecAt = tonumber(payload.mainSpecAt) or nil,
        mainSpecPrevious = payload.mainSpecPrevious,
        fetchedAt = updatedAt,
        updatedAt = updatedAt,
    }

    return {
        key = key,
        req = req,
        result = result,
        state = state,
        statusReason = payload.statusReason,
        updatedAt = updatedAt,
        ageMinutes = updatedAt > 0 and math.floor(math.max(0, GetNow() - updatedAt) / 60) or -1,
        isFresh = updatedAt > 0 and (GetNow() - updatedAt) <= FRESHNESS_TTL_SECONDS,
    }
end

function addon:GetActiveSavedReportEntries()
    local item = addon:GetActiveSavedReport()
    if type(item) ~= "table" or type(item.report) ~= "table" then
        return nil
    end

    local report = item.report
    local entries = {}
    local players = type(report.players) == "table" and report.players or {}
    local order = type(report.order) == "table" and report.order or {}
    local i

    for i = 1, #order do
        local key = string.lower(tostring(order[i] or ""))
        local payload = players[key]
        local entry = addon:BuildReportEntryFromPayload(payload, i)
        if entry then
            entries[#entries + 1] = entry
        end
    end

    if #entries == 0 then
        local key
        for key in pairs(players) do
            local entry = addon:BuildReportEntryFromPayload(players[key], #entries + 1)
            if entry then
                entries[#entries + 1] = entry
            end
        end
        table.sort(entries, function(a, b)
            return string.lower(tostring(a.key or "")) < string.lower(tostring(b.key or ""))
        end)
    end

    return entries
end

function addon:GetCompositionEntries()
    local savedReportEntries = addon:GetActiveSavedReportEntries()
    if savedReportEntries then
        return savedReportEntries
    end

    local latestByKey = addon:GetLatestRequestMap()
    local entries = {}
    local key
    local now = GetNow()

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local result = RaidInspectorDB.results[key]
        local state = req.status or "queued"
        local updatedAt = 0

        if state ~= "error" and result then
            state = "ready"
        end

        if result then
            updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
        end

        table.insert(entries, {
            key = key,
            req = req,
            result = result,
            state = state,
            statusReason = req.statusReason,
            updatedAt = updatedAt,
            ageMinutes = updatedAt > 0 and math.floor(math.max(0, now - updatedAt) / 60) or -1,
            isFresh = updatedAt > 0 and (now - updatedAt) <= FRESHNESS_TTL_SECONDS,
        })
    end

    return entries
end

function addon:ImportSavedReportFiles(items, generatedAt)
    local savedReports = addon:GetSavedReportFiles()
    savedReports.generatedAt = tonumber(generatedAt) or GetNow()
    savedReports.items = {}

    local i
    for i = 1, #(items or {}) do
        local item = items[i]
        if type(item) == "table" and Trim(item.fileName or "") ~= "" then
            savedReports.items[#savedReports.items + 1] = CopyTable(item)
        end
    end

    SortSavedReportItems(savedReports.items)

    if addon:GetSelectedSavedReportFile() ~= "" and not addon:GetActiveSavedReport() then
        RaidInspectorDB.state.ui.selectedSavedReportFile = ""
    end

    return #savedReports.items
end

function addon:ClearProcessedReportQueueItems(processedIds)
    if type(processedIds) ~= "table" or #processedIds == 0 then
        return 0
    end

    local processedMap = {}
    local i
    for i = 1, #processedIds do
        local id = tonumber(processedIds[i])
        if id then
            processedMap[id] = true
        end
    end

    local queue = addon:GetReportFileQueue()
    local kept = {}
    local removed = 0
    for i = 1, #queue.items do
        local item = queue.items[i]
        local id = tonumber(item and item.id)
        if id and processedMap[id] then
            removed = removed + 1
        else
            kept[#kept + 1] = item
        end
    end

    queue.items = kept
    return removed
end

function addon:BuildCurrentDetailedReport()
    local entries = addon:GetOverviewEntries()
    if #entries == 0 then
        return nil, "no overview entries available"
    end

    local createdAt = GetNow()
    local fileName = BuildReportFileName(createdAt)
    local report = {
        schemaVersion = 1,
        createdAt = createdAt,
        fileName = fileName,
        reportLabel = "Raid Inspector " .. FormatTimestampForDisplay(createdAt),
        source = "raidinspector-addon",
        sortMode = addon:GetSortMode(),
        filterMode = addon:GetFilterMode(),
        order = {},
        players = {},
    }

    local i
    for i = 1, #entries do
        local entry = entries[i]
        local payload = addon:BuildStoredSummaryPayload(entry.key, entry.req, entry.result, entry.state, entry.statusReason)
        report.order[#report.order + 1] = payload.key
        report.players[payload.key] = payload
    end

    return report
end

function addon:QueueDetailedReport()
    local report, err = addon:BuildCurrentDetailedReport()
    if not report then
        Print(err)
        return nil
    end

    local savedReports = addon:GetSavedReportFiles()
    local fileName = tostring(report.fileName or BuildReportFileName(GetNow()))
    if addon:FindSavedReportFileItem(fileName) then
        local suffix = 2
        while addon:FindSavedReportFileItem(fileName .. "-" .. tostring(suffix)) do
            suffix = suffix + 1
        end
        fileName = fileName .. "-" .. tostring(suffix)
    end
    report.fileName = fileName

    local item = {
        createdAt = tonumber(report.createdAt) or GetNow(),
        fileName = fileName,
        label = tostring(report.reportLabel or "Raid Inspector Report"),
        report = report,
    }

    savedReports.generatedAt = GetNow()
    savedReports.items[#savedReports.items + 1] = item
    SortSavedReportItems(savedReports.items)
    while #savedReports.items > REPORT_FILE_QUEUE_LIMIT do
        table.remove(savedReports.items)
    end

    addon:SetSelectedSavedReportFile(item.fileName)
    Print("report saved: " .. addon:BuildSavedReportMenuLabel(item))
    return item
end

function addon:LoadSavedReportFile(arg)
    local savedReports = addon:GetSavedReportFiles()
    if #savedReports.items == 0 then
        Print("no saved reports yet")
        return nil
    end

    local target = string.lower(Trim(arg or ""))
    local item = nil
    if target == "" or target == "latest" then
        item = savedReports.items[1]
    else
        local i
        for i = 1, #savedReports.items do
            local candidate = savedReports.items[i]
            local fileName = string.lower(tostring(candidate.fileName or ""))
            local label = string.lower(tostring(candidate.label or candidate.reportLabel or ""))
            if fileName == target or label == target then
                item = candidate
                break
            end
        end
    end

    if not item then
        Print("saved report not found: " .. tostring(arg))
        return nil
    end

    addon:SetSelectedSavedReportFile(item.fileName)
    Print("loaded saved report: " .. addon:BuildSavedReportMenuLabel(item))
    return item
end

function addon:BuildRaidHistoryPayloadForKey(key)
    local req = addon:GetLatestRequestForKey(key)
    local result = RaidInspectorDB.results[key]
    local state = req and req.status or "queued"

    if state ~= "error" and type(result) == "table" then
        state = "ready"
    end

    return addon:BuildStoredSummaryPayload(key, req, result, state, req and req.statusReason or nil)
end

function addon:FindRaidHistoryEntryById(historyId)
    if not historyId or historyId == 0 then
        return nil
    end

    local history = addon:GetRaidScanHistory()
    local i
    for i = #history.scans, 1, -1 do
        local entry = history.scans[i]
        if tonumber(entry.id) == tonumber(historyId) then
            return entry
        end
    end

    return nil
end

function addon:RefreshRaidHistoryEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    local members = type(entry.members) == "table" and entry.members or {}
    local roster = {}
    local key

    for key in pairs(members) do
        roster[#roster + 1] = key
    end

    table.sort(roster)
    entry.members = members
    entry.roster = roster
    entry.summaryPayloads = {}

    local i
    for i = 1, #roster do
        local rosterKey = roster[i]
        entry.summaryPayloads[rosterKey] = addon:BuildRaidHistoryPayloadForKey(rosterKey)
    end

    entry.updatedAt = GetNow()
    return true
end

function addon:RefreshActiveRaidHistoryEntry()
    local snapshot = RaidInspectorDB.state.lastSnapshot
    if type(snapshot) ~= "table" then
        return false
    end

    local historyId = tonumber(snapshot.historyId) or 0
    if historyId <= 0 then
        return false
    end

    addon:PruneRaidScanHistory()
    local entry = addon:FindRaidHistoryEntryById(historyId)
    if not entry then
        snapshot.historyId = 0
        return false
    end

    entry.members = CopyTable(snapshot.members or {})
    entry.snapshotAt = tonumber(snapshot.at) or entry.snapshotAt or GetNow()
    return addon:RefreshRaidHistoryEntry(entry)
end

function addon:CreateRaidHistoryEntry(snapshotAt, members)
    if type(members) ~= "table" or next(members) == nil then
        return nil
    end

    addon:PruneRaidScanHistory()

    local history = addon:GetRaidScanHistory()
    local id = tonumber(history.nextId) or 1
    history.nextId = id + 1

    local entry = {
        id = id,
        snapshotAt = tonumber(snapshotAt) or GetNow(),
        updatedAt = tonumber(snapshotAt) or GetNow(),
        members = CopyTable(members),
        roster = {},
        summaryPayloads = {},
    }

    history.scans[#history.scans + 1] = entry
    RaidInspectorDB.state.lastSnapshot.historyId = id
    addon:RefreshRaidHistoryEntry(entry)
    return entry
end

function addon:ResolveOverviewEntry(arg)
    local entries = addon:GetOverviewEntries()
    if #entries == 0 then
        return nil, "no entries available"
    end

    local targetKey = Trim(arg or "")
    if targetKey == "" then
        targetKey = addon:GetSelectedKey()
    elseif not string.find(targetKey, "%-") then
        targetKey = MakePlayerKey(targetKey, GetRealmName() or "")
    else
        targetKey = string.lower(targetKey)
    end

    local selected = nil
    local i
    for i = 1, #entries do
        if entries[i].key == targetKey then
            selected = entries[i]
            break
        end
    end

    if not selected and targetKey ~= "" then
        return nil, "target not found in current overview: " .. targetKey
    end

    if not selected then
        selected = entries[1]
    end

    return selected
end

function addon:StoreReportSnapshot(entry, sourceTag)
    if type(entry) ~= "table" or type(entry.req) ~= "table" then
        return nil
    end

    local reports = addon:GetReportSnapshots()
    local id = tonumber(reports.nextId) or 1
    local payload = addon:BuildStoredSummaryPayload(entry.key, entry.req, entry.result, entry.state, entry.statusReason)
    local snapshot = {
        id = id,
        savedAt = GetNow(),
        source = sourceTag or "manual",
        key = payload.key,
        name = payload.name,
        realm = payload.realm,
        payload = payload,
        message = addon:BuildExportSummaryFromPayload(payload),
    }

    reports.nextId = id + 1
    reports.items[#reports.items + 1] = snapshot

    while #reports.items > REPORT_SNAPSHOT_LIMIT do
        table.remove(reports.items, 1)
    end

    return snapshot
end

function addon:FindSavedReport(arg)
    local reports = addon:GetReportSnapshots()
    if #reports.items == 0 then
        return nil, "no saved reports"
    end

    local target = string.lower(Trim(arg or ""))
    if target == "" or target == "latest" then
        return reports.items[#reports.items]
    end

    local targetId = tonumber(target)
    if targetId then
        local i
        for i = #reports.items, 1, -1 do
            if tonumber(reports.items[i].id) == targetId then
                return reports.items[i]
            end
        end
        return nil, "saved report not found: #" .. tostring(targetId)
    end

    if not string.find(target, "%-") then
        target = MakePlayerKey(target, GetRealmName() or "")
    end

    local i
    for i = #reports.items, 1, -1 do
        if reports.items[i].key == target then
            return reports.items[i]
        end
    end

    return nil, "saved report not found: " .. target
end

function addon:SetItemListFilterMode(mode)
    if not ITEM_LIST_FILTER_LABELS[mode] then
        return false
    end
    RaidInspectorDB.state.ui.itemListFilterMode = mode
    addon:RefreshMainWindow()
    return true
end

function addon:GetLatestRequestForKey(key)
    local i
    for i = #RaidInspectorDB.requests, 1, -1 do
        local req = RaidInspectorDB.requests[i]
        if req.key == key then
            return req
        end
    end
    return nil
end

function addon:GetLatestRequestMap()
    local latestByKey = {}
    local i
    local requestCount = 0

    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        if type(req) == "table" and req.key and req.key ~= "" then
            latestByKey[req.key] = req
            requestCount = requestCount + 1
        end
    end

    -- Only synthesize rows from raw results when there are no requests at all.
    -- This keeps old unrelated results from reappearing while actively inspecting others.
    if requestCount == 0 then
        local key
        for key in pairs(RaidInspectorDB.results) do
            if not latestByKey[key] then
                local result = RaidInspectorDB.results[key] or {}
                local n, r = ParseKey(key)
                latestByKey[key] = {
                    id = 0,
                    name = result.name or n or "Unknown",
                    realm = result.realm or r or "Unknown",
                    key = key,
                    status = result.error and "error" or "ready",
                    statusReason = result.error and tostring(result.error) or nil,
                    requestedAt = tonumber(result.fetchedAt) or tonumber(result.updatedAt) or 0,
                    updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0,
                }
            end
        end
    end

    return latestByKey
end

function addon:SetLatestRequestState(key, status, reason)
    local req = addon:GetLatestRequestForKey(key)
    if not req then
        return nil
    end

    req.status = status or req.status or "queued"
    req.statusReason = reason
    req.updatedAt = GetNow()
    return req
end

function addon:GetCounts()
    local queued, ready, errorCount = 0, 0, 0
    local latestByKey = addon:GetLatestRequestMap()
    local key

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local result = RaidInspectorDB.results[req.key]
        if req.status == "error" then
            errorCount = errorCount + 1
        elseif result then
            ready = ready + 1
        else
            queued = queued + 1
        end
    end

    return queued, ready, errorCount
end

function addon:GetIssueTotals()
    local playersWithIssues, totalIssues = 0, 0
    local latestByKey = addon:GetLatestRequestMap()
    local key

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local result = RaidInspectorDB.results[req.key]
        if result and tonumber(result.issuesCount or 0) and tonumber(result.issuesCount or 0) > 0 then
            playersWithIssues = playersWithIssues + 1
            totalIssues = totalIssues + tonumber(result.issuesCount)
        end
    end

    return playersWithIssues, totalIssues
end

function addon:GetFreshnessCounts(ttlSeconds)
    local fresh, stale = 0, 0
    local now = GetNow()
    local latestByKey = addon:GetLatestRequestMap()
    local key

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local result = RaidInspectorDB.results[req.key]
        if result then
            local updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
            if updatedAt > 0 and (now - updatedAt) <= ttlSeconds then
                fresh = fresh + 1
            else
                stale = stale + 1
            end
        end
    end

    return fresh, stale
end

function addon:QueueInspect(name, realm, opts)
    opts = opts or {}
    local allowDuplicate = opts.allowDuplicate ~= false
    local silent = opts.silent == true
    local queueReason = opts.reason or "queued-manual"

    local normalizedName = Trim(name)
    local normalizedRealm = Trim(realm)

    if normalizedName == "" then
        if not silent then
            Print("missing player name. usage: /ri inspect <name> <realm>")
        end
        return false
    end

    if normalizedRealm == "" then
        normalizedRealm = GetCVar("realmName") or ""
    end

    if normalizedRealm == "" then
        if not silent then
            Print("missing realm. usage: /ri inspect <name> <realm>")
        end
        return false
    end

    local key = MakePlayerKey(normalizedName, normalizedRealm)
    if not allowDuplicate and addon:GetLatestRequestForKey(key) then
        return false
    end

    local id = RaidInspectorDB.state.nextRequestId

    table.insert(RaidInspectorDB.requests, {
        id = id,
        name = normalizedName,
        realm = normalizedRealm,
        key = key,
        status = "queued",
        statusReason = queueReason,
        requestedAt = GetNow(),
        updatedAt = GetNow(),
    })

    RaidInspectorDB.state.nextRequestId = id + 1
    if not silent then
        Print("queued: " .. normalizedName .. "-" .. normalizedRealm .. " (#" .. id .. ")")
    end

    if addon.RefreshMainWindow then
        addon:RefreshMainWindow()
    end

    return true
end

-- opts.silent       - no chat summary (used by autoscan, which runs every 10s)
-- opts.reuseHistory - keep updating the current raid history entry while the
--                     roster is unchanged, instead of appending a new entry per
--                     scan. Without this an autoscan would add ~6 entries/minute.
-- opts.pruneMissing - drop list entries for players no longer on the roster, so
--                     the list tracks the raid. Autoscan only; the manual Raid
--                     button must not delete anything the user added by hand.
function addon:QueueRaidSnapshot(opts)
    opts = type(opts) == "table" and opts or {}
    local silent = opts.silent == true
    local reuseHistory = opts.reuseHistory == true
    local pruneMissing = opts.pruneMissing == true

    if not GetNumRaidMembers or GetNumRaidMembers() <= 0 then
        if not silent then
            Print("not in a raid")
        end
        return
    end

    local count = GetNumRaidMembers()
    local queued = 0
    local skipped = 0
    local liveQueued = 0
    local liveSkipped = 0
    local members = {}
    local i

    for i = 1, count do
        local rosterName = GetRaidRosterInfo(i)
        if rosterName and rosterName ~= "" then
            local name = rosterName
            local explicitRealm = GetRealmName() or ""
            local splitName, splitRealm = string.match(rosterName, "^([^%-]+)%-(.+)$")
            if splitName and splitRealm then
                name = splitName
                explicitRealm = splitRealm
            end

            local key = MakePlayerKey(name, explicitRealm)
            members[key] = true
            if addon:QueueInspect(name, explicitRealm, { allowDuplicate = false, silent = true, reason = "queued-snapshot" }) then
                queued = queued + 1
            else
                skipped = skipped + 1
            end

            local unit = "raid" .. tostring(i)
            local okLive, liveReason = addon:QueueLiveInspectUnit(unit, false)
            if okLive then
                liveQueued = liveQueued + 1
            else
                liveSkipped = liveSkipped + 1
                if liveReason == "cannot-inspect" or liveReason == "unit-not-found" then
                    addon:SetLatestRequestState(key, "queued", liveReason)
                end
            end
        end
    end

    if pruneMissing then
        local pruned = addon:PruneEntriesNotInSet(members)
        if pruned > 0 then
            Print("autoscan: removed " .. pruned .. " no longer in the raid")
        end
    end

    local snapshotAt = GetNow()
    local sameRoster = reuseHistory and MemberSetsMatch(members, RaidInspectorDB.state.lastSnapshot.members)
    RaidInspectorDB.state.lastSnapshot.at = snapshotAt
    RaidInspectorDB.state.lastSnapshot.members = members
    if sameRoster then
        -- Falls back to a new entry if the active one is gone (pruned/cleared).
        if not addon:RefreshActiveRaidHistoryEntry() then
            addon:CreateRaidHistoryEntry(snapshotAt, members)
        end
    else
        addon:CreateRaidHistoryEntry(snapshotAt, members)
    end

    addon:ProcessInspectQueue(true)
    if not silent then
        Print("raid snapshot: queued=" .. queued .. ", skipped=" .. skipped .. ", total=" .. count .. " | live=" .. liveQueued .. ", liveSkipped=" .. liveSkipped)
    end
    addon:RefreshMainWindow()
end

function addon:QueueStaleRefresh(minAgeMinutes)
    local minMinutes = tonumber(minAgeMinutes) or 30
    if minMinutes < 1 then
        minMinutes = 1
    end

    local now = GetNow()
    local queued = 0
    local unavailable = 0
    local seen = {}
    local i

    for i = #RaidInspectorDB.requests, 1, -1 do
        local req = RaidInspectorDB.requests[i]
        if not seen[req.key] then
            seen[req.key] = req
        end
    end

    local key
    for key in pairs(seen) do
        local req = seen[key]
        local result = RaidInspectorDB.results[key]
        if result then
            local updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
            local ageMinutes = math.floor(math.max(0, now - updatedAt) / 60)
            if updatedAt <= 0 or ageMinutes >= minMinutes then
                local foundUnit = addon:FindUnitByName(req.name)
                if foundUnit then
                    addon:QueueInspect(req.name, req.realm, { allowDuplicate = true, silent = true, reason = "queued-refresh" })
                    local okLive, liveReason = addon:QueueLiveInspectUnit(foundUnit, false)
                    if okLive then
                        queued = queued + 1
                    else
                        unavailable = unavailable + 1
                        addon:SetLatestRequestState(key, "queued", liveReason)
                    end
                else
                    unavailable = unavailable + 1
                    addon:SetLatestRequestState(key, "queued", "local-only")
                end
            end
        end
    end

    addon:ProcessInspectQueue(true)
    Print("stale refresh: queued=" .. queued .. ", unavailable=" .. unavailable .. ", threshold=" .. minMinutes .. "m")
    addon:RefreshMainWindow()
end

function addon:RefreshOverviewEntryByKey(key)
    local normalizedKey = string.lower(tostring(key or ""))
    if normalizedKey == "" then
        Print("refresh: missing key")
        return false
    end

    if addon:GetSelectedSavedReportFile() ~= "" then
        Print("refresh is disabled while a saved report is loaded")
        return false
    end

    local req = addon:GetLatestRequestForKey(normalizedKey)
    local name = req and req.name or nil
    local realm = req and req.realm or nil
    if not name or name == "" or not realm or realm == "" then
        local parsedName, parsedRealm = ParseKey(normalizedKey)
        name = name or parsedName
        realm = realm or parsedRealm
    end

    if not name or name == "" or not realm or realm == "" then
        Print("refresh failed: bad player key")
        return false
    end

    local foundUnit = addon:FindUnitByName(name)
    if not foundUnit then
        local targeted = addon:TryTargetNearbyPlayer(name, realm)
        if targeted then
            foundUnit = "target"
        end
    end

    if foundUnit then
        addon:QueueInspect(name, realm, { allowDuplicate = true, silent = true, reason = "queued-refresh" })
        local okLive, liveReason = addon:QueueLiveInspectUnit(foundUnit, false)
        if okLive then
            addon:SetSelectedKey(normalizedKey)
            addon:ProcessInspectQueue(true)
            addon:RefreshMainWindow()
            Print("refresh queued: " .. tostring(name) .. "-" .. tostring(realm))
            return true
        end
        addon:SetLatestRequestState(normalizedKey, "queued", liveReason)
        addon:ProcessInspectQueue(true)
        addon:RefreshMainWindow()
        Print("refresh unavailable: " .. tostring(name) .. "-" .. tostring(realm) .. " (" .. FormatStatusReason(liveReason) .. ")")
        return false
    end

    addon:SetLatestRequestState(normalizedKey, "queued", "local-only")
    addon:RefreshMainWindow()
    Print("refresh unavailable: " .. tostring(name) .. "-" .. tostring(realm) .. " is not in target/focus/mouseover/party/raid or nearby")
    return false
end

-- silent: used by the roster prune, which removes several players at once and
-- prints one summary line + refreshes the window itself.
function addon:RemoveOverviewEntryByKey(key, silent)
    local normalizedKey = string.lower(tostring(key or ""))
    if normalizedKey == "" then
        if not silent then
            Print("remove: missing key")
        end
        return false
    end

    if addon:GetSelectedSavedReportFile() ~= "" then
        if not silent then
            Print("remove is disabled while a saved report is loaded")
        end
        return false
    end

    local removedRequests = 0
    local keptRequests = {}
    local i
    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        if tostring(req.key or "") == normalizedKey then
            removedRequests = removedRequests + 1
        else
            keptRequests[#keptRequests + 1] = req
        end
    end
    RaidInspectorDB.requests = keptRequests

    local hadResult = RaidInspectorDB.results[normalizedKey] ~= nil
    RaidInspectorDB.results[normalizedKey] = nil

    local keptInspectQueue = {}
    for i = 1, #(addon.inspectQueue or {}) do
        local entry = addon.inspectQueue[i]
        if tostring(entry and entry.key or "") ~= normalizedKey then
            keptInspectQueue[#keptInspectQueue + 1] = entry
        end
    end
    addon.inspectQueue = keptInspectQueue
    addon.inspectQueuedKeys[normalizedKey] = nil
    if addon.inspectCurrent and addon.inspectCurrent.key == normalizedKey then
        addon.inspectCurrent = nil
        if ClearInspectPlayer then
            ClearInspectPlayer()
        end
    end

    local snapshot = RaidInspectorDB.state.lastSnapshot
    if type(snapshot) == "table" and type(snapshot.members) == "table" then
        snapshot.members[normalizedKey] = nil
    end
    addon:RefreshActiveRaidHistoryEntry()

    if addon:GetSelectedKey() == normalizedKey then
        addon:SetSelectedKey("")
    end

    if not silent then
        addon:RefreshMainWindow()
    end

    if removedRequests > 0 or hadResult then
        if not silent then
            Print("removed from list: " .. normalizedKey)
        end
        return true
    end

    if not silent then
        Print("remove: player not found in live list")
    end
    return false
end

-- Drops every list entry whose key is not in `members`. Used by autoscan so that
-- players who leave the raid disappear from the list instead of lingering.
-- Batch equivalent of RemoveOverviewEntryByKey: one pass, no per-key chat spam.
function addon:PruneEntriesNotInSet(members)
    if type(members) ~= "table" then
        return 0
    end

    local removed = {}
    local removedCount = 0
    local keptRequests = {}
    local i
    local key

    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        key = type(req) == "table" and tostring(req.key or "") or ""
        if key ~= "" and not members[key] then
            if not removed[key] then
                removed[key] = true
                removedCount = removedCount + 1
            end
        else
            keptRequests[#keptRequests + 1] = req
        end
    end

    for key in pairs(RaidInspectorDB.results) do
        if not members[key] and not removed[key] then
            removed[key] = true
            removedCount = removedCount + 1
        end
    end

    if removedCount == 0 then
        return 0
    end

    RaidInspectorDB.requests = keptRequests

    for key in pairs(removed) do
        RaidInspectorDB.results[key] = nil
        if addon.inspectQueuedKeys then
            addon.inspectQueuedKeys[key] = nil
        end
    end

    local keptQueue = {}
    for i = 1, #(addon.inspectQueue or {}) do
        local entry = addon.inspectQueue[i]
        local entryKey = type(entry) == "table" and tostring(entry.key or "") or ""
        if not removed[entryKey] then
            keptQueue[#keptQueue + 1] = entry
        end
    end
    addon.inspectQueue = keptQueue

    if addon.inspectCurrent and removed[addon.inspectCurrent.key] then
        addon.inspectCurrent = nil
        if ClearInspectPlayer then
            ClearInspectPlayer()
        end
    end

    if removed[addon:GetSelectedKey()] then
        addon:SetSelectedKey("")
    end

    return removedCount
end

function addon:GetSnapshotProgress()
    local snapshot = RaidInspectorDB.state.lastSnapshot
    if type(snapshot) ~= "table" or type(snapshot.members) ~= "table" then
        return nil
    end

    local total = 0
    local ready = 0
    local stale = 0
    local missing = 0
    local now = GetNow()
    local key

    for key in pairs(snapshot.members) do
        total = total + 1
        local result = RaidInspectorDB.results[key]
        if not result then
            missing = missing + 1
        else
            local updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
            if updatedAt > 0 and (now - updatedAt) <= FRESHNESS_TTL_SECONDS then
                ready = ready + 1
            else
                stale = stale + 1
            end
        end
    end

    if total == 0 then
        return nil
    end

    return {
        total = total,
        ready = ready,
        stale = stale,
        missing = missing,
        at = tonumber(snapshot.at) or 0,
    }
end

function addon:QueueTarget()
    if not UnitExists("target") then
        Print("no target selected")
        return
    end

    local name, targetRealm = UnitName("target")
    local realm = targetRealm
    if not realm or realm == "" then
        realm = GetRealmName() or ""
    end

    if not name or name == "" then
        Print("target has no valid name")
        return
    end

    if realm == "" then
        Print("target has no valid realm")
        return
    end

    local key = MakePlayerKey(name, realm)

    addon:QueueInspect(name, realm, { allowDuplicate = false, silent = true, reason = "queued-target" })
    addon:SetSelectedKey(key)
    local okLive, reason = addon:QueueLiveInspectUnit("target", false)
    addon:ProcessInspectQueue(true)
    addon:RefreshMainWindow()

    if reason == "cannot-inspect" or reason == "unit-not-found" then
        addon:SetLatestRequestState(key, "queued", reason)
    end

    if okLive then
        Print("target queued + live inspect: " .. name .. "-" .. realm)
    elseif reason == "cannot-inspect" then
        Print("target queued, but not inspectable right now (range/permissions)")
    else
        Print("target queued: " .. name .. "-" .. realm)
    end
end

function addon:GetOverviewEntries()
    local savedReportEntries = addon:GetActiveSavedReportEntries()
    if savedReportEntries then
        return savedReportEntries
    end

    local latestByKey = addon:GetLatestRequestMap()

    local entries = {}
    local key
    local now = GetNow()

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local result = RaidInspectorDB.results[key]
        local state = req.status or "queued"
        local updatedAt = 0

        if state ~= "error" and result then
            state = "ready"
        end

        if result then
            updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
        end

        table.insert(entries, {
            key = key,
            req = req,
            result = result,
            state = state,
            statusReason = req.statusReason,
            updatedAt = updatedAt,
            ageMinutes = updatedAt > 0 and math.floor(math.max(0, now - updatedAt) / 60) or -1,
            isFresh = updatedAt > 0 and (now - updatedAt) <= FRESHNESS_TTL_SECONDS,
        })
    end

    local filterMode = addon:GetFilterMode()
    local filtered = {}
    for i = 1, #entries do
        local entry = entries[i]
        local include = true
        local issuesCount = entry.result and tonumber(entry.result.issuesCount or 0) or 0

        if filterMode == "snapshot" then
            local snapshot = RaidInspectorDB.state.lastSnapshot
            include = type(snapshot) == "table"
                and type(snapshot.members) == "table"
                and snapshot.members[entry.key] == true
        elseif filterMode == "ready" then
            include = entry.state == "ready"
        elseif filterMode == "queued" then
            include = entry.state == "queued"
        elseif filterMode == "issues" then
            include = issuesCount > 0
        end

        if include then
            table.insert(filtered, entry)
        end
    end

    local sortMode = addon:GetSortMode()
    table.sort(filtered, function(a, b)
        local aIssues = a.result and tonumber(a.result.issuesCount or 0) or 0
        local bIssues = b.result and tonumber(b.result.issuesCount or 0) or 0
        local aGs = a.result and tonumber(a.result.gearScore or -1) or -1
        local bGs = b.result and tonumber(b.result.gearScore or -1) or -1
        local aId = tonumber(a.req.id) or 0
        local bId = tonumber(b.req.id) or 0

        if sortMode == "gs" then
            if aGs ~= bGs then
                return aGs > bGs
            end
            return aId > bId
        end

        if sortMode == "issues" then
            if aIssues ~= bIssues then
                return aIssues > bIssues
            end
            return aId > bId
        end

        if sortMode == "name" then
            local aName = string.lower((a.req.name or "") .. "-" .. (a.req.realm or ""))
            local bName = string.lower((b.req.name or "") .. "-" .. (b.req.realm or ""))
            return aName < bName
        end

        -- MS: players who announced a spec change float to the top, most
        -- recent declaration first; everyone else keeps the default order.
        if sortMode == "ms" then
            local aMs = addon:GetMainSpecRecord(a.key)
            local bMs = addon:GetMainSpecRecord(b.key)
            local aSeq = aMs and (tonumber(aMs.seq) or 0) or 0
            local bSeq = bMs and (tonumber(bMs.seq) or 0) or 0
            if aSeq ~= bSeq then
                return aSeq > bSeq
            end
            return aId > bId
        end

        return aId > bId
    end)

    return filtered
end

function addon:SetSelectedKey(key)
    RaidInspectorDB.state.ui.selectedKey = key or ""
end

function addon:GetSelectedKey()
    return RaidInspectorDB.state.ui.selectedKey or ""
end

function addon:CycleSortMode()
    local mode = addon:GetSortMode()
    local i
    for i = 1, #SORT_MODES do
        if SORT_MODES[i] == mode then
            local nextIndex = i + 1
            if nextIndex > #SORT_MODES then
                nextIndex = 1
            end
            RaidInspectorDB.settings.overview.sortMode = SORT_MODES[nextIndex]
            addon:RefreshMainWindow()
            return
        end
    end
    RaidInspectorDB.settings.overview.sortMode = SORT_MODES[1]
    addon:RefreshMainWindow()
end

function addon:CycleFilterMode()
    local mode = addon:GetFilterMode()
    local i
    for i = 1, #FILTER_MODES do
        if FILTER_MODES[i] == mode then
            local nextIndex = i + 1
            if nextIndex > #FILTER_MODES then
                nextIndex = 1
            end
            RaidInspectorDB.settings.overview.filterMode = FILTER_MODES[nextIndex]
            addon:RefreshMainWindow()
            return
        end
    end
    RaidInspectorDB.settings.overview.filterMode = FILTER_MODES[1]
    addon:RefreshMainWindow()
end

function addon:SetSortMode(mode)
    if not SORT_LABELS[mode] then
        return false
    end
    RaidInspectorDB.settings.overview.sortMode = mode
    addon:RefreshMainWindow()
    return true
end

function addon:SetFilterMode(mode)
    if not FILTER_LABELS[mode] then
        return false
    end
    RaidInspectorDB.settings.overview.filterMode = mode
    addon:RefreshMainWindow()
    return true
end

function addon:BuildOverviewRows(container, rowCount)
    container.rows = container.rows or {}
    local i
    local rowWidth = tonumber(container:GetWidth()) or 432
    local actionWidth = 18
    local actionGap = 4
    -- three icons now: refresh, remove, and the gear-preview button
    local actionArea = (actionWidth * 3) + (actionGap * 2) + 8
    local containerHeight = tonumber(container:GetHeight()) or 0
    local maxVisibleRows = math.max(1, math.min(OVERVIEW_VISIBLE_ROWS, math.floor(containerHeight / OVERVIEW_ROW_HEIGHT)))
    local parentLevel = (container.GetParent and container:GetParent() and container:GetParent():GetFrameLevel()) or 0

    if rowCount then
        rowCount = math.max(1, math.min(tonumber(rowCount) or maxVisibleRows, maxVisibleRows))
    else
        rowCount = maxVisibleRows
    end

    for i = 1, rowCount do
        local row = CreateFrame("Button", nil, container)
        row:SetWidth(rowWidth)
        row:SetHeight(OVERVIEW_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * OVERVIEW_ROW_HEIGHT)
        row:SetFrameStrata("DIALOG")
        row:SetFrameLevel(parentLevel + 10)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", row, "LEFT", 2, 0)
        text:SetWidth(rowWidth - actionArea)
        text:SetHeight(OVERVIEW_ROW_HEIGHT)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("MIDDLE")
        -- MS:<spec> is far longer than the Scanned=Xm it replaces, so without
        -- this a long name + issues + MS wraps and draws over the next row.
        if text.SetWordWrap then
            text:SetWordWrap(false)
        end
        if text.GetFont and text.SetFont then
            local fontName, fontHeight, fontFlags = text:GetFont()
            if fontName and fontHeight then
                text:SetFont(fontName, fontHeight + 1, fontFlags)
            end
        end
        text:SetText("")
        text:Show()

        -- Small square icon buttons (refresh arrow + red X) instead of text buttons.
        local refreshButton = CreateFrame("Button", nil, row)
        refreshButton:SetWidth(actionWidth)
        refreshButton:SetHeight(actionWidth)
        refreshButton:SetPoint("RIGHT", row, "RIGHT", -(2 * (actionWidth + actionGap) + 4), 0)
        refreshButton:SetFrameStrata("DIALOG")
        refreshButton:SetFrameLevel(parentLevel + 12)
        refreshButton:SetNormalTexture("Interface\\Buttons\\UI-RotationRight-Button-Up")
        refreshButton:SetPushedTexture("Interface\\Buttons\\UI-RotationRight-Button-Down")
        refreshButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        refreshButton:Hide()
        refreshButton:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Refresh")
                GameTooltip:Show()
            end
        end)
        refreshButton:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        refreshButton:SetScript("OnClick", function(self)
            SafeInvoke("row-refresh", function()
                local targetKey = self.key or row.key
                if targetKey and targetKey ~= "" then
                    addon:RefreshOverviewEntryByKey(targetKey)
                end
            end)
        end)

        local removeButton = CreateFrame("Button", nil, row)
        removeButton:SetWidth(actionWidth)
        removeButton:SetHeight(actionWidth)
        removeButton:SetPoint("RIGHT", row, "RIGHT", -(actionWidth + actionGap + 4), 0)
        removeButton:SetFrameStrata("DIALOG")
        removeButton:SetFrameLevel(parentLevel + 12)
        removeButton:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        removeButton:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        removeButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        removeButton:Hide()
        removeButton:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Remove")
                GameTooltip:Show()
            end
        end)
        removeButton:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        removeButton:SetScript("OnClick", function(self)
            SafeInvoke("row-remove", function()
                local targetKey = self.key or row.key
                if targetKey and targetKey ~= "" then
                    addon:RemoveOverviewEntryByKey(targetKey)
                end
            end)
        end)

        -- Gear preview: opens a character-panel-style window populated from this
        -- player's stored gear. Shown on any row that has gear, so it works for
        -- saved lists and offline players, not just the live-selected row.
        local gearButton = CreateFrame("Button", nil, row)
        gearButton:SetWidth(actionWidth)
        gearButton:SetHeight(actionWidth)
        gearButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        gearButton:SetFrameStrata("DIALOG")
        gearButton:SetFrameLevel(parentLevel + 12)
        gearButton:SetNormalTexture("Interface\\Icons\\INV_Chest_Plate06")
        gearButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        gearButton:Hide()
        gearButton:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("View gear")
                GameTooltip:Show()
            end
        end)
        gearButton:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        gearButton:SetScript("OnClick", function(self)
            SafeInvoke("row-gear", function()
                local targetKey = self.key or row.key
                if targetKey and targetKey ~= "" then
                    addon:ShowGearPreview(targetKey)
                end
            end)
        end)

        row.text = text
        row.refreshButton = refreshButton
        row.removeButton = removeButton
        row.gearButton = gearButton
        row.key = nil
        row.playerName = nil
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                -- Plain right-click edits the MS; shift+right-click keeps the
                -- old copy-name dialog, matching the gear detail rows.
                if IsShiftKeyDown() then
                    SafeInvoke("row-copy", function()
                        local value, label = addon:GetOverviewRowCopyValue(self)
                        if value then
                            addon:ShowCopyDialog(value, label)
                        end
                    end)
                    return
                end
                SafeInvoke("row-ms-edit", function()
                    -- Saved reports are read-only; editing there would silently
                    -- rewrite the live MS list from a historical view.
                    if addon:GetSelectedSavedReportFile() ~= "" then
                        Print("MS: switch to Live Overview to edit MS")
                        return
                    end
                    addon:ShowMainSpecEditDialog(self.key, self.playerName)
                end)
                return
            end
            if self.key then
                addon:SetSelectedKey(self.key)
                addon:RefreshMainWindow()
            end
        end)

        container.rows[i] = row
    end
end

-- Sets a font string's text, shortening it with an ellipsis (binary search on
-- the real rendered width) when it would overflow maxWidth.
local function SetTruncatedText(fontString, text, maxWidth)
    text = tostring(text or "")
    fontString:SetText(text)
    if not fontString.GetStringWidth or fontString:GetStringWidth() <= maxWidth then
        return
    end

    local lo, hi, best = 1, #text, 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        fontString:SetText(string.sub(text, 1, mid) .. "...")
        if fontString:GetStringWidth() <= maxWidth then
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    fontString:SetText(string.sub(text, 1, best) .. "...")
end

local function ClearDetailRowColumns(row)
    if not row or not row.colFS then
        return
    end
    local c
    for c = 1, #DETAIL_COLUMNS do
        local fs = row.colFS[DETAIL_COLUMNS[c].key]
        if fs then
            fs:SetText("")
        end
    end
end

function addon:BuildDetailRows(container, rowCount)
    container.rows = container.rows or {}
    local i
    local rowWidth = tonumber(container:GetWidth()) or 442

    for i = 1, rowCount do
        local row = CreateFrame("Button", nil, container)
        row:SetWidth(rowWidth)
        row:SetHeight(DETAIL_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * DETAIL_ROW_HEIGHT)
        row:EnableMouse(true)

        -- One FontString per fixed column (Slot / Item Name / iLvl / Enchant / Gems).
        row.colFS = {}
        local c
        for c = 1, #DETAIL_COLUMNS do
            local col = DETAIL_COLUMNS[c]
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
            fs:SetWidth(col.width)
            fs:SetHeight(DETAIL_ROW_HEIGHT)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("MIDDLE")
            if fs.SetWordWrap then
                fs:SetWordWrap(false)
            end
            if fs.GetFont and fs.SetFont then
                local fontName, fontHeight, fontFlags = fs:GetFont()
                if fontName and fontHeight then
                    fs:SetFont(fontName, fontHeight + 1, fontFlags)
                end
            end
            fs:SetText("")
            row.colFS[col.key] = fs
        end

        row.data = nil
        row:RegisterForClicks("RightButtonUp")
        row:SetScript("OnEnter", function(self)
            addon:ShowDetailRowTooltip(self)
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        row:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then
                return
            end
            -- Shift+right-click copies the value; plain right-click opens AtlasLoot.
            if IsShiftKeyDown() then
                SafeInvoke("detail-copy", function()
                    local value, label = addon:GetDetailRowCopyValue(self)
                    if value then
                        addon:ShowCopyDialog(value, label)
                    end
                end)
                return
            end
            SafeInvoke("detail-atlasloot", function()
                if not addon:OpenItemInAtlasLoot(self) then
                    local value, label = addon:GetDetailRowCopyValue(self)
                    if value then
                        addon:ShowCopyDialog(value, label)
                    end
                end
            end)
        end)

        container.rows[i] = row
    end
end

function addon:RefreshAutoScanButton()
    if not addon.ui or not addon.ui.autoScanButton then
        return
    end

    if addon:IsAutoScanEnabled() then
        addon.ui.autoScanButton:SetText("|cff66ff66Autoscan: on|r")
    else
        addon.ui.autoScanButton:SetText("|cff999999Autoscan: off|r")
    end
end

function addon:RefreshMSButton()
    if not addon.ui or not addon.ui.msButton then
        return
    end

    if addon:IsMSTrackingEnabled() then
        addon.ui.msButton:SetText("|cff66ff66MS: on|r")
    else
        addon.ui.msButton:SetText("|cff999999MS: off|r")
    end

    if addon.ui.msShareButton then
        local count = addon:GetMainSpecCount()
        if count > 0 then
            addon.ui.msShareButton:SetText("|cff66ff66MS Share (" .. tostring(count) .. ")|r")
        else
            addon.ui.msShareButton:SetText("|cff66ff66MS Share|r")
        end
    end
end

function addon:ApplyButtonModeLayout()
    if not addon.ui or not addon.ui.actionPanel then
        return
    end

    addon:RefreshAutoScanButton()
    addon:RefreshMSButton()

    local ACTION_BUTTON_WIDTH = 100
    local ACTION_BUTTON_HEIGHT = 20
    local ACTION_BUTTON_SPACING_X = 6
    local ACTION_BUTTON_SPACING_Y = 6
    local ACTION_BUTTON_COLUMNS = 3

    local buttons = {
        sort = addon.ui.sortButton,
        filter = addon.ui.filterButton,
        target = addon.ui.targetButton,
        raid = addon.ui.raidButton,
        autoscan = addon.ui.autoScanButton,
        sync = addon.ui.syncButton,
        force = addon.ui.forceSyncButton,
        report = addon.ui.reportButton,
        stale = addon.ui.staleButton,
        status = addon.ui.statusButton,
        clear = addon.ui.clearButton,
        ms = addon.ui.msButton,
        msshare = addon.ui.msShareButton,
        msclear = addon.ui.msClearButton,
    }

    -- Filter, Status, Stale/Refresh, and Save One were removed from the window;
    -- their slash commands (/ri filter, /ri status, /ri refreshstale, /ri savereport) still work.
    local visible = {
        sort = false,
        filter = false,
        target = true,
        raid = true,
        autoscan = true,
        sync = true,
        force = false,
        report = true,
        stale = false,
        status = false,
        clear = true,
        ms = true,
        msshare = true,
        msclear = true,
    }

    local order = { "target", "raid", "autoscan", "sync", "report", "clear", "ms", "msshare", "msclear" }

    local key, button
    for key, button in pairs(buttons) do
        if button then
            if visible[key] then
                button:Show()
            else
                button:Hide()
            end
        end
    end

    local visibleCount = 0
    for i = 1, #order do
        key = order[i]
        if buttons[key] and visible[key] then
            visibleCount = visibleCount + 1
        end
    end

    local buttonRows = math.max(1, math.ceil(visibleCount / ACTION_BUTTON_COLUMNS))
    addon.ui.actionPanel:SetWidth((ACTION_BUTTON_WIDTH * ACTION_BUTTON_COLUMNS) + (ACTION_BUTTON_SPACING_X * (ACTION_BUTTON_COLUMNS - 1)))
    addon.ui.actionPanel:SetHeight((ACTION_BUTTON_HEIGHT * buttonRows) + (ACTION_BUTTON_SPACING_Y * (buttonRows - 1)))

    local index = 0
    local i
    for i = 1, #order do
        key = order[i]
        button = buttons[key]
        if button and visible[key] then
            local col = index - (math.floor(index / ACTION_BUTTON_COLUMNS) * ACTION_BUTTON_COLUMNS)
            local row = math.floor(index / ACTION_BUTTON_COLUMNS)
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT",
                addon.ui.actionPanel,
                "TOPLEFT",
                col * (ACTION_BUTTON_WIDTH + ACTION_BUTTON_SPACING_X),
                -(row * (ACTION_BUTTON_HEIGHT + ACTION_BUTTON_SPACING_Y))
            )
            index = index + 1
        end
    end
end

local function BuildInspectItemHyperlink(item)
    local itemId = tonumber(item and item.itemId)
    if not itemId then
        return nil
    end

    local enchantId = tonumber(item.enchantId) or 0
    local gem1, gem2, gem3 = 0, 0, 0
    if type(item.gems) == "table" then
        gem1 = tonumber(item.gems[1]) or 0
        gem2 = tonumber(item.gems[2]) or 0
        gem3 = tonumber(item.gems[3]) or 0
    end

    return "item:" .. tostring(itemId)
        .. ":" .. tostring(enchantId)
        .. ":" .. tostring(gem1)
        .. ":" .. tostring(gem2)
        .. ":" .. tostring(gem3)
        .. ":0:0:0"
end

function addon:ShowDetailRowTooltip(row)
    if not row or type(row.data) ~= "table" or type(row.data.item) ~= "table" or not GameTooltip then
        return
    end

    local data = row.data
    local item = data.item
    local slotLabel = SLOT_LABELS[data.slotKey or ""] or tostring(data.slotKey or "Item")
    local itemLink = BuildInspectItemHyperlink(item)

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        local itemName = item.name or (item.itemId and ("item:" .. tostring(item.itemId))) or "Unknown item"
        GameTooltip:ClearLines()
        GameTooltip:AddLine(slotLabel .. ": " .. itemName, 1, 1, 1)
    end

    local enchantText = "n/a"
    if ENCHANTABLE_SLOTS[data.slotKey] then
        local enchantId = GetRecordedEnchantId(item)
        if not enchantId then
            if OPTIONAL_ENCHANT_SLOTS[data.slotKey] then
                enchantText = "optional"
            else
                enchantText = "missing"
            end
        elseif IsLowTierEnchant(item) then
            enchantText = "low tier (" .. tostring(enchantId) .. ")"
        else
            enchantText = "ok (" .. tostring(enchantId) .. ")"
        end
    end

    local socketCount = tonumber(item.socketCount) or 0
    local gems = type(item.gems) == "table" and item.gems or {}
    local gemCount = #gems

    if ENCHANTABLE_SLOTS[data.slotKey] or socketCount > 0 then
        GameTooltip:AddLine(" ")
        if ENCHANTABLE_SLOTS[data.slotKey] then
            GameTooltip:AddLine("Enchant: " .. enchantText, 0.9, 0.9, 0.9)
        end
        if socketCount > 0 then
            GameTooltip:AddLine("Sockets: " .. tostring(gemCount) .. "/" .. tostring(socketCount), 0.9, 0.9, 0.9)
            local idx
            for idx = 1, socketCount do
                local gemId = tonumber(gems[idx])
                if gemId and gemId > 0 then
                    local gemName = GetItemInfo(gemId)
                    if not gemName or gemName == "" then
                        gemName = "item:" .. tostring(gemId)
                    end
                    GameTooltip:AddLine("  Gem " .. tostring(idx) .. ": " .. tostring(gemName), 0.5, 1, 0.5)
                else
                    GameTooltip:AddLine("  Gem " .. tostring(idx) .. ": missing", 1, 0.3, 0.3)
                end
            end
        end
    end

    GameTooltip:Show()
end

--[[-------------------------------------------------------------------------
    Saved-gear preview ("paper doll") window
    Opens a character-panel-style layout for any list entry - live OR saved -
    and fills each equipment slot from the gear RaidInspector has stored, so an
    offline or long-gone player's gear can still be browsed with real item
    tooltips on mouseover, exactly like the character info screen.
---------------------------------------------------------------------------]]

local GEAR_DOLL_LEFT = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot" }
local GEAR_DOLL_RIGHT = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local GEAR_DOLL_BOTTOM = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

local GEAR_SLOT_SIZE = 36
local GEAR_SLOT_PITCH = 40
local GEAR_DOLL_HEADER = 74
local GEAR_DOLL_WIDTH = 300

-- Empty-slot background texture for a slot key, taken from the client itself so
-- it always matches this build (avoids hardcoding PaperDoll texture paths).
local function GetEmptySlotTexture(slotKey)
    if GetInventorySlotInfo then
        local ok, _, texture = pcall(GetInventorySlotInfo, slotKey)
        if ok and texture then
            return texture
        end
    end
    return nil
end

local function GetGearItemIcon(item)
    if type(item) ~= "table" then
        return nil
    end
    local itemId = tonumber(item.itemId)
    if itemId and GetItemIcon then
        local tex = GetItemIcon(itemId)
        if tex then
            return tex
        end
    end
    local link = BuildInspectItemHyperlink(item)
    if link then
        local tex = select(10, GetItemInfo(link))
        if tex then
            return tex
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- True when an item is missing an enchant it should have, or has an empty gem
-- socket. Mirrors the "issues" list filter's per-item rule so the red slot icon
-- lines up with the audit counts.
local function GearSlotHasIssue(item, slotKey)
    if type(item) ~= "table" then
        return false
    end
    if ENCHANTABLE_SLOTS[slotKey] and not OPTIONAL_ENCHANT_SLOTS[slotKey]
        and not GetRecordedEnchantId(item) then
        return true
    end
    local socketCount = tonumber(item.socketCount) or 0
    local gemCount = (type(item.gems) == "table") and #item.gems or 0
    if socketCount > 0 and gemCount < socketCount then
        return true
    end
    return false
end

local function GearSlot_OnEnter(self)
    if not GameTooltip then
        return
    end
    if self.data and type(self.data.item) == "table" then
        -- Reuse the detail-list tooltip: real item link + enchant/gem fallback.
        addon:ShowDetailRowTooltip(self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(SLOT_LABELS[self.slotKey] or "Slot", 1, 1, 1)
        GameTooltip:AddLine("Empty", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
end

local function GearSlot_OnLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- Right-click a filled slot to open the item in AtlasLoot (shift+right-click
-- copies it instead), exactly like the gear detail list. The slot's .data is the
-- same {item, slotKey} shape those rows use, so the existing helpers just work.
local function GearSlot_OnClick(self, button)
    if button ~= "RightButton" then
        return
    end
    if not (self.data and type(self.data.item) == "table") then
        return
    end
    if IsShiftKeyDown() then
        SafeInvoke("gear-slot-copy", function()
            local value, label = addon:GetDetailRowCopyValue(self)
            if value then
                addon:ShowCopyDialog(value, label)
            end
        end)
        return
    end
    SafeInvoke("gear-slot-atlasloot", function()
        if not addon:OpenItemInAtlasLoot(self) then
            local value, label = addon:GetDetailRowCopyValue(self)
            if value then
                addon:ShowCopyDialog(value, label)
            end
        end
    end)
end

local function CreateGearSlot(parent, slotKey)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(GEAR_SLOT_SIZE)
    btn:SetHeight(GEAR_SLOT_SIZE)
    btn.slotKey = slotKey

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    local emptyTex = GetEmptySlotTexture(slotKey)
    if emptyTex then
        bg:SetTexture(emptyTex)
    else
        bg:SetTexture(0.1, 0.1, 0.1, 0.6)
    end
    btn.bg = bg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the icon's built-in border
    icon:Hide()
    btn.icon = icon

    -- Quality glow, tinted per item quality (same texture action buttons use).
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)
    border:SetWidth(GEAR_SLOT_SIZE * 1.9)
    border:SetHeight(GEAR_SLOT_SIZE * 1.9)
    border:Hide()
    btn.border = border

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:RegisterForClicks("RightButtonUp")
    btn:SetScript("OnEnter", GearSlot_OnEnter)
    btn:SetScript("OnLeave", GearSlot_OnLeave)
    btn:SetScript("OnClick", GearSlot_OnClick)
    return btn
end

function addon:EnsureGearPreviewFrame()
    if addon.ui and addon.ui.gearPreview then
        return addon.ui.gearPreview
    end
    addon.ui = addon.ui or {}

    local width = GEAR_DOLL_WIDTH
    local columnRows = #GEAR_DOLL_RIGHT -- the taller of the two columns
    local height = GEAR_DOLL_HEADER + (columnRows * GEAR_SLOT_PITCH) + GEAR_SLOT_PITCH + 24

    local f = CreateFrame("Frame", "RaidInspectorGearPreview", UIParent)
    f:SetWidth(width)
    f:SetHeight(height)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    if f.SetToplevel then
        f:SetToplevel(true)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    f.titleText = title

    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOP", title, "BOTTOM", 0, -4)
    f.infoText = info

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- Legend: red = missing enchant or empty gem socket.
    local legend = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    legend:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    legend:SetText("red icon = missing enchant or gem")
    legend:SetTextColor(1.0, 0.4, 0.4)
    f.legend = legend

    f.slots = {}
    local leftX = 16
    local rightX = width - 16 - GEAR_SLOT_SIZE
    local topY = -GEAR_DOLL_HEADER
    local idx

    for idx = 1, #GEAR_DOLL_LEFT do
        local slotKey = GEAR_DOLL_LEFT[idx]
        local btn = CreateGearSlot(f, slotKey)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", leftX, topY - (idx - 1) * GEAR_SLOT_PITCH)
        f.slots[slotKey] = btn
    end

    for idx = 1, #GEAR_DOLL_RIGHT do
        local slotKey = GEAR_DOLL_RIGHT[idx]
        local btn = CreateGearSlot(f, slotKey)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", rightX, topY - (idx - 1) * GEAR_SLOT_PITCH)
        f.slots[slotKey] = btn
    end

    local bottomCount = #GEAR_DOLL_BOTTOM
    local bottomGap = 8
    local bottomWidth = (bottomCount * GEAR_SLOT_SIZE) + ((bottomCount - 1) * bottomGap)
    local bottomStartX = math.floor((width - bottomWidth) / 2)
    local bottomY = topY - (#GEAR_DOLL_RIGHT * GEAR_SLOT_PITCH) - 6
    for idx = 1, bottomCount do
        local slotKey = GEAR_DOLL_BOTTOM[idx]
        local btn = CreateGearSlot(f, slotKey)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", bottomStartX + (idx - 1) * (GEAR_SLOT_SIZE + bottomGap), bottomY)
        f.slots[slotKey] = btn
    end

    f:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "RaidInspectorGearPreview") -- Escape closes it
    end
    addon.ui.gearPreview = f
    return f
end

function addon:FindOverviewEntryByKey(key)
    if not key or key == "" then
        return nil
    end
    local entries = addon:GetOverviewEntries()
    local i
    for i = 1, #entries do
        if entries[i].key == key then
            return entries[i]
        end
    end
    return nil
end

function addon:ShowGearPreview(key)
    local entry = addon:FindOverviewEntryByKey(key)
    if not entry then
        Print("no stored gear to preview for that player")
        return
    end

    local result = entry.result
    local req = entry.req or {}
    local f = addon:EnsureGearPreviewFrame()

    local name = SafeText((result and result.name) or req.name)
    if result and result.class then
        f.titleText:SetText(ColorClassText(name, result.class))
    else
        f.titleText:SetText(name)
    end

    if result then
        local levelText = result.level and tostring(result.level) or "?"
        local classText = result.class and tostring(result.class) or "?"
        local specText = result.spec and tostring(result.spec) or "?"
        local gsText = result.gearScore
            and ColorText(tostring(result.gearScore), GetGearScoreColorCode(result.gearScore))
            or "N/A"
        f.infoText:SetText(
            "Lvl " .. levelText
            .. " " .. ColorClassText(classText, result.class)
            .. " " .. ColorText(specText, "ff9933")
            .. "  |  GS: " .. gsText
        )
    else
        f.infoText:SetText("No stored gear for this player.")
    end

    -- Map stored items onto slots (first item per slot wins, as the detail list).
    local itemsBySlot = {}
    if result and type(result.items) == "table" then
        local i
        for i = 1, #result.items do
            local item = result.items[i]
            local slot = NormalizeSlot(item.slot)
            if slot and not itemsBySlot[slot] then
                itemsBySlot[slot] = item
            end
        end
    end

    local slotKey, btn
    for slotKey, btn in pairs(f.slots) do
        local item = itemsBySlot[slotKey]
        if item then
            btn.data = { item = item, slotKey = slotKey }
            btn.icon:SetTexture(GetGearItemIcon(item))
            btn.icon:Show()
            if GearSlotHasIssue(item, slotKey) then
                -- Missing enchant or empty gem socket: flag the slot red.
                btn.icon:SetVertexColor(1, 0.3, 0.3)
                btn.border:SetVertexColor(1, 0.1, 0.1)
                btn.border:Show()
            else
                btn.icon:SetVertexColor(1, 1, 1)
                local quality = tonumber(item.quality)
                local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                if qc and quality > 0 then
                    btn.border:SetVertexColor(qc.r, qc.g, qc.b)
                    btn.border:Show()
                else
                    btn.border:Hide()
                end
            end
        else
            btn.data = nil
            btn.icon:SetVertexColor(1, 1, 1)
            btn.icon:Hide()
            btn.border:Hide()
        end
    end

    f:Show()
    if f.Raise then
        f:Raise()
    end
end

-- Pops a small dialog containing a pre-selected, focused EditBox so the player
-- can press Ctrl+C to copy the value to the OS clipboard (3.3.5a has no direct
-- clipboard API, so an EditBox is the standard copy mechanism).
function addon:ShowCopyDialog(text, label)
    text = SafeText(text)
    if text == "" or text == "?" then
        return
    end

    addon.ui = addon.ui or {}
    local dialog = addon.ui.copyDialog

    if not dialog then
        dialog = CreateFrame("Frame", "RaidInspectorCopyDialog", UIParent)
        dialog:SetWidth(360)
        dialog:SetHeight(108)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetToplevel(true)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        dialog:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        if dialog.SetBackdropColor then
            dialog:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
        end
        if dialog.SetBackdropBorderColor then
            dialog:SetBackdropBorderColor(0.85, 0.72, 0.18, 1)
        end

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -14)
        title:SetJustifyH("LEFT")
        dialog.title = title

        local editBox = CreateFrame("EditBox", "RaidInspectorCopyDialogEditBox", dialog, "InputBoxTemplate")
        editBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -38)
        editBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -20, -38)
        editBox:SetHeight(20)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dialog:Hide()
        end)
        editBox:SetScript("OnEnterPressed", function(self)
            self:HighlightText()
        end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        editBox:SetScript("OnTextChanged", function(self)
            if self.settingText then
                return
            end
            self.settingText = true
            self:SetText(self.copyText or "")
            self.settingText = false
            self:HighlightText()
        end)
        dialog.editBox = editBox

        local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -10)
        hint:SetText("Press Ctrl+C to copy, then Esc to close.")
        dialog.hint = hint

        local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        closeButton:SetWidth(72)
        closeButton:SetHeight(20)
        closeButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 12)
        closeButton:SetText("Close")
        closeButton:SetScript("OnClick", function()
            dialog.editBox:ClearFocus()
            dialog:Hide()
        end)
        dialog.closeButton = closeButton

        addon.ui.copyDialog = dialog
    end

    dialog.title:SetText((label and label ~= "" and label) or "Copy value")

    local editBox = dialog.editBox
    editBox.copyText = text
    editBox.settingText = true
    editBox:SetText(text)
    editBox.settingText = false

    dialog:Show()
    editBox:SetFocus()
    editBox:SetCursorPosition(0)
    editBox:HighlightText()
end

-- Right-clicking an overview row edits that player's MS by hand, for the ones
-- who never typed it in raid chat (or typed it wrong). Saving an empty box
-- removes the record.
function addon:ShowMainSpecEditDialog(key, playerName)
    if type(key) ~= "string" or key == "" then
        return
    end

    local parsedName, parsedRealm = ParseKey(key)
    local name = playerName
    if not name or name == "" then
        name = parsedName or key
    end

    addon.ui = addon.ui or {}
    local dialog = addon.ui.msEditDialog

    if not dialog then
        dialog = CreateFrame("Frame", "RaidInspectorMSEditDialog", UIParent)
        dialog:SetWidth(340)
        dialog:SetHeight(126)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetToplevel(true)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        dialog:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        if dialog.SetBackdropColor then
            dialog:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
        end
        if dialog.SetBackdropBorderColor then
            dialog:SetBackdropBorderColor(0.85, 0.72, 0.18, 1)
        end

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -14)
        title:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -16, -14)
        title:SetJustifyH("LEFT")
        dialog.title = title

        local editBox = CreateFrame("EditBox", "RaidInspectorMSEditDialogEditBox", dialog, "InputBoxTemplate")
        editBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -38)
        editBox:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -20, -38)
        editBox:SetHeight(20)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(MS_MAX_SPEC_LENGTH)
        editBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dialog:Hide()
        end)
        dialog.editBox = editBox

        local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -8)
        hint:SetText("Enter saves, empty box clears the MS. Esc closes.")
        dialog.hint = hint

        local saveButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        saveButton:SetWidth(72)
        saveButton:SetHeight(20)
        saveButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 12)
        saveButton:SetText("Save")
        dialog.saveButton = saveButton

        local cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        cancelButton:SetWidth(72)
        cancelButton:SetHeight(20)
        cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
        cancelButton:SetText("Cancel")
        cancelButton:SetScript("OnClick", function()
            dialog.editBox:ClearFocus()
            dialog:Hide()
        end)
        dialog.cancelButton = cancelButton

        -- Commits whatever is in the box for the player the dialog was opened
        -- for. Reads dialog.playerKey at click time so one frame serves all rows.
        local function CommitMainSpecEdit()
            SafeInvoke("ms-edit-save", function()
                local targetKey = dialog.playerKey
                if not targetKey or targetKey == "" then
                    return
                end

                local value = Trim(dialog.editBox:GetText() or "")
                if value == "" then
                    if addon:RemoveMainSpecRecord(targetKey) then
                        Print("MS cleared for " .. tostring(dialog.playerLabel or targetKey))
                    end
                else
                    local record = addon:RecordMainSpecChange(
                        dialog.playerLabel or targetKey, value, "manual", dialog.playerRealm)
                    if record then
                        Print("MS set: " .. tostring(record.name) .. " = " .. tostring(record.spec))
                    else
                        Print("MS: '" .. tostring(value) .. "' is not a usable spec (no links, must start with a letter)")
                        return
                    end
                end

                dialog.editBox:ClearFocus()
                dialog:Hide()
                addon:RefreshMainWindow()
            end)
        end

        saveButton:SetScript("OnClick", CommitMainSpecEdit)
        editBox:SetScript("OnEnterPressed", CommitMainSpecEdit)

        addon.ui.msEditDialog = dialog
    end

    local record = addon:GetMainSpecRecord(key)
    dialog.playerKey = key
    -- Prefer the name/realm already stored on the record so a manual edit
    -- re-keys to exactly the same entry the chat hook created.
    dialog.playerLabel = (record and record.name) or name
    dialog.playerRealm = (record and record.realm) or parsedRealm
    dialog.title:SetText("Set MS - " .. SafeText(dialog.playerLabel))

    dialog.editBox:SetText(record and tostring(record.spec) or "")
    dialog:Show()
    dialog.editBox:SetFocus()
    dialog.editBox:HighlightText()
end

-- Resolves the copyable value + dialog label for a player overview row.
function addon:GetOverviewRowCopyValue(row)
    if not row then
        return nil
    end

    local name = row.playerName
    if name and name ~= "" then
        return name, "Player name"
    end

    -- Fall back to the row key ("name-realm"); recover the name portion.
    local key = row.key
    if type(key) == "string" and key ~= "" then
        local dash = string.find(key, "-", 1, true)
        local fromKey = dash and string.sub(key, 1, dash - 1) or key
        if fromKey ~= "" then
            return fromKey, "Player name"
        end
    end

    return nil
end

-- Resolves the best-known item name for a gear detail row (cached scan name
-- first, falling back to a live GetItemInfo lookup from the rebuilt link).
local function GetDetailRowItemName(row)
    if not row or type(row.data) ~= "table" then
        return nil
    end

    local item = row.data.item
    if type(item) ~= "table" then
        return nil
    end

    if item.name and item.name ~= "" then
        return item.name
    end

    local linkBody = BuildInspectItemHyperlink(item)
    if linkBody then
        local itemName = GetItemInfo(linkBody)
        if itemName and itemName ~= "" then
            return itemName
        end
    end

    return nil
end

-- Opens the given gear detail row's item inside AtlasLoot (search view).
-- Returns true on success; false if AtlasLoot or the item name is unavailable
-- so the caller can fall back to the copy dialog.
function addon:OpenItemInAtlasLoot(row)
    local itemName = GetDetailRowItemName(row)
    if not itemName then
        return false
    end

    if type(AtlasLoot) ~= "table"
        or type(AtlasLoot.Search) ~= "function"
        or type(AtlasLoot.ShowSearchResult) ~= "function" then
        Print("atlasloot: AtlasLoot not detected (copying item name instead)")
        return false
    end

    if AtlasLootDefaultFrame and AtlasLootDefaultFrame.Show then
        AtlasLootDefaultFrame:Show()
    end

    AtlasLoot:Search(itemName)
    AtlasLoot:ShowSearchResult()
    Print("atlasloot: searching for '" .. itemName .. "'")
    return true
end

-- Resolves the copyable value + dialog label for a gear/item detail row.
function addon:GetDetailRowCopyValue(row)
    if not row or type(row.data) ~= "table" then
        return nil
    end

    local data = row.data
    local item = data.item

    if type(item) == "table" then
        if item.name and item.name ~= "" then
            return item.name, "Item name"
        end

        local linkBody = BuildInspectItemHyperlink(item)
        if linkBody then
            local itemName = GetItemInfo(linkBody)
            if itemName and itemName ~= "" then
                return itemName, "Item name"
            end
            return linkBody, "Item link"
        end
    end

    return nil
end

function addon:RefreshOptionsDialog()
    local dialog = addon.ui and addon.ui.optionsDialog
    if not dialog then
        return
    end

    if dialog.scaleSlider then
        local scale = addon:GetWindowScale()
        dialog.scaleSlider:SetValue(scale)
        local valueText = _G["RaidInspectorScaleSliderText"]
        if valueText then
            valueText:SetText("Scale: " .. tostring(scale))
        end
    end

    local binds = addon:GetKeybinds()
    if dialog.keyButtons then
        local i
        for i = 1, #KEYBIND_ACTIONS do
            local def = KEYBIND_ACTIONS[i]
            local btn = dialog.keyButtons[def.key]
            if btn then
                if dialog.capturingAction == def.key then
                    btn:SetText("Press a key... (Esc)")
                else
                    local key = binds[def.key]
                    if type(key) == "string" and key ~= "" then
                        btn:SetText(key)
                    else
                        btn:SetText("Set")
                    end
                end
            end
        end
    end
end

function addon:HandleKeybindKey(key)
    local dialog = addon.ui and addon.ui.optionsDialog
    if not dialog or not dialog.capturingAction then
        return
    end

    -- Ignore lone modifier keys; wait for the actual key.
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
        or key == "LALT" or key == "RALT" or key == "UNKNOWN" then
        return
    end

    dialog:EnableKeyboard(false)
    dialog:SetScript("OnKeyDown", nil)

    local action = dialog.capturingAction
    dialog.capturingAction = nil

    if key ~= "ESCAPE" then
        local combo = ""
        if IsShiftKeyDown() then
            combo = combo .. "SHIFT-"
        end
        if IsControlKeyDown() then
            combo = combo .. "CTRL-"
        end
        if IsAltKeyDown() then
            combo = combo .. "ALT-"
        end
        combo = combo .. key
        addon:SetKeybind(action, combo)
    end

    addon:RefreshOptionsDialog()
end

function addon:BeginKeybindCapture(actionKey)
    local dialog = addon.ui and addon.ui.optionsDialog
    if not dialog then
        return
    end
    dialog.capturingAction = actionKey
    dialog:EnableKeyboard(true)
    dialog:SetScript("OnKeyDown", function(_, key)
        SafeInvoke("keybind-capture", function()
            addon:HandleKeybindKey(key)
        end)
    end)
    addon:RefreshOptionsDialog()
end

function addon:RefreshImportDialog()
    local dialog = addon.ui and addon.ui.importDialog
    if not dialog then
        return
    end

    local list = addon.lfmPendingImports or {}
    local visible = math.min(#list, MAX_VISIBLE_IMPORT_ROWS)
    local i
    for i = 1, MAX_VISIBLE_IMPORT_ROWS do
        local row = dialog.rows[i]
        if not row then
            break
        end
        local entry = (i <= visible) and list[i] or nil
        if entry then
            row.entry = entry
            row.acceptButton.entry = entry
            row.declineButton.entry = entry
            local labelText = tostring(entry.preset and entry.preset.name or "?")
                .. "   (from " .. tostring(entry.from) .. ")"
            SetTruncatedText(row.label, labelText, 284)
            row:Show()
        else
            row.entry = nil
            row.acceptButton.entry = nil
            row.declineButton.entry = nil
            row:Hide()
        end
    end

    if dialog.moreText then
        if #list > MAX_VISIBLE_IMPORT_ROWS then
            dialog.moreText:SetText("... and " .. tostring(#list - MAX_VISIBLE_IMPORT_ROWS) .. " more")
            dialog.moreText:Show()
        else
            dialog.moreText:Hide()
        end
    end

    if dialog.emptyText then
        if #list == 0 then
            dialog.emptyText:Show()
        else
            dialog.emptyText:Hide()
        end
    end
end

-- Lists every received LFM preset so each can be individually accepted/declined.
function addon:ShowImportDialog()
    addon.ui = addon.ui or {}
    local dialog = addon.ui.importDialog

    if not dialog then
        dialog = CreateFrame("Frame", "RaidInspectorImportDialog", UIParent)
        dialog:SetWidth(480)
        dialog:SetHeight(470)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetToplevel(true)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        dialog:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        if dialog.SetBackdropColor then
            dialog:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
        end
        if dialog.SetBackdropBorderColor then
            dialog:SetBackdropBorderColor(0.85, 0.72, 0.18, 1)
        end

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -14)
        title:SetText("Raid Inspector - Pending Imports")

        local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -38)
        hint:SetText("Accept or decline each received LFM preset.")

        local emptyText = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        emptyText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -70)
        emptyText:SetText("No pending imports.")
        emptyText:Hide()
        dialog.emptyText = emptyText

        dialog.rows = {}
        local i
        for i = 1, MAX_VISIBLE_IMPORT_ROWS do
            local row = CreateFrame("Frame", nil, dialog)
            row:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -58 - ((i - 1) * 28))
            row:SetWidth(444)
            row:SetHeight(26)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", row, "LEFT", 0, 0)
            label:SetWidth(290)
            label:SetJustifyH("LEFT")
            if label.SetWordWrap then
                label:SetWordWrap(false)
            end
            row.label = label

            local acceptButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            acceptButton:SetWidth(70)
            acceptButton:SetHeight(22)
            acceptButton:SetPoint("LEFT", label, "RIGHT", 8, 0)
            acceptButton:SetText("|cff66ff66Accept|r")
            acceptButton:SetScript("OnClick", function(self)
                SafeInvoke("import-accept", function()
                    addon:AcceptImportEntry(self.entry)
                end)
            end)
            row.acceptButton = acceptButton

            local declineButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            declineButton:SetWidth(70)
            declineButton:SetHeight(22)
            declineButton:SetPoint("LEFT", acceptButton, "RIGHT", 6, 0)
            declineButton:SetText("|cffff7777Decline|r")
            declineButton:SetScript("OnClick", function(self)
                SafeInvoke("import-decline", function()
                    addon:DeclineImportEntry(self.entry)
                end)
            end)
            row.declineButton = declineButton

            row:Hide()
            dialog.rows[i] = row
        end

        local moreText = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        moreText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -58 - (MAX_VISIBLE_IMPORT_ROWS * 28) - 2)
        moreText:Hide()
        dialog.moreText = moreText

        local acceptAllButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        acceptAllButton:SetWidth(100)
        acceptAllButton:SetHeight(22)
        acceptAllButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 16, 14)
        acceptAllButton:SetText("Accept All")
        acceptAllButton:SetScript("OnClick", function()
            SafeInvoke("import-accept-all", function()
                addon:AcceptAllImports()
            end)
        end)

        local declineAllButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        declineAllButton:SetWidth(100)
        declineAllButton:SetHeight(22)
        declineAllButton:SetPoint("LEFT", acceptAllButton, "RIGHT", 6, 0)
        declineAllButton:SetText("Decline All")
        declineAllButton:SetScript("OnClick", function()
            SafeInvoke("import-decline-all", function()
                addon:DeclineAllImports()
            end)
        end)

        local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        closeButton:SetWidth(90)
        closeButton:SetHeight(22)
        closeButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 14)
        closeButton:SetText("Close")
        closeButton:SetScript("OnClick", function()
            dialog:Hide()
        end)

        addon.ui.importDialog = dialog
    end

    addon:RefreshImportDialog()
    dialog:Show()
    if dialog.Raise then
        dialog:Raise()
    end
end

-- Options: window scale slider + PallyPower-style keybinds for the action buttons.
function addon:ShowOptionsDialog()
    addon.ui = addon.ui or {}
    local dialog = addon.ui.optionsDialog

    if not dialog then
        dialog = CreateFrame("Frame", "RaidInspectorOptionsDialog", UIParent)
        dialog:SetWidth(440)
        dialog:SetHeight(360)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetToplevel(true)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        dialog:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        if dialog.SetBackdropColor then
            dialog:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
        end
        if dialog.SetBackdropBorderColor then
            dialog:SetBackdropBorderColor(0.85, 0.72, 0.18, 1)
        end

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -14)
        title:SetText("Raid Inspector - Options")

        local scaleLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        scaleLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -46)
        scaleLabel:SetText("Window Scale")

        local slider = CreateFrame("Slider", "RaidInspectorScaleSlider", dialog, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 8, -22)
        slider:SetWidth(370)
        slider:SetMinMaxValues(MIN_WINDOW_SCALE, MAX_WINDOW_SCALE)
        slider:SetValueStep(0.05)
        if _G["RaidInspectorScaleSliderLow"] then
            _G["RaidInspectorScaleSliderLow"]:SetText(tostring(MIN_WINDOW_SCALE))
        end
        if _G["RaidInspectorScaleSliderHigh"] then
            _G["RaidInspectorScaleSliderHigh"]:SetText(tostring(MAX_WINDOW_SCALE))
        end
        slider:SetScript("OnValueChanged", function(_, value)
            local rounded = math.floor((value * 20) + 0.5) / 20
            addon:SetWindowScale(rounded)
            local valueText = _G["RaidInspectorScaleSliderText"]
            if valueText then
                valueText:SetText("Scale: " .. tostring(rounded))
            end
        end)
        dialog.scaleSlider = slider

        local keyHeader = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        keyHeader:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -8, -26)
        keyHeader:SetText("|cffffd100Keybinds|r  (click Set, then press a key; Esc cancels)")

        dialog.keyButtons = {}
        local i
        for i = 1, #KEYBIND_ACTIONS do
            local def = KEYBIND_ACTIONS[i]
            local rowY = -14 - ((i - 1) * 28)

            local rowLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            rowLabel:SetPoint("TOPLEFT", keyHeader, "BOTTOMLEFT", 6, rowY)
            rowLabel:SetWidth(90)
            rowLabel:SetJustifyH("LEFT")
            rowLabel:SetText(def.label)

            local keyButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
            keyButton:SetPoint("TOPLEFT", keyHeader, "BOTTOMLEFT", 104, rowY + 2)
            keyButton:SetWidth(230)
            keyButton:SetHeight(22)
            keyButton:SetText("Set")
            keyButton.actionKey = def.key
            keyButton:SetScript("OnClick", function(self)
                SafeInvoke("keybind-set", function()
                    addon:BeginKeybindCapture(self.actionKey)
                end)
            end)
            dialog.keyButtons[def.key] = keyButton

            local clearButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
            clearButton:SetPoint("LEFT", keyButton, "RIGHT", 6, 0)
            clearButton:SetWidth(24)
            clearButton:SetHeight(22)
            clearButton:SetText("X")
            clearButton.actionKey = def.key
            clearButton:SetScript("OnClick", function(self)
                SafeInvoke("keybind-clear", function()
                    addon:ClearKeybind(self.actionKey)
                    addon:RefreshOptionsDialog()
                end)
            end)
        end

        local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        closeButton:SetWidth(90)
        closeButton:SetHeight(22)
        closeButton:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 14)
        closeButton:SetText("Close")
        closeButton:SetScript("OnClick", function()
            dialog.capturingAction = nil
            dialog:EnableKeyboard(false)
            dialog:SetScript("OnKeyDown", nil)
            dialog:Hide()
        end)

        addon.ui.optionsDialog = dialog
    end

    dialog.capturingAction = nil
    dialog:EnableKeyboard(false)
    dialog:SetScript("OnKeyDown", nil)
    addon:RefreshOptionsDialog()
    dialog:Show()
    if dialog.Raise then
        dialog:Raise()
    end
end

-- Movable help dialog that explains what the buttons / mouse actions do.
function addon:ShowInfoDialog()
    addon.ui = addon.ui or {}
    local dialog = addon.ui.infoDialog

    if not dialog then
        dialog = CreateFrame("Frame", "RaidInspectorInfoDialog", UIParent)
        dialog:SetWidth(560)
        dialog:SetHeight(600)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetToplevel(true)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        dialog:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        if dialog.SetBackdropColor then
            dialog:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
        end
        if dialog.SetBackdropBorderColor then
            dialog:SetBackdropBorderColor(0.85, 0.72, 0.18, 1)
        end

        local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -14)
        title:SetText("Raid Inspector - Help")

        local body = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", dialog, "TOPLEFT", 18, -44)
        body:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -18, -44)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetText(table.concat({
            "|cffffd100Tabs|r",
            "Inspector - raid gear/enchant overview + selected player details.",
            "LFM - compose and post a \"looking for more\" message.",
            " ",
            "|cffffd100Inspector buttons|r",
            "S:<mode> - click to cycle the list sort (recent / gs / issues / name / MS changes).",
            "Target - inspect your current target and add them to the list.",
            "Raid - inspect everyone in your party/raid.",
            "Autoscan - toggle. While on, the raid is rescanned automatically:",
            "  once whenever someone joins or leaves, and every 10s after the queue",
            "  finishes. Anyone who leaves the raid is dropped from the list, so the",
            "  list always matches the raid. Click again (or /ri autoscan off) to stop.",
            "Share - send a short summary of the selected player to the ticked Share channels.",
            "Save All - save a full report of the current overview into the addon.",
            "Clear - clear the queue, results and recorded MS changes (asks to confirm).",
            "MS: on/off - toggle MS registering. While on, raid/party lines like",
            "  \"MS resto\" are recorded against whoever typed them, and the row shows",
            "  MS:<spec> in place of Scanned=<age>. Records survive rescans and relogs;",
            "  Clear or MS Clear wipes them.",
            "MS Share - post the whole recorded MS list to the ticked Share channels.",
            "MS Clear - wipe the recorded MS changes only, keeping the scan list.",
            "RW - a Share channel for Raid Warning (needs leader/assistant).",
            " ",
            "|cffffd100Out of range|r",
            "Players too far away show \"not inspectable\" and are retried automatically",
            "every 15s until they come into range and get inspected.",
            " ",
            "|cffffd100Share / Reports|r",
            "Share checkboxes (Raid / Say / Whisper / Guild / RW) choose where Share sends.",
            "Reports dropdown - view the live overview or a previously saved report.",
            "Item List dropdown - filter which gear slots are listed.",
            " ",
            "|cffffd100Mouse|r",
            "Left-click a player row - select that player.",
            "Right-click a player row - set/edit that player's MS (empty box clears it).",
            "Shift+right-click a player row - copy their name.",
            "Right-click a gear row - open the item in AtlasLoot.",
            "Shift+right-click a gear row - copy the item value.",
            " ",
            "|cffffd100LFM tab|r",
            "Pick channels, set Delay (s) and Repeat, fill the Need table",
            "(Tank/Healer/Melee/Ranged with a count + classes), then press POST.",
            "Cancel stops any pending posts.",
            "Presets: Save Template stores the message + Need table; pick it from the",
            "dropdown to reload it. Export sends it to another player (they Import to accept).",
            " ",
            "|cffffd100Options button|r",
            "Window scale slider + keybinds for Target / Raid / Share / Save All / Clear.",
            " ",
            "|cffffd100Chat commands|r",
            "/ri - open this window.   /ri help - list every command.",
        }, "\n"))

        local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        closeButton:SetWidth(90)
        closeButton:SetHeight(22)
        closeButton:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 14)
        closeButton:SetText("Close")
        closeButton:SetScript("OnClick", function()
            dialog:Hide()
        end)

        addon.ui.infoDialog = dialog
    end

    dialog:Show()
    if dialog.Raise then
        dialog:Raise()
    end
end

function addon:CreateMainWindow()
    if addon.ui and addon.ui.frame then
        return
    end

    addon.ui = addon.ui or {}

    local f = CreateFrame("Frame", "RaidInspectorMainFrame", UIParent)
    f:SetWidth(WINDOW_WIDTH)
    f:SetHeight(WINDOW_HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(120)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    if f.SetBackdropColor then
        f:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
    end
    if f.SetBackdropBorderColor then
        f:SetBackdropBorderColor(0.85, 0.72, 0.18, 1)
    end
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        local point, _, _, x, y = self:GetPoint(1)
        self:StopMovingOrSizing()
        RaidInspectorDB.settings.window.point = point or "CENTER"
        RaidInspectorDB.settings.window.x = math.floor(x or 0)
        RaidInspectorDB.settings.window.y = math.floor(y or 0)
    end)

    f:SetPoint(
        RaidInspectorDB.settings.window.point,
        UIParent,
        RaidInspectorDB.settings.window.point,
        RaidInspectorDB.settings.window.x,
        RaidInspectorDB.settings.window.y
    )
    f:SetScale(addon:GetWindowScale())

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    title:SetText("Raid Inspector")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Raid overview + selected player details")

    local inspectorTabButton = CreateFrame("Button", "RaidInspectorInspectorTabButton", f, "UIPanelButtonTemplate")
    inspectorTabButton:SetWidth(86)
    inspectorTabButton:SetHeight(20)
    inspectorTabButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
    inspectorTabButton:SetText("|cff66ff66Inspector|r")
    inspectorTabButton:SetScript("OnClick", function()
        SafeInvoke("tab-inspector", function()
            addon:SetActiveTab("inspector")
            addon:RefreshMainWindow()
        end)
    end)

    local lfmTabButton = CreateFrame("Button", "RaidInspectorLFMTabButton", f, "UIPanelButtonTemplate")
    lfmTabButton:SetWidth(86)
    lfmTabButton:SetHeight(20)
    lfmTabButton:SetPoint("LEFT", inspectorTabButton, "RIGHT", 6, 0)
    lfmTabButton:SetText("|cffbbbbbbLFM|r")
    lfmTabButton:SetScript("OnClick", function()
        SafeInvoke("tab-lfm", function()
            addon:SetActiveTab("lfm")
            addon:RefreshMainWindow()
        end)
    end)

    local infoButton = CreateFrame("Button", "RaidInspectorInfoButton", f, "UIPanelButtonTemplate")
    infoButton:SetWidth(80)
    infoButton:SetHeight(20)
    infoButton:SetPoint("LEFT", lfmTabButton, "RIGHT", 12, 0)
    infoButton:SetText("|cffffd100? Info|r")
    infoButton:SetScript("OnClick", function()
        SafeInvoke("info", function()
            addon:ShowInfoDialog()
        end)
    end)

    local optionsButton = CreateFrame("Button", "RaidInspectorOptionsButton", f, "UIPanelButtonTemplate")
    optionsButton:SetWidth(80)
    optionsButton:SetHeight(20)
    optionsButton:SetPoint("LEFT", infoButton, "RIGHT", 6, 0)
    optionsButton:SetText("|cffffd100Options|r")
    optionsButton:SetScript("OnClick", function()
        SafeInvoke("options", function()
            addon:ShowOptionsDialog()
        end)
    end)

    local closeButton = CreateFrame("Button", "RaidInspectorCloseButton", f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", inspectorTabButton, "BOTTOMLEFT", 0, -4)
    statusText:SetJustifyH("LEFT")
    statusText:SetWidth(WINDOW_WIDTH - (PANEL_SIDE_MARGIN * 2))
    -- Fixed (small) height keeps the rows below stable whether this line is blank
    -- (live overview) or shows saved-report / LFM text, while keeping the gap tight.
    statusText:SetHeight(14)
    statusText:SetText("")

    local function SetActionButtonLabel(button, colorCode, plainText)
        button:SetText("|c" .. colorCode .. plainText .. "|r")
    end

    local function ActivateActionButton(button)
        button:EnableMouse(true)
        local parent = button.GetParent and button:GetParent() or nil
        local parentStrata = parent and parent:GetFrameStrata() or "DIALOG"
        local parentLevel = parent and parent:GetFrameLevel() or 0
        button:SetFrameStrata(parentStrata)
        button:SetFrameLevel(parentLevel + 20)
    end

    local shareChannelsRow = CreateFrame("Frame", nil, f)
    shareChannelsRow:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -4)
    shareChannelsRow:SetWidth(420)
    shareChannelsRow:SetHeight(20)

    local shareChannelsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shareChannelsLabel:SetPoint("LEFT", shareChannelsRow, "LEFT", 0, 0)
    shareChannelsLabel:SetText("Share:")

    local raidShareCheck = CreateFrame("CheckButton", "RaidInspectorShareRaidCheck", f, "UICheckButtonTemplate")
    raidShareCheck:SetPoint("LEFT", shareChannelsLabel, "RIGHT", 6, 0)
    raidShareCheck:SetHitRectInsets(0, -24, 0, 0)
    _G[raidShareCheck:GetName() .. "Text"]:SetText("Raid")
    raidShareCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("raid", self:GetChecked() and true or false)
    end)

    local sayShareCheck = CreateFrame("CheckButton", "RaidInspectorShareSayCheck", f, "UICheckButtonTemplate")
    sayShareCheck:SetPoint("LEFT", raidShareCheck, "RIGHT", 44, 0)
    sayShareCheck:SetHitRectInsets(0, -24, 0, 0)
    _G[sayShareCheck:GetName() .. "Text"]:SetText("Say")
    sayShareCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("say", self:GetChecked() and true or false)
    end)

    local whisperShareCheck = CreateFrame("CheckButton", "RaidInspectorShareWhisperCheck", f, "UICheckButtonTemplate")
    whisperShareCheck:SetPoint("LEFT", sayShareCheck, "RIGHT", 44, 0)
    whisperShareCheck:SetHitRectInsets(0, -38, 0, 0)
    _G[whisperShareCheck:GetName() .. "Text"]:SetText("Whisper")
    whisperShareCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("whisper", self:GetChecked() and true or false)
    end)

    local guildShareCheck = CreateFrame("CheckButton", "RaidInspectorShareGuildCheck", f, "UICheckButtonTemplate")
    guildShareCheck:SetPoint("LEFT", whisperShareCheck, "RIGHT", 58, 0)
    guildShareCheck:SetHitRectInsets(0, -30, 0, 0)
    _G[guildShareCheck:GetName() .. "Text"]:SetText("Guild")
    guildShareCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("guild", self:GetChecked() and true or false)
    end)

    local rwShareCheck = CreateFrame("CheckButton", "RaidInspectorShareRWCheck", f, "UICheckButtonTemplate")
    rwShareCheck:SetPoint("LEFT", guildShareCheck, "RIGHT", 48, 0)
    rwShareCheck:SetHitRectInsets(0, -22, 0, 0)
    _G[rwShareCheck:GetName() .. "Text"]:SetText("RW")
    rwShareCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("rw", self:GetChecked() and true or false)
    end)
    rwShareCheck:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Raid Warning")
            GameTooltip:AddLine("Needs raid leader or assistant.", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    rwShareCheck:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local savedReportsRow = CreateFrame("Frame", nil, f)
    savedReportsRow:SetPoint("TOPLEFT", shareChannelsRow, "BOTTOMLEFT", 0, -8)
    savedReportsRow:SetWidth(340)
    savedReportsRow:SetHeight(20)

    local savedReportsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    savedReportsLabel:SetPoint("LEFT", savedReportsRow, "LEFT", 0, 0)
    savedReportsLabel:SetText("Reports:")

    local savedReportDropDown = CreateFrame("Frame", "RaidInspectorSavedReportDropDown", f, "UIDropDownMenuTemplate")
    savedReportDropDown:SetPoint("TOPLEFT", savedReportsLabel, "TOPLEFT", 46, 10)
    UIDropDownMenu_SetWidth(savedReportDropDown, 250)
    UIDropDownMenu_JustifyText(savedReportDropDown, "LEFT")
    UIDropDownMenu_Initialize(savedReportDropDown, function(_, level)
        if level ~= 1 then
            return
        end

        local liveInfo = UIDropDownMenu_CreateInfo()
        liveInfo.text = "Live Overview"
        liveInfo.value = ""
        liveInfo.checked = (addon:GetSelectedSavedReportFile() == "")
        liveInfo.func = function()
            addon:SetSelectedSavedReportFile("")
            UIDropDownMenu_SetSelectedValue(savedReportDropDown, "")
            UIDropDownMenu_SetText(savedReportDropDown, "Live Overview")
        end
        UIDropDownMenu_AddButton(liveInfo, level)

        local savedReports = addon:GetSavedReportFiles()
        if #savedReports.items == 0 then
            local emptyInfo = UIDropDownMenu_CreateInfo()
            emptyInfo.text = "No saved reports"
            emptyInfo.disabled = true
            UIDropDownMenu_AddButton(emptyInfo, level)
            return
        end

        local i
        for i = 1, #savedReports.items do
            local item = savedReports.items[i]
            local fileName = tostring(item.fileName or "")
            local info = UIDropDownMenu_CreateInfo()
            info.text = addon:BuildSavedReportMenuLabel(item)
            info.value = fileName
            info.checked = (addon:GetSelectedSavedReportFile() == fileName)
            info.func = function(btn)
                local selectedFile = tostring(btn.value or "")
                addon:SetSelectedSavedReportFile(selectedFile)
                UIDropDownMenu_SetSelectedValue(savedReportDropDown, selectedFile)
                UIDropDownMenu_SetText(savedReportDropDown, addon:BuildSavedReportMenuLabel(item))
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(savedReportDropDown, "")
    UIDropDownMenu_SetText(savedReportDropDown, "Live Overview")

    local sortRow = CreateFrame("Frame", nil, f)
    sortRow:SetPoint("TOPLEFT", savedReportsRow, "BOTTOMLEFT", 0, -6)
    sortRow:SetWidth(300)
    sortRow:SetHeight(20)

    local sortLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sortLabel:SetPoint("LEFT", sortRow, "LEFT", 0, 0)
    sortLabel:SetText("Sort:")

    local sortDropDown = CreateFrame("Frame", "RaidInspectorSortDropDown", f, "UIDropDownMenuTemplate")
    sortDropDown:SetPoint("LEFT", sortLabel, "RIGHT", -6, 2)
    UIDropDownMenu_SetWidth(sortDropDown, 120)
    UIDropDownMenu_JustifyText(sortDropDown, "LEFT")
    UIDropDownMenu_Initialize(sortDropDown, function(_, level)
        if level ~= 1 then
            return
        end

        local i
        for i = 1, #SORT_MODES do
            local mode = SORT_MODES[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = SORT_LABELS[mode] or mode
            info.value = mode
            info.checked = (addon:GetSortMode() == mode)
            info.func = function(btn)
                addon:SetSortMode(btn.value)
                UIDropDownMenu_SetSelectedValue(sortDropDown, btn.value)
                UIDropDownMenu_SetText(sortDropDown, SORT_LABELS[btn.value] or btn.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(sortDropDown, addon:GetSortMode())
    UIDropDownMenu_SetText(sortDropDown, SORT_LABELS[addon:GetSortMode()] or addon:GetSortMode())

    local actionPanel = CreateFrame("Frame", nil, f)
    actionPanel:SetPoint("TOPLEFT", sortRow, "BOTTOMLEFT", 0, -6)
    actionPanel:SetWidth(318)
    actionPanel:SetHeight(98)

    local sortButton = CreateFrame("Button", "RaidInspectorSortButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(sortButton)
    sortButton:SetWidth(100)
    sortButton:SetHeight(20)
    sortButton:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 0, 0)
    SetActionButtonLabel(sortButton, "ff66ff66", "S:recent")
    sortButton:SetScript("OnClick", function()
        SafeInvoke("sort", function()
            addon:CycleSortMode()
        end)
    end)

    local filterButton = CreateFrame("Button", "RaidInspectorFilterButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(filterButton)
    filterButton:SetWidth(100)
    filterButton:SetHeight(20)
    filterButton:SetPoint("LEFT", sortButton, "RIGHT", 6, 0)
    SetActionButtonLabel(filterButton, "ff66ff66", "F:all")
    filterButton:SetScript("OnClick", function()
        SafeInvoke("filter", function()
            addon:CycleFilterMode()
        end)
    end)

    local targetButton = CreateFrame("Button", "RaidInspectorTargetButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(targetButton)
    targetButton:SetWidth(100)
    targetButton:SetHeight(20)
    targetButton:SetPoint("TOPLEFT", sortButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(targetButton, "ff66ff66", "Target")
    targetButton:SetScript("OnClick", function()
        SafeInvoke("target", function()
            addon:QueueTarget()
        end)
    end)

    local raidButton = CreateFrame("Button", "RaidInspectorRaidButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(raidButton)
    raidButton:SetWidth(100)
    raidButton:SetHeight(20)
    raidButton:SetPoint("LEFT", targetButton, "RIGHT", 6, 0)
    SetActionButtonLabel(raidButton, "ff66ff66", "Raid")
    raidButton:SetScript("OnClick", function()
        SafeInvoke("raid", function()
            addon:QueueRaidSnapshot()
        end)
    end)

    local autoScanButton = CreateFrame("Button", "RaidInspectorAutoScanButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(autoScanButton)
    autoScanButton:SetWidth(100)
    autoScanButton:SetHeight(20)
    autoScanButton:SetPoint("LEFT", raidButton, "RIGHT", 6, 0)
    SetActionButtonLabel(autoScanButton, "ff66ff66", "Autoscan: off")
    autoScanButton:SetScript("OnClick", function()
        SafeInvoke("autoscan", function()
            addon:ToggleAutoScan()
        end)
    end)

    local syncButton = CreateFrame("Button", "RaidInspectorSyncButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(syncButton)
    syncButton:SetWidth(100)
    syncButton:SetHeight(20)
    syncButton:SetPoint("TOPLEFT", targetButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(syncButton, "ff66ff66", "Share")
    syncButton:SetScript("OnClick", function()
        SafeInvoke("share", function()
            addon:ExportSummary("")
        end)
    end)

    local forceSyncButton = CreateFrame("Button", "RaidInspectorForceSyncButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(forceSyncButton)
    forceSyncButton:SetWidth(100)
    forceSyncButton:SetHeight(20)
    forceSyncButton:SetPoint("LEFT", syncButton, "RIGHT", 6, 0)
    SetActionButtonLabel(forceSyncButton, "ff66ff66", "Save One")
    forceSyncButton:SetScript("OnClick", function()
        SafeInvoke("savereport", function()
            addon:SaveReportSnapshot("")
        end)
    end)

    local reportButton = CreateFrame("Button", "RaidInspectorReportButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(reportButton)
    reportButton:SetWidth(100)
    reportButton:SetHeight(20)
    reportButton:SetPoint("TOPLEFT", syncButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(reportButton, "ff66ff66", "Save All")
    reportButton:SetScript("OnClick", function()
        SafeInvoke("report", function()
            addon:QueueDetailedReport()
        end)
    end)

    local staleButton = CreateFrame("Button", "RaidInspectorStaleButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(staleButton)
    staleButton:SetWidth(100)
    staleButton:SetHeight(20)
    staleButton:SetPoint("LEFT", reportButton, "RIGHT", 6, 0)
    SetActionButtonLabel(staleButton, "ffffaa33", "Refresh")
    staleButton:SetScript("OnClick", function()
        SafeInvoke("stale", function()
            addon:QueueStaleRefresh("15")
        end)
    end)

    local statusButton = CreateFrame("Button", "RaidInspectorStatusButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(statusButton)
    statusButton:SetWidth(100)
    statusButton:SetHeight(20)
    statusButton:SetPoint("TOPLEFT", reportButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(statusButton, "ffffaa33", "Status")
    statusButton:SetScript("OnClick", function()
        SafeInvoke("status", function()
            addon:PrintStatus()
            addon:RefreshMainWindow()
        end)
    end)

    local clearButton = CreateFrame("Button", "RaidInspectorClearButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(clearButton)
    clearButton:SetWidth(100)
    clearButton:SetHeight(20)
    clearButton:SetPoint("LEFT", statusButton, "RIGHT", 6, 0)
    SetActionButtonLabel(clearButton, "ffffaa33", "Clear")
    clearButton:SetScript("OnClick", function()
        SafeInvoke("clear", function()
            addon:RequestClearQueue()
        end)
    end)

    local msButton = CreateFrame("Button", "RaidInspectorMSButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(msButton)
    msButton:SetWidth(100)
    msButton:SetHeight(20)
    msButton:SetPoint("TOPLEFT", statusButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(msButton, "ff999999", "MS: off")
    msButton:SetScript("OnClick", function()
        SafeInvoke("ms-toggle", function()
            addon:ToggleMSTracking()
        end)
    end)
    msButton:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("MS registering")
            GameTooltip:AddLine("While on, raid/party lines like \"MS resto\"", 1, 1, 1)
            GameTooltip:AddLine("are recorded against that player.", 1, 1, 1)
            GameTooltip:AddLine("Right-click a row to edit an MS by hand.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    msButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local msShareButton = CreateFrame("Button", "RaidInspectorMSShareButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(msShareButton)
    msShareButton:SetWidth(100)
    msShareButton:SetHeight(20)
    msShareButton:SetPoint("LEFT", msButton, "RIGHT", 6, 0)
    SetActionButtonLabel(msShareButton, "ff66ff66", "MS Share")
    msShareButton:SetScript("OnClick", function()
        SafeInvoke("ms-share", function()
            addon:ShareMainSpecChanges()
        end)
    end)
    msShareButton:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Share MS changes")
            GameTooltip:AddLine("Posts every recorded MS to the ticked", 1, 1, 1)
            GameTooltip:AddLine("Share channels (Raid/Say/Whisper/Guild/RW).", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    msShareButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local msClearButton = CreateFrame("Button", "RaidInspectorMSClearButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(msClearButton)
    msClearButton:SetWidth(100)
    msClearButton:SetHeight(20)
    msClearButton:SetPoint("LEFT", msShareButton, "RIGHT", 6, 0)
    SetActionButtonLabel(msClearButton, "ffffaa33", "MS Clear")
    msClearButton:SetScript("OnClick", function()
        SafeInvoke("ms-clear", function()
            addon:RequestClearMainSpecRecords()
        end)
    end)
    msClearButton:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Clear MS list")
            GameTooltip:AddLine("Wipes every recorded MS (asks to confirm).", 1, 1, 1)
            GameTooltip:AddLine("Keeps the scan list, unlike the Clear button.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    msClearButton:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    local rowsViewport = CreateFrame("ScrollFrame", nil, f)
    rowsViewport:SetPoint("TOPLEFT", actionPanel, "BOTTOMLEFT", 0, -8)
    rowsViewport:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PANEL_SIDE_MARGIN, OVERVIEW_BOTTOM_INSET)
    rowsViewport:SetWidth(432)
    if rowsViewport.SetClipsChildren then
        rowsViewport:SetClipsChildren(true)
    end

    local overviewAvailableHeight = tonumber(rowsViewport:GetHeight()) or (OVERVIEW_ROW_HEIGHT * OVERVIEW_VISIBLE_ROWS)
    local overviewVisibleRowCount = math.max(1, math.min(OVERVIEW_VISIBLE_ROWS, math.floor(overviewAvailableHeight / OVERVIEW_ROW_HEIGHT)))
    local overviewHeight = overviewVisibleRowCount * OVERVIEW_ROW_HEIGHT

    local rowsContainer = CreateFrame("Frame", nil, rowsViewport)
    rowsContainer:SetPoint("TOPLEFT", rowsViewport, "TOPLEFT", 0, 0)
    rowsContainer:SetWidth(432)
    rowsContainer:SetHeight(overviewHeight)
    rowsViewport:SetScrollChild(rowsContainer)
    addon:BuildOverviewRows(rowsContainer, overviewVisibleRowCount)

    local overviewScroll = CreateFrame("ScrollFrame", "RaidInspectorOverviewScroll", rowsViewport, "FauxScrollFrameTemplate")
    overviewScroll:SetPoint("TOPLEFT", rowsViewport, "TOPRIGHT", 0, -1)
    overviewScroll:SetPoint("BOTTOMLEFT", rowsViewport, "BOTTOMRIGHT", 0, 1)
    overviewScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, OVERVIEW_ROW_HEIGHT, function()
            addon:RefreshMainWindow()
        end)
    end)

    rowsViewport:EnableMouseWheel(true)
    rowsViewport:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, (addon.ui.overviewEntryCount or 0) - #rowsContainer.rows)
        local current = GetFauxScrollOffset(overviewScroll)
        local nextOffset = math.max(0, math.min(maxOffset, current - delta))
        if nextOffset ~= current then
            SetFauxScrollOffset(overviewScroll, nextOffset, OVERVIEW_ROW_HEIGHT)
            addon:RefreshMainWindow()
        end
    end)

    local rightPanelWidth = WINDOW_WIDTH - RIGHT_PANEL_X - PANEL_SIDE_MARGIN

    local compositionHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compositionHeader:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_PANEL_X, -86)
    compositionHeader:SetWidth(rightPanelWidth)
    compositionHeader:SetJustifyH("LEFT")
    compositionHeader:SetText("Raid Composition (Talent):")

    local compositionSummary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    compositionSummary:SetPoint("TOPLEFT", compositionHeader, "BOTTOMLEFT", 0, -6)
    compositionSummary:SetWidth(rightPanelWidth)
    compositionSummary:SetJustifyH("LEFT")
    compositionSummary:SetText("Tanks: 0  |  Heals: 0  |  RDPS: 0  |  MDPS: 0  |  Total: 0")

    local detailHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailHeader:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_PANEL_X, -136)
    detailHeader:SetWidth(rightPanelWidth)
    detailHeader:SetJustifyH("LEFT")
    detailHeader:SetText("Selected: none")

    local detailScore = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailScore:SetPoint("TOPLEFT", detailHeader, "BOTTOMLEFT", 0, -6)
    detailScore:SetWidth(rightPanelWidth)
    detailScore:SetJustifyH("LEFT")
    detailScore:SetText("")

    local detailMeta = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailMeta:SetPoint("TOPLEFT", detailScore, "BOTTOMLEFT", 0, -4)
    detailMeta:SetWidth(rightPanelWidth)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetText("")
    if detailMeta.GetFont and detailMeta.SetFont then
        local fontName, fontHeight = detailMeta:GetFont()
        if fontName and fontHeight then
            detailMeta:SetFont(fontName, fontHeight, "OUTLINE")
        end
    end

    local detailAudit = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailAudit:SetPoint("TOPLEFT", detailMeta, "BOTTOMLEFT", 0, -7)
    detailAudit:SetWidth(rightPanelWidth)
    detailAudit:SetJustifyH("LEFT")
    detailAudit:SetText("")

    local itemFilterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemFilterLabel:SetPoint("TOPLEFT", detailAudit, "BOTTOMLEFT", 0, -10)
    itemFilterLabel:SetWidth(70)
    itemFilterLabel:SetJustifyH("LEFT")
    itemFilterLabel:SetText("Item List:")

    local itemFilterDropDown = CreateFrame("Frame", "RaidInspectorItemListDropDown", f, "UIDropDownMenuTemplate")
    itemFilterDropDown:SetPoint("TOPLEFT", itemFilterLabel, "TOPLEFT", 62, 10)
    UIDropDownMenu_SetWidth(itemFilterDropDown, 170)
    UIDropDownMenu_JustifyText(itemFilterDropDown, "LEFT")
    UIDropDownMenu_Initialize(itemFilterDropDown, function(_, level)
        if level ~= 1 then
            return
        end

        local i
        for i = 1, #ITEM_LIST_FILTER_MODES do
            local mode = ITEM_LIST_FILTER_MODES[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = ITEM_LIST_FILTER_LABELS[mode] or mode
            info.value = mode
            info.checked = (addon:GetItemListFilterMode() == mode)
            info.func = function(btn)
                local selectedMode = btn.value
                addon:SetItemListFilterMode(selectedMode)
                UIDropDownMenu_SetSelectedValue(itemFilterDropDown, selectedMode)
                UIDropDownMenu_SetText(itemFilterDropDown, ITEM_LIST_FILTER_LABELS[selectedMode] or selectedMode)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local selectedItemFilter = addon:GetItemListFilterMode()
    UIDropDownMenu_SetSelectedValue(itemFilterDropDown, selectedItemFilter)
    UIDropDownMenu_SetText(itemFilterDropDown, ITEM_LIST_FILTER_LABELS[selectedItemFilter] or selectedItemFilter)

    -- Column header row for the gear list.
    local detailHeaderRow = CreateFrame("Frame", nil, f)
    detailHeaderRow:SetPoint("TOPLEFT", itemFilterLabel, "BOTTOMLEFT", 0, -8)
    detailHeaderRow:SetWidth(rightPanelWidth)
    detailHeaderRow:SetHeight(16)
    do
        local hc
        for hc = 1, #DETAIL_COLUMNS do
            local col = DETAIL_COLUMNS[hc]
            local headerFS = detailHeaderRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            headerFS:SetPoint("LEFT", detailHeaderRow, "LEFT", col.x, 0)
            headerFS:SetWidth(col.width)
            headerFS:SetJustifyH("LEFT")
            headerFS:SetText(col.header)
        end
    end

    local detailContainer = CreateFrame("Frame", nil, f)
    detailContainer:SetPoint("TOPLEFT", detailHeaderRow, "BOTTOMLEFT", 0, -2)
    detailContainer:SetWidth(rightPanelWidth)
    detailContainer:SetHeight(340)
    if detailContainer.SetClipsChildren then
        detailContainer:SetClipsChildren(true)
    end
    addon:BuildDetailRows(detailContainer, 16)

    local detailScroll = CreateFrame("ScrollFrame", "RaidInspectorDetailScroll", detailContainer, "FauxScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detailContainer, "TOPRIGHT", 0, -1)
    detailScroll:SetPoint("BOTTOMLEFT", detailContainer, "BOTTOMRIGHT", 0, 1)
    detailScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, DETAIL_ROW_HEIGHT, function()
            if addon.ui.lastDetailEntry then
                addon:RefreshDetailPanel(addon.ui.lastDetailEntry)
            end
        end)
    end)

    detailContainer:EnableMouseWheel(true)
    detailContainer:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, (addon.ui.detailLineCount or 0) - #detailContainer.rows)
        local current = GetFauxScrollOffset(detailScroll)
        local nextOffset = math.max(0, math.min(maxOffset, current - delta))
        if nextOffset ~= current then
            SetFauxScrollOffset(detailScroll, nextOffset, DETAIL_ROW_HEIGHT)
            if addon.ui.lastDetailEntry then
                addon:RefreshDetailPanel(addon.ui.lastDetailEntry)
            end
        end
    end)

    local lfmPanel = CreateFrame("Frame", nil, f)
    lfmPanel:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -8)
    lfmPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PANEL_SIDE_MARGIN, OVERVIEW_BOTTOM_INSET)

    local lfmMessageLabel = lfmPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lfmMessageLabel:SetPoint("TOPLEFT", lfmPanel, "TOPLEFT", 0, -2)
    lfmMessageLabel:SetText("LFM Message:")

    local lfmMessageBox = CreateFrame("EditBox", "RaidInspectorLFMMessageBox", lfmPanel, "InputBoxTemplate")
    lfmMessageBox:SetAutoFocus(false)
    lfmMessageBox:SetWidth(720)
    lfmMessageBox:SetHeight(26)
    lfmMessageBox:SetPoint("TOPLEFT", lfmMessageLabel, "BOTTOMLEFT", 0, -6)
    if lfmMessageBox.SetTextInsets then
        lfmMessageBox:SetTextInsets(6, 6, 0, 0)
    end
    lfmMessageBox:SetMaxLetters(255)
    lfmMessageBox:SetScript("OnTextChanged", function(self)
        addon:SetLFMMessage(self:GetText() or "")
    end)
    lfmMessageBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    lfmMessageBox:SetScript("OnEnterPressed", function(self)
        SafeInvoke("lfm-post-enter", function()
            addon:SetLFMMessage(self:GetText() or "")
            addon:CommitLFMInputsFromUI()
            addon:PostLFMMessage()
        end)
    end)

    local lfmMessageClearButton = CreateFrame("Button", "RaidInspectorLFMMessageClearButton", lfmPanel, "UIPanelButtonTemplate")
    lfmMessageClearButton:SetWidth(24)
    lfmMessageClearButton:SetHeight(22)
    lfmMessageClearButton:SetPoint("LEFT", lfmMessageBox, "RIGHT", 10, 0)
    lfmMessageClearButton:SetText("X")
    lfmMessageClearButton:SetScript("OnClick", function()
        SafeInvoke("lfm-message-clear", function()
            lfmMessageBox:SetText("")
            addon:SetLFMMessage("")
        end)
    end)

    local lfmHint = lfmPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lfmHint:SetPoint("TOPLEFT", lfmMessageBox, "BOTTOMLEFT", 2, -6)
    lfmHint:SetWidth(820)
    lfmHint:SetJustifyH("LEFT")
    lfmHint:SetText("Write your post (paste an achievement link if you want), pick channels, set delay/repeat, fill the Need table, then press POST. Use Cancel to stop pending posts.")

    local lfmChannelsLabel = lfmPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lfmChannelsLabel:SetPoint("TOPLEFT", lfmHint, "BOTTOMLEFT", -2, -10)
    lfmChannelsLabel:SetText("Post To:")

    local lfmYellCheck = CreateFrame("CheckButton", "RaidInspectorLFMYellCheck", lfmPanel, "UICheckButtonTemplate")
    lfmYellCheck:SetPoint("TOPLEFT", lfmChannelsLabel, "BOTTOMLEFT", 4, -2)
    lfmYellCheck:SetHitRectInsets(0, -24, 0, 0)
    _G[lfmYellCheck:GetName() .. "Text"]:SetText("Yell")
    lfmYellCheck:SetScript("OnClick", function(self)
        addon:SetLFMChannel("yell", self:GetChecked() and true or false)
    end)

    local lfmGuildCheck = CreateFrame("CheckButton", "RaidInspectorLFMGuildCheck", lfmPanel, "UICheckButtonTemplate")
    lfmGuildCheck:SetPoint("LEFT", lfmYellCheck, "RIGHT", 40, 0)
    lfmGuildCheck:SetHitRectInsets(0, -24, 0, 0)
    _G[lfmGuildCheck:GetName() .. "Text"]:SetText("/guild")
    lfmGuildCheck:SetScript("OnClick", function(self)
        addon:SetLFMChannel("guild", self:GetChecked() and true or false)
    end)

    local lfmGeneralCheck = CreateFrame("CheckButton", "RaidInspectorLFMGeneralCheck", lfmPanel, "UICheckButtonTemplate")
    lfmGeneralCheck:SetPoint("LEFT", lfmGuildCheck, "RIGHT", 54, 0)
    lfmGeneralCheck:SetHitRectInsets(0, -24, 0, 0)
    _G[lfmGeneralCheck:GetName() .. "Text"]:SetText("/general")
    lfmGeneralCheck:SetScript("OnClick", function(self)
        addon:SetLFMChannel("general", self:GetChecked() and true or false)
    end)

    local lfmGlobalCheck = CreateFrame("CheckButton", "RaidInspectorLFMGlobalCheck", lfmPanel, "UICheckButtonTemplate")
    lfmGlobalCheck:SetPoint("LEFT", lfmGeneralCheck, "RIGHT", 64, 0)
    lfmGlobalCheck:SetHitRectInsets(0, -24, 0, 0)
    _G[lfmGlobalCheck:GetName() .. "Text"]:SetText("/global")
    lfmGlobalCheck:SetScript("OnClick", function(self)
        addon:SetLFMChannel("global", self:GetChecked() and true or false)
    end)

    local lfmDelayLabel = lfmPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lfmDelayLabel:SetPoint("TOPLEFT", lfmYellCheck, "BOTTOMLEFT", 0, -12)
    lfmDelayLabel:SetText("Delay (s):")

    local lfmDelayBox = CreateFrame("EditBox", "RaidInspectorLFMDelayBox", lfmPanel, "InputBoxTemplate")
    lfmDelayBox:SetPoint("LEFT", lfmDelayLabel, "RIGHT", 10, 0)
    lfmDelayBox:SetWidth(46)
    lfmDelayBox:SetHeight(20)
    lfmDelayBox:SetAutoFocus(false)
    lfmDelayBox:SetNumeric(true)
    lfmDelayBox:SetMaxLetters(4)
    lfmDelayBox:SetJustifyH("CENTER")
    lfmDelayBox:SetScript("OnTextChanged", function(self)
        addon:SetLFMPostDelaySeconds(self:GetText())
    end)
    lfmDelayBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    lfmDelayBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    lfmDelayBox:SetScript("OnEditFocusLost", function(self)
        self:SetText(tostring(addon:GetLFMPostDelaySeconds()))
    end)

    local lfmRepeatLabel = lfmPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lfmRepeatLabel:SetPoint("LEFT", lfmDelayBox, "RIGHT", 14, 0)
    lfmRepeatLabel:SetText("Repeat:")

    local lfmRepeatBox = CreateFrame("EditBox", "RaidInspectorLFMRepeatBox", lfmPanel, "InputBoxTemplate")
    lfmRepeatBox:SetPoint("LEFT", lfmRepeatLabel, "RIGHT", 10, 0)
    lfmRepeatBox:SetWidth(40)
    lfmRepeatBox:SetHeight(20)
    lfmRepeatBox:SetAutoFocus(false)
    lfmRepeatBox:SetNumeric(true)
    lfmRepeatBox:SetMaxLetters(2)
    lfmRepeatBox:SetJustifyH("CENTER")
    lfmRepeatBox:SetScript("OnTextChanged", function(self)
        addon:SetLFMRepeatCount(self:GetText())
    end)
    lfmRepeatBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    lfmRepeatBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    lfmRepeatBox:SetScript("OnEditFocusLost", function(self)
        self:SetText(tostring(addon:GetLFMRepeatCount()))
    end)

    local lfmPostButton = CreateFrame("Button", "RaidInspectorLFMPostButton", lfmPanel, "UIPanelButtonTemplate")
    lfmPostButton:SetWidth(90)
    lfmPostButton:SetHeight(24)
    lfmPostButton:SetPoint("LEFT", lfmRepeatBox, "RIGHT", 18, -1)
    lfmPostButton:SetText("|cff66ff66POST|r")
    lfmPostButton:SetScript("OnClick", function()
        SafeInvoke("lfm-post", function()
            addon:CommitLFMInputsFromUI()
            addon:PostLFMMessage()
        end)
    end)

    local lfmCancelButton = CreateFrame("Button", "RaidInspectorLFMCancelButton", lfmPanel, "UIPanelButtonTemplate")
    lfmCancelButton:SetWidth(80)
    lfmCancelButton:SetHeight(24)
    lfmCancelButton:SetPoint("LEFT", lfmPostButton, "RIGHT", 6, 0)
    lfmCancelButton:SetText("|cffff7777Cancel|r")
    lfmCancelButton:SetScript("OnClick", function()
        SafeInvoke("lfm-cancel", function()
            addon:CancelLFMPostQueue()
        end)
    end)

    local lfmChannelStatus = lfmPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lfmChannelStatus:SetPoint("TOPLEFT", lfmDelayLabel, "BOTTOMLEFT", 0, -14)
    lfmChannelStatus:SetWidth(760)
    lfmChannelStatus:SetJustifyH("LEFT")
    lfmChannelStatus:SetText("")

    local lfmNeedPanel = CreateFrame("Frame", nil, lfmPanel)
    lfmNeedPanel:SetPoint("TOPLEFT", lfmChannelStatus, "BOTTOMLEFT", 0, -10)
    lfmNeedPanel:SetPoint("BOTTOMRIGHT", lfmPanel, "BOTTOMRIGHT", -4, 6)

    local lfmNeedLabel = lfmNeedPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lfmNeedLabel:SetPoint("TOPLEFT", lfmNeedPanel, "TOPLEFT", 0, -2)
    lfmNeedLabel:SetText("Need:")

    local lfmNeedHeaderNeed = lfmNeedPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lfmNeedHeaderNeed:SetPoint("TOPLEFT", lfmNeedLabel, "BOTTOMLEFT", 78, -6)
    lfmNeedHeaderNeed:SetText("Need")

    local lfmNeedHeaderClass = lfmNeedPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lfmNeedHeaderClass:SetPoint("TOPLEFT", lfmNeedLabel, "BOTTOMLEFT", 150, -6)
    lfmNeedHeaderClass:SetText("Class (free text, e.g. mage, boomy)")

    local lfmRoleRows = {}

    local i
    for i = 1, #LFM_ROLE_ROWS do
        local roleRow = LFM_ROLE_ROWS[i]
        local rowY = -24 - ((i - 1) * 26)

        local roleLabel = lfmNeedPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        roleLabel:SetPoint("TOPLEFT", lfmNeedLabel, "BOTTOMLEFT", 4, rowY)
        roleLabel:SetWidth(64)
        roleLabel:SetJustifyH("LEFT")
        roleLabel:SetText(roleRow.label)

        local countBox = CreateFrame("EditBox", "RaidInspectorLFMRoleCount" .. tostring(i), lfmNeedPanel, "InputBoxTemplate")
        countBox:SetPoint("TOPLEFT", lfmNeedLabel, "BOTTOMLEFT", 80, rowY + 3)
        countBox:SetWidth(40)
        countBox:SetHeight(20)
        countBox:SetAutoFocus(false)
        countBox:SetNumeric(true)
        countBox:SetMaxLetters(3)
        countBox:SetJustifyH("CENTER")
        countBox.roleKey = roleRow.key
        countBox:SetScript("OnTextChanged", function(self)
            addon:SetLFMRoleCount(self.roleKey, self:GetText())
        end)
        countBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        countBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        local classBox = CreateFrame("EditBox", "RaidInspectorLFMRoleClass" .. tostring(i), lfmNeedPanel, "InputBoxTemplate")
        classBox:SetPoint("TOPLEFT", lfmNeedLabel, "BOTTOMLEFT", 152, rowY + 3)
        classBox:SetWidth(300)
        classBox:SetHeight(20)
        classBox:SetAutoFocus(false)
        classBox:SetMaxLetters(MAX_LFM_ROLE_CLASSES_LENGTH)
        if classBox.SetTextInsets then
            classBox:SetTextInsets(6, 6, 0, 0)
        end
        classBox.roleKey = roleRow.key
        classBox:SetScript("OnTextChanged", function(self)
            addon:SetLFMRoleClasses(self.roleKey, self:GetText())
        end)
        classBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        classBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        -- Per-row clear button: wipes just this role's count + class.
        local clearRowButton = CreateFrame("Button", "RaidInspectorLFMRoleClear" .. tostring(i), lfmNeedPanel, "UIPanelButtonTemplate")
        clearRowButton:SetWidth(22)
        clearRowButton:SetHeight(20)
        clearRowButton:SetPoint("LEFT", classBox, "RIGHT", 6, 0)
        clearRowButton:SetText("X")
        clearRowButton:SetScript("OnClick", function()
            SafeInvoke("lfm-role-clear", function()
                countBox:SetText("")
                classBox:SetText("")
                addon:SetLFMRoleCount(roleRow.key, "")
                addon:SetLFMRoleClasses(roleRow.key, "")
            end)
        end)

        table.insert(lfmRoleRows, {
            key = roleRow.key,
            countBox = countBox,
            classBox = classBox,
        })
    end

    -- ===== LFM preset controls (save / load / delete / import / export) =====
    local presetLabel = lfmNeedPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    presetLabel:SetPoint("TOPLEFT", lfmNeedLabel, "BOTTOMLEFT", 4, -142)
    presetLabel:SetText("Preset:")

    local lfmPresetDropDown = CreateFrame("Frame", "RaidInspectorLFMPresetDropDown", lfmNeedPanel, "UIDropDownMenuTemplate")
    lfmPresetDropDown:SetPoint("LEFT", presetLabel, "RIGHT", -6, 2)
    UIDropDownMenu_SetWidth(lfmPresetDropDown, 180)
    UIDropDownMenu_JustifyText(lfmPresetDropDown, "LEFT")
    UIDropDownMenu_Initialize(lfmPresetDropDown, function(_, level)
        if level ~= 1 then
            return
        end
        local presets = addon:GetLFMPresets()
        if #presets == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "No saved presets"
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end
        local i
        for i = 1, #presets do
            local preset = presets[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = preset.name
            info.value = preset.name
            info.checked = (addon.ui and addon.ui.lfmSelectedPreset == preset.name)
            info.func = function(btn)
                addon:LoadLFMPreset(btn.value)
                UIDropDownMenu_SetSelectedValue(lfmPresetDropDown, btn.value)
                UIDropDownMenu_SetText(lfmPresetDropDown, btn.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(lfmPresetDropDown, "Select preset")

    local lfmPresetDeleteButton = CreateFrame("Button", "RaidInspectorLFMPresetDelete", lfmNeedPanel, "UIPanelButtonTemplate")
    lfmPresetDeleteButton:SetPoint("LEFT", lfmPresetDropDown, "RIGHT", -8, 2)
    lfmPresetDeleteButton:SetWidth(24)
    lfmPresetDeleteButton:SetHeight(22)
    lfmPresetDeleteButton:SetText("X")
    lfmPresetDeleteButton:SetScript("OnClick", function()
        SafeInvoke("lfm-preset-delete", function()
            local name = addon.ui and addon.ui.lfmSelectedPreset
            if name and name ~= "" then
                addon:DeleteLFMPreset(name)
            else
                Print("lfm: select a preset to delete")
            end
        end)
    end)

    local lfmSaveTemplateButton = CreateFrame("Button", "RaidInspectorLFMSaveTemplate", lfmNeedPanel, "UIPanelButtonTemplate")
    lfmSaveTemplateButton:SetPoint("TOPLEFT", presetLabel, "BOTTOMLEFT", 0, -10)
    lfmSaveTemplateButton:SetWidth(96)
    lfmSaveTemplateButton:SetHeight(22)
    lfmSaveTemplateButton:SetText("Save Template")
    lfmSaveTemplateButton:SetScript("OnClick", function()
        SafeInvoke("lfm-preset-save", function()
            if type(StaticPopup_Show) == "function" then
                StaticPopup_Show("RAIDINSPECTOR_SAVE_PRESET")
            end
        end)
    end)

    local lfmImportTemplateButton = CreateFrame("Button", "RaidInspectorLFMImportTemplate", lfmNeedPanel, "UIPanelButtonTemplate")
    lfmImportTemplateButton:SetPoint("LEFT", lfmSaveTemplateButton, "RIGHT", 6, 0)
    lfmImportTemplateButton:SetWidth(96)
    lfmImportTemplateButton:SetHeight(22)
    lfmImportTemplateButton:SetText("Import")
    lfmImportTemplateButton:SetScript("OnClick", function()
        SafeInvoke("lfm-preset-import", function()
            addon:PromptImportPreset()
        end)
    end)

    local lfmExportTemplateButton = CreateFrame("Button", "RaidInspectorLFMExportTemplate", lfmNeedPanel, "UIPanelButtonTemplate")
    lfmExportTemplateButton:SetPoint("LEFT", lfmImportTemplateButton, "RIGHT", 6, 0)
    lfmExportTemplateButton:SetWidth(96)
    lfmExportTemplateButton:SetHeight(22)
    lfmExportTemplateButton:SetText("Export")
    lfmExportTemplateButton:SetScript("OnClick", function()
        SafeInvoke("lfm-preset-export", function()
            local name = addon.ui and addon.ui.lfmSelectedPreset
            if not name or name == "" then
                Print("lfm: select a preset to export first")
                return
            end
            if type(StaticPopup_Show) == "function" then
                StaticPopup_Show("RAIDINSPECTOR_EXPORT_PRESET", name, nil, name)
            end
        end)
    end)

    addon.ui.frame = f
    addon.ui.subtitle = subtitle
    addon.ui.inspectorTabButton = inspectorTabButton
    addon.ui.lfmTabButton = lfmTabButton
    addon.ui.statusText = statusText
    addon.ui.shareChannelsRow = shareChannelsRow
    addon.ui.shareChannelsLabel = shareChannelsLabel
    addon.ui.raidShareCheck = raidShareCheck
    addon.ui.sayShareCheck = sayShareCheck
    addon.ui.whisperShareCheck = whisperShareCheck
    addon.ui.guildShareCheck = guildShareCheck
    addon.ui.savedReportsRow = savedReportsRow
    addon.ui.savedReportsLabel = savedReportsLabel
    addon.ui.sortRow = sortRow
    addon.ui.sortLabel = sortLabel
    addon.ui.sortDropDown = sortDropDown
    addon.ui.actionPanel = actionPanel
    addon.ui.sortButton = sortButton
    addon.ui.filterButton = filterButton
    addon.ui.targetButton = targetButton
    addon.ui.raidButton = raidButton
    addon.ui.autoScanButton = autoScanButton
    addon.ui.msButton = msButton
    addon.ui.msShareButton = msShareButton
    addon.ui.msClearButton = msClearButton
    addon.ui.rwShareCheck = rwShareCheck
    addon.ui.syncButton = syncButton
    addon.ui.forceSyncButton = forceSyncButton
    addon.ui.reportButton = reportButton
    addon.ui.staleButton = staleButton
    addon.ui.statusButton = statusButton
    addon.ui.clearButton = clearButton
    addon.ui.savedReportDropDown = savedReportDropDown
    addon.ui.rowsViewport = rowsViewport
    addon.ui.overviewRows = rowsContainer.rows
    addon.ui.overviewScroll = overviewScroll
    addon.ui.overviewEntryCount = 0
    addon.ui.compositionHeader = compositionHeader
    addon.ui.compositionSummary = compositionSummary
    addon.ui.detailHeader = detailHeader
    addon.ui.detailScore = detailScore
    addon.ui.detailMeta = detailMeta
    addon.ui.detailAudit = detailAudit
    addon.ui.itemFilterLabel = itemFilterLabel
    addon.ui.itemFilterDropDown = itemFilterDropDown
    addon.ui.detailHeaderRow = detailHeaderRow
    addon.ui.detailContainer = detailContainer
    addon.ui.detailRows = detailContainer.rows
    addon.ui.detailScroll = detailScroll
    addon.ui.detailLineCount = 0
    addon.ui.lastDetailKey = ""
    addon.ui.lastDetailEntry = nil
    addon.ui.lfmPanel = lfmPanel
    addon.ui.lfmMessageBox = lfmMessageBox
    addon.ui.lfmYellCheck = lfmYellCheck
    addon.ui.lfmGuildCheck = lfmGuildCheck
    addon.ui.lfmGeneralCheck = lfmGeneralCheck
    addon.ui.lfmGlobalCheck = lfmGlobalCheck
    addon.ui.lfmDelayBox = lfmDelayBox
    addon.ui.lfmRepeatBox = lfmRepeatBox
    addon.ui.lfmPostButton = lfmPostButton
    addon.ui.lfmCancelButton = lfmCancelButton
    addon.ui.lfmChannelStatus = lfmChannelStatus
    addon.ui.lfmRoleRows = lfmRoleRows
    addon.ui.lfmPresetDropDown = lfmPresetDropDown

    addon:ApplyButtonModeLayout()
    addon:SetActiveTab(addon:GetActiveTab())
    addon:ApplyKeybinds()

    f:Hide()
end

function addon:CreateMinimapButton()
    if addon.ui and addon.ui.minimapButton then
        addon.ui.minimapButton:Hide()
        addon.ui.minimapButton = nil
    end

    if RaidInspectorMinimapButton then
        RaidInspectorMinimapButton:Hide()
    end
end

function addon:BuildOverviewRowText(entry)
    local req = entry.req
    local result = entry.result
    local state = entry.state
    local reqId = tonumber(req.id) or 0
    local reqName = req.name or "Unknown"
    local reqRealm = req.realm or "Unknown"

    local gsText = "-"
    if result and result.gearScore then
        gsText = ColorText(tostring(result.gearScore), GetGearScoreColorCode(result.gearScore))
    end

    -- A recorded MS replaces the scan age on the row: during a raid the spec a
    -- player just called out matters more than how old their gear scan is.
    -- A saved report shows the MS stored in the report itself, so it stays a
    -- snapshot of that raid instead of following today's live MS list.
    local ageText = ""
    local msText = nil
    if addon:GetSelectedSavedReportFile() ~= "" then
        msText = result and result.mainSpec
    else
        local msRecord = addon:GetMainSpecRecord(entry.key)
        msText = msRecord and msRecord.spec
    end

    if msText and msText ~= "" then
        ageText = " " .. ColorText("MS:" .. SafeText(msText), "ffd200")
    elseif entry.ageMinutes >= 0 then
        ageText = " Scanned=" .. tostring(entry.ageMinutes) .. "m"
    end

    local issueSummary = result and result.issueSummary or {}
    local missingEnchant = tonumber(issueSummary.missingEnchant or 0) or 0
    local missingGems = tonumber(issueSummary.missingGems or 0) or 0
    local auditText = ""
    if missingEnchant > 0 or missingGems > 0 then
        auditText = " E" .. tostring(missingEnchant) .. " G" .. tostring(missingGems)
    end

    local reasonText = ""
    if (state == "queued" or state == "error") and entry.statusReason and entry.statusReason ~= "" then
        reasonText = " | " .. FormatStatusReason(entry.statusReason)
    end

    local nameText = SafeText(reqName)
    local pvpItems = result and result.issueSummary and tonumber(result.issueSummary.pvpItems or 0) or 0
    if pvpItems > 0 then
        nameText = ColorText(nameText, "ff8000")
    elseif result and result.class then
        nameText = ColorClassText(nameText, result.class)
    end

    return "#" .. tostring(reqId)
        .. " " .. nameText
        .. " [" .. state .. "] GS=" .. gsText
        .. auditText
        .. reasonText
        .. ageText
end

local function SpecContains(specLower, needle)
    return specLower ~= "" and string.find(specLower, needle, 1, true) ~= nil
end

local function ClassifyTalentRole(classValue, specValue)
    local classToken = ResolveClassToken(classValue)
    local specLower = string.lower(Trim(specValue or ""))

    if classToken == "WARRIOR" then
        if SpecContains(specLower, "protection") then
            return "tank"
        end
        if specLower ~= "" then
            return "mdps"
        end
        return nil
    end

    if classToken == "PALADIN" then
        if SpecContains(specLower, "protection tank") then
            return "tank"
        end
        if SpecContains(specLower, "protection dps") then
            return "mdps"
        end
        if SpecContains(specLower, "holy healer") then
            return "heal"
        end
        if SpecContains(specLower, "holy dps") then
            return "rdps"
        end
        if SpecContains(specLower, "holy") then
            return "heal"
        end
        if SpecContains(specLower, "protection") then
            return "tank"
        end
        if SpecContains(specLower, "retribution") then
            return "mdps"
        end
        return nil
    end

    if classToken == "DEATHKNIGHT" then
        if SpecContains(specLower, "blood tank") then
            return "tank"
        end
        if SpecContains(specLower, "blood dps") then
            return "mdps"
        end
        if SpecContains(specLower, "blood") then
            return "tank"
        end
        if specLower ~= "" then
            return "mdps"
        end
        return nil
    end

    if classToken == "DRUID" then
        if SpecContains(specLower, "feral tank") then
            return "tank"
        end
        if SpecContains(specLower, "feral dps") then
            return "mdps"
        end
        if SpecContains(specLower, "restoration") then
            return "heal"
        end
        if SpecContains(specLower, "balance") then
            return "rdps"
        end
        if SpecContains(specLower, "feral") then
            return "mdps"
        end
        return nil
    end

    if classToken == "PRIEST" then
        if SpecContains(specLower, "discipline") or SpecContains(specLower, "holy") then
            return "heal"
        end
        if SpecContains(specLower, "shadow") then
            return "rdps"
        end
        return nil
    end

    if classToken == "SHAMAN" then
        if SpecContains(specLower, "restoration") then
            return "heal"
        end
        if SpecContains(specLower, "elemental") then
            return "rdps"
        end
        if SpecContains(specLower, "enhancement") then
            return "mdps"
        end
        return nil
    end

    if classToken == "HUNTER" or classToken == "MAGE" or classToken == "WARLOCK" then
        return "rdps"
    end

    if classToken == "ROGUE" then
        return "mdps"
    end

    return nil
end

local function BuildRaidCompositionCounts(entries)
    local counts = {
        tank = 0,
        heal = 0,
        rdps = 0,
        mdps = 0,
        total = #(entries or {}),
    }

    local i
    for i = 1, #(entries or {}) do
        local result = entries[i] and entries[i].result
        if type(result) == "table" and not result.error then
            local role = ClassifyTalentRole(result.class, result.spec)
            if role and counts[role] ~= nil then
                counts[role] = counts[role] + 1
            end
        end
    end

    return counts
end

local function EntryHasMissingAuditIssues(entry)
    if type(entry) ~= "table" or type(entry.result) ~= "table" then
        return false
    end

    local summary = entry.result.issueSummary or {}
    local missingEnchant = tonumber(summary.missingEnchant or 0) or 0
    local missingGems = tonumber(summary.missingGems or 0) or 0
    return missingEnchant > 0 or missingGems > 0
end

local function EntryHasStoredGear(entry)
    return type(entry) == "table"
        and type(entry.result) == "table"
        and type(entry.result.items) == "table"
        and #entry.result.items > 0
end

local function EntryIsPendingNotInspectable(entry)
    if type(entry) ~= "table" then
        return false
    end

    if tostring(entry.statusReason or "") ~= "cannot-inspect" then
        return false
    end

    if entry.state ~= "ready" then
        return true
    end

    return entry.isFresh ~= true
end

-- Returns the aligned-column data for a gear slot: { slot, name, ilvl, enchant,
-- gems, r, g, b }. Colour follows the same priority as the old single line.
function addon:BuildSlotColumns(slotKey, item)
    local slotLabel = SLOT_LABELS[slotKey] or slotKey
    if not item then
        return { slot = slotLabel, name = "-", ilvl = "", enchant = "", gems = "", r = 0.72, g = 0.72, b = 0.72 }
    end

    local itemName = item.name
    if not itemName or itemName == "" then
        local itemId = tonumber(item.itemId)
        if itemId then
            itemName = "item:" .. tostring(itemId)
        else
            itemName = "Unknown item"
        end
    end

    local ilvl = tonumber(item.ilvl)
    local ilvlText = ""
    if ilvl and ilvl > 0 then
        ilvlText = "i" .. tostring(ilvl)
    end

    local enchantText = "E:n/a"
    local missingEnchant = false
    if ENCHANTABLE_SLOTS[slotKey] then
        local enchantId = GetRecordedEnchantId(item)
        if not enchantId then
            if OPTIONAL_ENCHANT_SLOTS[slotKey] then
                enchantText = "E:OPT"
            else
                enchantText = "E:MISS"
                missingEnchant = true
            end
        elseif IsLowTierEnchant(item) then
            enchantText = "E:LOW"
        else
            enchantText = "E:OK"
        end
    end

    local socketCount = tonumber(item.socketCount) or 0
    local gemCount = 0
    local missingGems = false
    if type(item.gems) == "table" then
        gemCount = #item.gems
    end

    local gemText = "G:n/a"
    if socketCount > 0 then
        if gemCount < socketCount then
            gemText = "G:" .. tostring(gemCount) .. "/" .. tostring(socketCount) .. " MISS"
            missingGems = true
        else
            gemText = "G:" .. tostring(socketCount) .. "/" .. tostring(socketCount)
        end
    end

    if item.isPvp then
        gemText = gemText .. " PVP"
    end

    local columns = {
        slot = slotLabel,
        name = itemName,
        ilvl = ilvlText,
        enchant = enchantText,
        gems = gemText,
    }

    -- PvP orange takes priority so it stands out even if otherwise complete.
    if item.isPvp then
        columns.r, columns.g, columns.b = 1.0, 0.5, 0.0
    elseif missingEnchant or missingGems then
        columns.r, columns.g, columns.b = 1.0, 0.4, 0.4
    elseif ENCHANTABLE_SLOTS[slotKey] or socketCount > 0 then
        columns.r, columns.g, columns.b = 0.4, 1.0, 0.4
    else
        columns.r, columns.g, columns.b = 0.87, 0.87, 0.87
    end

    return columns
end

local function ItemMatchesListFilter(mode, slotKey, item)
    if mode == "all" then
        return true
    end

    if type(item) ~= "table" then
        return false
    end

    local missingEnchant = false
    if ENCHANTABLE_SLOTS[slotKey] then
        local enchantId = GetRecordedEnchantId(item)
        if not enchantId and not OPTIONAL_ENCHANT_SLOTS[slotKey] then
            missingEnchant = true
        end
    end

    local socketCount = tonumber(item.socketCount) or 0
    local gemCount = (type(item.gems) == "table") and #item.gems or 0
    local missingGems = socketCount > 0 and gemCount < socketCount

    if mode == "issues" then
        return missingEnchant or missingGems
    end

    if mode == "missing-enchant" then
        return missingEnchant
    end

    if mode == "missing-gems" then
        return missingGems
    end

    return true
end

function addon:RefreshDetailPanel(selectedEntry)
    if not addon.ui or not addon.ui.detailHeader then
        return
    end

    addon.ui.lastDetailEntry = selectedEntry

    if not selectedEntry then
        addon.ui.detailHeader:SetText("Selected: none")
        addon.ui.detailScore:SetText("Select a player from the left overview.")
        if addon.ui.detailMeta then
            addon.ui.detailMeta:SetText("")
        end
        addon.ui.detailAudit:SetText("")
        addon.ui.detailLineCount = 0
        if addon.ui.detailScroll then
            SetFauxScrollOffset(addon.ui.detailScroll, 0, DETAIL_ROW_HEIGHT)
            FauxScrollFrame_Update(addon.ui.detailScroll, 0, #addon.ui.detailRows, DETAIL_ROW_HEIGHT)
        end
        local i
        for i = 1, #addon.ui.detailRows do
            ClearDetailRowColumns(addon.ui.detailRows[i])
            addon.ui.detailRows[i].data = nil
        end
        return
    end

    local req = selectedEntry.req
    local result = selectedEntry.result
    local selectedNameText = SafeText(req.name)
    local selectedPvpItems = result and result.issueSummary and tonumber(result.issueSummary.pvpItems or 0) or 0
    if selectedPvpItems > 0 then
        selectedNameText = ColorText(selectedNameText, "ff8000")
    elseif result and result.class then
        selectedNameText = ColorClassText(selectedNameText, result.class)
    end
    addon.ui.detailHeader:SetText("Selected: " .. selectedNameText .. " [" .. selectedEntry.state .. "]")

    if not result then
        local reason = FormatStatusReason(req.statusReason)
        if reason ~= "" then
            addon.ui.detailScore:SetText("No result yet (" .. reason .. "). Use Target/Raid while the player is inspectable.")
        else
            addon.ui.detailScore:SetText("No result yet. Use Target/Raid while the player is inspectable.")
        end
        if addon.ui.detailMeta then
            addon.ui.detailMeta:SetText("")
        end
        addon.ui.detailAudit:SetText("")
        addon.ui.detailLineCount = 0
        if addon.ui.detailScroll then
            SetFauxScrollOffset(addon.ui.detailScroll, 0, DETAIL_ROW_HEIGHT)
            FauxScrollFrame_Update(addon.ui.detailScroll, 0, #addon.ui.detailRows, DETAIL_ROW_HEIGHT)
        end
        local i
        for i = 1, #addon.ui.detailRows do
            ClearDetailRowColumns(addon.ui.detailRows[i])
            addon.ui.detailRows[i].data = nil
        end
        return
    end

    local classText = result.class and tostring(result.class) or "?"
    local specText = result.spec and tostring(result.spec) or "?"
    local guildText = result.guild and tostring(result.guild) or "-"
    local levelText = result.level and tostring(result.level) or "?"
    local scoreValue = result.gearScore and tostring(result.gearScore) or "N/A"
    local scoreColored = result.gearScore and ColorText(scoreValue, GetGearScoreColorCode(result.gearScore)) or scoreValue
    local classColored = ColorClassText(classText, result.class)
    local specColored = ColorText(specText, "ff9933")

    addon.ui.detailScore:SetText(
        "GS: " .. scoreColored .. " | Character: Lvl " .. levelText .. " | " .. classColored .. " | Guild: " .. guildText
    )

    if addon.ui.detailMeta then
        addon.ui.detailMeta:SetText("Talent: " .. specColored)
    end

    local summary = result.issueSummary or {}
    local missingEnchant = tonumber(summary.missingEnchant or 0) or 0
    local missingGems = tonumber(summary.missingGems or 0) or 0
    local itemsAnalyzed = tonumber(summary.itemsAnalyzed or 0) or 0
    local socketsFilled = tonumber(summary.filledSockets or 0) or 0
    local socketsTotal = tonumber(summary.totalSockets or 0) or 0
    local pvpItems = tonumber(summary.pvpItems or 0) or 0

    local missingEnchantText = "missingEnchant=" .. tostring(missingEnchant)
    local missingGemsText = "missingGems=" .. tostring(missingGems)
    local socketsText = "sockets=" .. tostring(socketsFilled) .. "/" .. tostring(socketsTotal)
    local pvpText = "pvp=" .. tostring(pvpItems)

    if missingEnchant > 0 then
        missingEnchantText = ColorText(missingEnchantText, "ff6666")
    end

    if missingGems > 0 then
        missingGemsText = ColorText(missingGemsText, "ff6666")
    end

    if socketsTotal > 0 and socketsFilled < socketsTotal then
        socketsText = ColorText(socketsText, "ff6666")
    end

    if pvpItems > 0 then
        pvpText = ColorText(pvpText, "ff8000")
    end

    local auditText = "Audit: " .. missingEnchantText
        .. " | " .. missingGemsText
        .. " | " .. socketsText
        .. " | items=" .. tostring(itemsAnalyzed)
        .. " | " .. pvpText

    addon.ui.detailAudit:SetText(auditText)

    local itemsBySlot = {}
    local detailLines = {}
    local unslotted = 0
    local filterMode = addon:GetItemListFilterMode()
    local i

    for i = 1, #(result.items or {}) do
        local item = result.items[i]
        local slot = NormalizeSlot(item.slot)
        if slot and not itemsBySlot[slot] then
            itemsBySlot[slot] = item
        else
            unslotted = unslotted + 1
        end
    end

    for i = 1, #SLOT_ORDER do
        local slotKey = SLOT_ORDER[i]
        local slotItem = itemsBySlot[slotKey]
        if ItemMatchesListFilter(filterMode, slotKey, slotItem) then
            table.insert(detailLines, {
                columns = addon:BuildSlotColumns(slotKey, slotItem),
                item = slotItem,
                slotKey = slotKey,
            })
        end
    end

    if unslotted > 0 and filterMode == "all" then
        table.insert(detailLines, {
            infoText = "Other: " .. tostring(unslotted) .. " unslotted item(s)",
            r = 1.0, g = 0.8, b = 0.4,
        })
    end

    if #detailLines == 0 then
        table.insert(detailLines, {
            infoText = "No items match selected filter.",
            r = 1.0, g = 0.8, b = 0.4,
        })
    end

    if addon.ui.lastDetailKey ~= selectedEntry.key then
        addon.ui.lastDetailKey = selectedEntry.key
        if addon.ui.detailScroll then
            SetFauxScrollOffset(addon.ui.detailScroll, 0, DETAIL_ROW_HEIGHT)
        end
    end

    addon.ui.detailLineCount = #detailLines

    local offset = 0
    if addon.ui.detailScroll then
        local maxOffset = math.max(0, #detailLines - #addon.ui.detailRows)
        local currentOffset = GetFauxScrollOffset(addon.ui.detailScroll)
        if currentOffset > maxOffset then
            SetFauxScrollOffset(addon.ui.detailScroll, maxOffset, DETAIL_ROW_HEIGHT)
            currentOffset = maxOffset
        end
        FauxScrollFrame_Update(addon.ui.detailScroll, #detailLines, #addon.ui.detailRows, DETAIL_ROW_HEIGHT)
        offset = currentOffset
    end

    local rowIndex
    for rowIndex = 1, #addon.ui.detailRows do
        local lineData = detailLines[rowIndex + offset]
        local row = addon.ui.detailRows[rowIndex]
        local c
        if lineData and lineData.columns then
            local cols = lineData.columns
            for c = 1, #DETAIL_COLUMNS do
                local col = DETAIL_COLUMNS[c]
                local fs = row.colFS[col.key]
                local value = cols[col.key] or ""
                if col.truncate then
                    SetTruncatedText(fs, value, col.width)
                else
                    fs:SetText(value)
                end
                fs:SetTextColor(cols.r or 1, cols.g or 1, cols.b or 1)
            end
            row.data = lineData
        elseif lineData and lineData.infoText then
            for c = 1, #DETAIL_COLUMNS do
                local col = DETAIL_COLUMNS[c]
                local fs = row.colFS[col.key]
                if col.key == "name" then
                    fs:SetText(lineData.infoText)
                    fs:SetTextColor(lineData.r or 1, lineData.g or 1, lineData.b or 1)
                else
                    fs:SetText("")
                end
            end
            row.data = nil
        else
            for c = 1, #DETAIL_COLUMNS do
                row.colFS[DETAIL_COLUMNS[c].key]:SetText("")
            end
            row.data = nil
        end
    end
end

function addon:RefreshMainWindow()
    if not addon.ui or not addon.ui.frame then
        return
    end

    local activeTab = addon:GetActiveTab()
    addon:RefreshTabVisibility()
    if activeTab == "inspector" then
        addon:ApplyButtonModeLayout()
    end

    local activeSavedReport = addon:GetActiveSavedReport()

    local queued, ready, errorCount = addon:GetCounts()
    local fresh, stale = addon:GetFreshnessCounts(FRESHNESS_TTL_SECONDS)
    local playersWithIssues, totalIssues = addon:GetIssueTotals()

    if activeTab == "lfm" then
        local postDelaySeconds = addon:GetLFMPostDelaySeconds()
        local queueCount = addon.lfmPostQueue and #addon.lfmPostQueue or 0
        local queueText = ""
        if queueCount > 0 then
            local secondsUntilNext = math.max(0, (tonumber(addon.lfmPostNextAt) or 0) - GetNow())
            queueText = " | Queue: " .. tostring(queueCount) .. " pending, next in " .. tostring(secondsUntilNext) .. "s"
        end

        local repeatCount = addon:GetLFMRepeatCount()
        addon.ui.statusText:SetText(
            "LFM Composer: write your post, pick channels, set delay/repeat, fill the Need table, press POST."
                .. " (" .. tostring(postDelaySeconds) .. "s spacing, x" .. tostring(repeatCount) .. " repeat)"
                .. queueText
        )
    elseif activeSavedReport then
        addon.ui.statusText:SetText(
            "Saved Report: " .. addon:BuildSavedReportMenuLabel(activeSavedReport)
                .. "  |  Source: saved variables"
        )
    else
        -- Live overview: the queue/ready/stale counts line was removed by request.
        addon.ui.statusText:SetText("")
    end

    if addon.ui.sortDropDown then
        local sortMode = addon:GetSortMode()
        UIDropDownMenu_SetSelectedValue(addon.ui.sortDropDown, sortMode)
        UIDropDownMenu_SetText(addon.ui.sortDropDown, SORT_LABELS[sortMode] or sortMode)
    end

    if addon.ui.filterButton then
        addon.ui.filterButton:SetText("|cff66ff66F:" .. addon:GetFilterMode() .. "|r")
    end

    if addon.ui.itemFilterDropDown then
        local selectedMode = addon:GetItemListFilterMode()
        UIDropDownMenu_SetSelectedValue(addon.ui.itemFilterDropDown, selectedMode)
        UIDropDownMenu_SetText(addon.ui.itemFilterDropDown, ITEM_LIST_FILTER_LABELS[selectedMode] or selectedMode)
    end

    if addon.ui.savedReportDropDown then
        local selectedFile = addon:GetSelectedSavedReportFile()
        UIDropDownMenu_SetSelectedValue(addon.ui.savedReportDropDown, selectedFile)
        if selectedFile == "" then
            UIDropDownMenu_SetText(addon.ui.savedReportDropDown, "Live Overview")
        else
            local item = addon:GetActiveSavedReport()
            UIDropDownMenu_SetText(addon.ui.savedReportDropDown, item and addon:BuildSavedReportMenuLabel(item) or "Live Overview")
        end
    end

    local channels = addon:GetExportChannels()
    if addon.ui.raidShareCheck then
        addon.ui.raidShareCheck:SetChecked(channels.raid == true)
    end
    if addon.ui.sayShareCheck then
        addon.ui.sayShareCheck:SetChecked(channels.say == true)
    end
    if addon.ui.whisperShareCheck then
        addon.ui.whisperShareCheck:SetChecked(channels.whisper == true)
    end
    if addon.ui.rwShareCheck then
        addon.ui.rwShareCheck:SetChecked(channels.rw == true)
    end
    if addon.ui.guildShareCheck then
        addon.ui.guildShareCheck:SetChecked(channels.guild == true)
    end

    local lfmChannels = addon:GetLFMChannels()
    if addon.ui.lfmYellCheck then
        addon.ui.lfmYellCheck:SetChecked(lfmChannels.yell == true)
    end
    if addon.ui.lfmGuildCheck then
        addon.ui.lfmGuildCheck:SetChecked(lfmChannels.guild == true)
    end
    if addon.ui.lfmGeneralCheck then
        addon.ui.lfmGeneralCheck:SetChecked(lfmChannels.general == true)
    end
    if addon.ui.lfmGlobalCheck then
        addon.ui.lfmGlobalCheck:SetChecked(lfmChannels.global == true)
    end

    local lfmRoles = addon:GetLFMRoleState()
    if addon.ui.lfmRoleRows then
        local i
        for i = 1, #addon.ui.lfmRoleRows do
            local entry = addon.ui.lfmRoleRows[i]
            local data = lfmRoles[entry.key] or {}
            if entry.countBox and not entry.countBox:HasFocus() then
                local desired = tostring(data.count or "")
                if (entry.countBox:GetText() or "") ~= desired then
                    entry.countBox:SetText(desired)
                end
            end
            if entry.classBox and not entry.classBox:HasFocus() then
                local desired = tostring(data.classes or "")
                if (entry.classBox:GetText() or "") ~= desired then
                    entry.classBox:SetText(desired)
                end
            end
        end
    end

    if addon.ui.lfmDelayBox and not addon.ui.lfmDelayBox:HasFocus() then
        local desired = tostring(addon:GetLFMPostDelaySeconds())
        if (addon.ui.lfmDelayBox:GetText() or "") ~= desired then
            addon.ui.lfmDelayBox:SetText(desired)
        end
    end

    if addon.ui.lfmRepeatBox and not addon.ui.lfmRepeatBox:HasFocus() then
        local desired = tostring(addon:GetLFMRepeatCount())
        if (addon.ui.lfmRepeatBox:GetText() or "") ~= desired then
            addon.ui.lfmRepeatBox:SetText(desired)
        end
    end

    if addon.ui.lfmPresetDropDown then
        local selected = addon.ui.lfmSelectedPreset
        if selected and addon:FindLFMPreset(selected) then
            UIDropDownMenu_SetSelectedValue(addon.ui.lfmPresetDropDown, selected)
            UIDropDownMenu_SetText(addon.ui.lfmPresetDropDown, selected)
        else
            UIDropDownMenu_SetText(addon.ui.lfmPresetDropDown, "Select preset")
        end
    end

    if addon.ui.lfmChannelStatus then
        local availability = addon:GetLFMChannelAvailability()

        local function BuildChannelStatusLabel(channelKey, label, isAvailable, joinedName)
            local selected = lfmChannels[channelKey] == true
            local prefix = selected and "[x] " or "[ ] "

            local stateText = "ready"
            if channelKey == "guild" then
                stateText = isAvailable and "in guild" or "no guild"
            elseif channelKey ~= "yell" then
                if isAvailable then
                    stateText = "joined"
                else
                    stateText = "missing"
                end
            end

            local detail = ""
            if channelKey ~= "yell" and isAvailable and joinedName and joinedName ~= "" then
                detail = " (" .. tostring(joinedName) .. ")"
            end

            local color = "b8b8b8"
            if isAvailable then
                if selected then
                    color = "66ff66"
                end
            else
                if selected then
                    color = "ffaa33"
                else
                    color = "ff6666"
                end
            end

            return ColorText(prefix .. label .. ": " .. stateText .. detail, color)
        end

        local statusText = "Channel status: "
            .. BuildChannelStatusLabel("yell", "Yell", availability.yell, nil)
            .. "  |  "
            .. BuildChannelStatusLabel("guild", "/guild", availability.guild, nil)
            .. "  |  "
            .. BuildChannelStatusLabel("general", "/general", availability.general, availability.generalName)
            .. "  |  "
            .. BuildChannelStatusLabel("global", "/global", availability.global, availability.globalName)

        addon.ui.lfmChannelStatus:SetText(statusText)
    end

    if addon.ui.lfmMessageBox and not addon.ui.lfmMessageBox:HasFocus() then
        local desiredText = addon:GetLFMMessage()
        if (addon.ui.lfmMessageBox:GetText() or "") ~= desiredText then
            addon.ui.lfmMessageBox:SetText(desiredText)
        end
    end

    local entries = addon:GetOverviewEntries()
    if #entries == 0 and not activeSavedReport then
        local latestByKey = addon:GetLatestRequestMap()
        local key
        for key in pairs(latestByKey) do
            local req = latestByKey[key]
            local result = RaidInspectorDB.results[key]
            -- Same derivation as addon:GetOverviewEntries: a stored result only
            -- upgrades the state to "ready" when the request did not fail.
            local state = req.status or "queued"
            if state ~= "error" and result and not result.error then
                state = "ready"
            end
            table.insert(entries, {
                key = key,
                req = req,
                result = result,
                state = state,
                statusReason = req.statusReason,
                updatedAt = result and (tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0) or 0,
                ageMinutes = -1,
                isFresh = false,
            })
        end
        table.sort(entries, function(a, b)
            return string.lower(tostring(a.key or "")) < string.lower(tostring(b.key or ""))
        end)
    end

    if addon.ui.compositionSummary then
        local compositionEntries = addon:GetCompositionEntries()
        local counts = BuildRaidCompositionCounts(compositionEntries)
        addon.ui.compositionSummary:SetText(
            "Tanks: " .. tostring(counts.tank)
                .. "  |  Heals: " .. tostring(counts.heal)
                .. "  |  RDPS: " .. tostring(counts.rdps)
                .. "  |  MDPS: " .. tostring(counts.mdps)
                .. "  |  Total: " .. tostring(counts.total)
        )
    end

    addon.ui.overviewEntryCount = #entries
    local overviewOffset = 0
    if addon.ui.overviewScroll then
        local maxOverviewOffset = math.max(0, #entries - #addon.ui.overviewRows)
        local currentOverviewOffset = GetFauxScrollOffset(addon.ui.overviewScroll)
        if currentOverviewOffset > maxOverviewOffset then
            SetFauxScrollOffset(addon.ui.overviewScroll, maxOverviewOffset, OVERVIEW_ROW_HEIGHT)
            currentOverviewOffset = maxOverviewOffset
        end
        FauxScrollFrame_Update(addon.ui.overviewScroll, #entries, #addon.ui.overviewRows, OVERVIEW_ROW_HEIGHT)
        overviewOffset = currentOverviewOffset
    end

    local selectedKey = addon:GetSelectedKey()
    local selectedEntry = nil
    local i

    for i = 1, #entries do
        if entries[i].key == selectedKey then
            selectedEntry = entries[i]
            break
        end
    end

    if selectedKey == "" or not selectedEntry then
        if #entries > 0 then
            selectedKey = entries[1].key
            addon:SetSelectedKey(selectedKey)
        else
            selectedKey = ""
            addon:SetSelectedKey("")
        end
    end

    if not selectedEntry and #entries > 0 then
        selectedEntry = entries[1]
        selectedKey = entries[1].key
        addon:SetSelectedKey(selectedKey)
    end

    local rowIndex
    for rowIndex = 1, #addon.ui.overviewRows do
        local row = addon.ui.overviewRows[rowIndex]
        local entry = entries[rowIndex + overviewOffset]
        if entry then
            row.key = entry.key
            row.playerName = entry.req and entry.req.name or nil
            row.text:SetText(addon:BuildOverviewRowText(entry))
            local hasAuditIssues = EntryHasMissingAuditIssues(entry)
            local isPendingNotInspectable = EntryIsPendingNotInspectable(entry)
            local isSelected = entry.key == selectedKey
            if isPendingNotInspectable then
                row.text:SetTextColor(1.0, 0.65, 0.10)
            elseif hasAuditIssues then
                row.text:SetTextColor(1.0, 0.20, 0.20)
            else
                row.text:SetTextColor(0.35, 1.0, 0.35)
            end
            SetFontStringBold(row.text, isSelected)
            if isSelected then
                row:LockHighlight()
            else
                row:UnlockHighlight()
            end

            if row.refreshButton and row.removeButton then
                row.refreshButton.key = entry.key
                row.removeButton.key = entry.key
                if isSelected and addon:GetSelectedSavedReportFile() == "" then
                    row.refreshButton:Show()
                    row.removeButton:Show()
                else
                    row.refreshButton:Hide()
                    row.removeButton:Hide()
                end
            end

            if row.gearButton then
                row.gearButton.key = entry.key
                if EntryHasStoredGear(entry) then
                    row.gearButton:Show()
                else
                    row.gearButton:Hide()
                end
            end

            row:Show()
        else
            row.key = nil
            row.playerName = nil
            row.text:SetText("")
            row.text:SetTextColor(1.0, 1.0, 1.0)
            SetFontStringBold(row.text, false)
            row:UnlockHighlight()
            if row.refreshButton and row.removeButton then
                row.refreshButton.key = nil
                row.removeButton.key = nil
                row.refreshButton:Hide()
                row.removeButton:Hide()
            end
            if row.gearButton then
                row.gearButton.key = nil
                row.gearButton:Hide()
            end
            row:Hide()
        end
    end

    addon:RefreshDetailPanel(selectedEntry)
end

function addon:ToggleWindow(forceShow)
    if not addon.ui or not addon.ui.frame then
        addon:CreateMainWindow()
        if not addon.ui or not addon.ui.frame then
            Print("unable to open window: UI failed to initialize")
            return
        end
    end

    if forceShow == true then
        addon.ui.frame:Show()
    elseif forceShow == false then
        addon.ui.frame:Hide()
    elseif addon.ui.frame:IsShown() then
        addon.ui.frame:Hide()
    else
        addon.ui.frame:Show()
    end

    addon:RefreshMainWindow()
end

function addon:FindUnitByName(name)
    local wanted = string.lower(name or "")
    if wanted == "" then
        return nil
    end

    local function MatchUnit(unit)
        if not UnitExists(unit) then
            return false
        end
        local unitName = UnitName(unit)
        return unitName and string.lower(unitName) == wanted
    end

    if MatchUnit("target") then
        return "target"
    end

    if MatchUnit("focus") then
        return "focus"
    end

    if MatchUnit("mouseover") then
        return "mouseover"
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local i
        for i = 1, GetNumRaidMembers() do
            local raidUnit = "raid" .. tostring(i)
            if MatchUnit(raidUnit) then
                return raidUnit
            end
        end
    end

    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        local i
        for i = 1, GetNumPartyMembers() do
            local partyUnit = "party" .. tostring(i)
            if MatchUnit(partyUnit) then
                return partyUnit
            end
        end
    end

    return nil
end

function addon:TryTargetNearbyPlayer(name, realm)
    if type(TargetByName) ~= "function" then
        return false, "target-by-name-unsupported"
    end

    local wantedName = string.lower(Trim(name or ""))
    if wantedName == "" then
        return false, "bad-unit-name"
    end

    local expectedRealm = string.lower(string.gsub(Trim(realm or ""), "%s+", ""))
    local hadTarget = UnitExists("target")

    local okTarget = pcall(TargetByName, name, true)
    if not okTarget or not UnitExists("target") then
        return false, "unit-not-found"
    end

    local targetName, targetRealm = UnitName("target")
    if not targetName or string.lower(targetName) ~= wantedName then
        if hadTarget and type(TargetLastTarget) == "function" then
            pcall(TargetLastTarget)
        elseif not hadTarget and type(ClearTarget) == "function" then
            pcall(ClearTarget)
        end
        return false, "unit-not-found"
    end

    if expectedRealm ~= "" then
        local actualRealm = targetRealm
        if not actualRealm or actualRealm == "" then
            actualRealm = GetRealmName() or ""
        end
        actualRealm = string.lower(string.gsub(actualRealm, "%s+", ""))
        if actualRealm ~= "" and actualRealm ~= expectedRealm then
            if hadTarget and type(TargetLastTarget) == "function" then
                pcall(TargetLastTarget)
            elseif not hadTarget and type(ClearTarget) == "function" then
                pcall(ClearTarget)
            end
            return false, "unit-not-found"
        end
    end

    return true, "nearby-target"
end

function addon:HandleInspectCommand(args)
    if args == "" then
        Print("usage: /ri inspect <name> <realm>")
        return
    end

    local arg1, rest = string.match(args, "^(%S+)%s*(.-)$")
    if not arg1 then
        Print("usage: /ri inspect <name> <realm>")
        return
    end

    local name = arg1
    local realm = rest or ""

    local splitName, splitRealm = string.match(name, "^([^%-]+)%-(.+)$")
    if splitName and splitRealm and realm == "" then
        name = splitName
        realm = splitRealm
    end

    local foundUnit = addon:FindUnitByName(name)
    if foundUnit then
        addon:QueueInspect(name, realm, { reason = "queued-manual" })
        local okLive = addon:QueueLiveInspectUnit(foundUnit, false)
        if okLive then
            addon:ProcessInspectQueue(true)
        end
    else
        Print("inspect failed: " .. tostring(name) .. " is not in your current target, party, or raid")
    end
end

function addon:BuildExportSummaryFromPayload(payload)
    if type(payload) ~= "table" then
        return nil
    end

    local score = payload.gearScore and tostring(payload.gearScore) or "N/A"
    local spec = Trim(payload.spec or "")
    local summary = payload.issueSummary or {}
    local missingEnchant = tonumber(summary.missingEnchant or 0) or 0
    local missingGems = tonumber(summary.missingGems or 0) or 0
    local pvpItems = tonumber(summary.pvpItems or 0) or 0
    local name = tostring(payload.name or "Unknown") .. "-" .. tostring(payload.realm or "Unknown")

    -- Only added when an MS was recorded, so summaries without one are unchanged.
    local mainSpec = Trim(payload.mainSpec or "")
    local mainSpecText = ""
    if mainSpec ~= "" then
        mainSpecText = ", MS: " .. mainSpec
    end

    return "Name: " .. name
        .. ", GearScore: " .. score
        .. ", Spec: " .. (spec ~= "" and spec or "?")
        .. mainSpecText
        .. ", Missing Enchants: " .. tostring(missingEnchant)
        .. ", Missing Gems: " .. tostring(missingGems)
        .. ", PvP Items: " .. tostring(pvpItems)
end

function addon:BuildExportSummary(entry)
    if not entry then
        return nil
    end

    local payload = addon:BuildStoredSummaryPayload(entry.key, entry.req, entry.result, entry.state, entry.statusReason)
    return addon:BuildExportSummaryFromPayload(payload)
end

local function RaidInspectorTryInsertLFMLink(link)
    local editBox = addon.ui and addon.ui.lfmMessageBox
    if editBox and editBox:IsShown() and editBox:HasFocus()
        and type(link) == "string" and link ~= "" then
        editBox:Insert(link)
        addon:SetLFMMessage(editBox:GetText() or "")
        return true
    end
    return false
end

function addon:InitLFMMessageLinkHook()
    if addon.lfmLinkHooked then
        return
    end

    -- Path 1: clicking an already-displayed hyperlink (e.g. one linked into chat).
    if type(ChatEdit_InsertLink) == "function" then
        local originalInsert = ChatEdit_InsertLink
        ChatEdit_InsertLink = function(link, ...)
            if RaidInspectorTryInsertLFMLink(link) then
                return true
            end
            return originalInsert(link, ...)
        end
    end

    -- Path 2: shift-clicking a link straight from a UI panel (Achievement frame,
    -- bags, spellbook...). These route through HandleModifiedItemClick, which
    -- normally only inserts when a chat edit box is active - so without this hook
    -- an achievement could not be linked directly into the LFM box.
    if type(HandleModifiedItemClick) == "function" then
        local originalHandle = HandleModifiedItemClick
        HandleModifiedItemClick = function(link, ...)
            if IsModifiedClick("CHATLINK") and RaidInspectorTryInsertLFMLink(link) then
                return true
            end
            return originalHandle(link, ...)
        end
    end

    addon.lfmLinkHooked = true
end

-- On this client, shift-clicking an achievement in the Achievement window routes
-- to the tracking toggle (you see "This achievement has already been completed")
-- instead of a chat-link insert. So when the LFM box is focused we intercept the
-- tracking toggle and insert the achievement link instead. Blizzard_AchievementUI
-- is load-on-demand, so this is (re)tried whenever that addon loads.
function addon:InitAchievementLinkHook()
    if addon.achievementLinkHooked then
        return
    end

    if type(AchievementButton_ToggleTracking) ~= "function" then
        return
    end

    local originalToggle = AchievementButton_ToggleTracking
    AchievementButton_ToggleTracking = function(id, ...)
        if id and type(GetAchievementLink) == "function" then
            local ok, link = pcall(GetAchievementLink, id)
            if ok and RaidInspectorTryInsertLFMLink(link) then
                return
            end
        end
        return originalToggle(id, ...)
    end

    addon.achievementLinkHooked = true
end

function addon:PostLFMMessage()
    local message = Trim(addon:GetLFMMessage())
    if message == "" then
        Print("lfm: message is empty")
        return 0, 0
    end

    local needSuffix = addon:BuildLFMNeedSuffix()
    if needSuffix ~= "" then
        message = message .. ", NEED: " .. needSuffix
    end

    local channels = addon:GetLFMChannels()
    local selectedCount = 0
    local baseTargets = {}

    if channels.yell then
        selectedCount = selectedCount + 1
        table.insert(baseTargets, {
            message = message,
            chatType = "YELL",
            label = "Yell",
        })
    end

    if channels.guild then
        selectedCount = selectedCount + 1
        if IsInGuild() then
            table.insert(baseTargets, {
                message = message,
                chatType = "GUILD",
                label = "Guild",
            })
        else
            Print("lfm: /guild selected, but you are not in a guild")
        end
    end

    if channels.general then
        selectedCount = selectedCount + 1
        local channelId, channelName = FindJoinedChannelByAlias(LFM_GENERAL_ALIASES)
        if channelId and channelId > 0 then
            table.insert(baseTargets, {
                message = message,
                chatType = "CHANNEL",
                channelId = channelId,
                label = channelName or "general",
            })
        else
            Print("lfm: /general channel is not joined")
        end
    end

    if channels.global then
        selectedCount = selectedCount + 1
        local channelId, channelName = FindJoinedChannelByAlias(LFM_GLOBAL_ALIASES)
        if channelId and channelId > 0 then
            table.insert(baseTargets, {
                message = message,
                chatType = "CHANNEL",
                channelId = channelId,
                label = channelName or "global",
            })
        else
            Print("lfm: /global channel is not joined")
        end
    end

    if selectedCount == 0 then
        Print("lfm: no channels selected (Yell/Guild/General/Global)")
        return 0, 0
    end

    if #baseTargets == 0 then
        Print("lfm: no selected channels are available right now")
        return selectedCount, 0
    end

    -- Replicate the per-channel posts once per requested repeat, so the whole
    -- broadcast is re-sent repeatCount times, each post spaced by the delay.
    local repeatCount = addon:GetLFMRepeatCount()
    local targets = {}
    local r
    for r = 1, repeatCount do
        local t
        for t = 1, #baseTargets do
            local src = baseTargets[t]
            targets[#targets + 1] = {
                message = src.message,
                chatType = src.chatType,
                channelId = src.channelId,
                label = src.label,
            }
        end
    end

    if addon.lfmPostQueue and #addon.lfmPostQueue > 0 then
        Print("lfm: replaced previous pending queue with latest message")
    end

    addon.lfmPostQueue = targets
    addon.lfmPostSentCount = 0
    addon.lfmPostSelectedCount = #targets
    addon.lfmPostNextAt = GetNow()
    local postDelaySeconds = addon:GetLFMPostDelaySeconds()

    Print("lfm: queued " .. tostring(#targets) .. " post(s) ("
        .. tostring(#baseTargets) .. " channel(s) x " .. tostring(repeatCount)
        .. " repeat) with " .. tostring(postDelaySeconds) .. "s spacing")

    addon:ProcessLFMPostQueue(true)
    return selectedCount, #targets
end

-- Pulls the live editbox values (delay, repeat, role table, message) into
-- saved state so a POST always uses exactly what is shown in the UI.
function addon:CommitLFMInputsFromUI()
    if not addon.ui then
        return
    end

    if addon.ui.lfmMessageBox then
        addon:SetLFMMessage(addon.ui.lfmMessageBox:GetText() or "")
    end
    if addon.ui.lfmDelayBox then
        addon:SetLFMPostDelaySeconds(addon.ui.lfmDelayBox:GetText())
    end
    if addon.ui.lfmRepeatBox then
        addon:SetLFMRepeatCount(addon.ui.lfmRepeatBox:GetText())
    end
    if addon.ui.lfmRoleRows then
        local i
        for i = 1, #addon.ui.lfmRoleRows do
            local entry = addon.ui.lfmRoleRows[i]
            if entry.countBox then
                addon:SetLFMRoleCount(entry.key, entry.countBox:GetText())
            end
            if entry.classBox then
                addon:SetLFMRoleClasses(entry.key, entry.classBox:GetText())
            end
        end
    end
end

function addon:SendSummaryMessage(message, whisperTarget)
    local chatMessage = EscapeChatMessage(message)
    local channels = addon:GetExportChannels()
    local attempted = 0
    local sent = 0

    if channels.raid then
        attempted = attempted + 1
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            SendChatMessage(chatMessage, "RAID")
            sent = sent + 1
        else
            Print("share: RAID checked, but you are not in a raid")
        end
    end

    if channels.say then
        attempted = attempted + 1
        SendChatMessage(chatMessage, "SAY")
        sent = sent + 1
    end

    if channels.whisper then
        attempted = attempted + 1
        local targetName = Trim(whisperTarget or "")
        if targetName ~= "" then
            SendChatMessage(chatMessage, "WHISPER", nil, targetName)
            sent = sent + 1
        else
            Print("share: WHISPER checked, but selected player name is missing")
        end
    end

    if channels.guild then
        attempted = attempted + 1
        if IsInGuild() then
            SendChatMessage(chatMessage, "GUILD")
            sent = sent + 1
        else
            Print("share: GUILD checked, but you are not in a guild")
        end
    end

    if channels.rw then
        attempted = attempted + 1
        local isLeader = (type(IsRaidLeader) == "function" and IsRaidLeader())
            or (type(IsRaidOfficer) == "function" and IsRaidOfficer())
        if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then
            Print("share: RAID WARNING checked, but you are not in a raid")
        elseif not isLeader then
            Print("share: RAID WARNING checked, but you are not raid leader/assistant")
        else
            SendChatMessage(chatMessage, "RAID_WARNING")
            sent = sent + 1
        end
    end

    if attempted == 0 then
        Print("share: no channels selected (Raid/Say/Whisper/Guild/RW)")
        return 0, 0, chatMessage
    end

    if sent == 0 then
        Print(chatMessage)
    end

    return attempted, sent, chatMessage
end

function addon:SaveReportSnapshot(arg)
    local entry, err = addon:ResolveOverviewEntry(arg)
    if not entry then
        Print(err)
        return nil
    end

    local snapshot = addon:StoreReportSnapshot(entry, "manual")
    if not snapshot then
        Print("could not save report snapshot")
        return nil
    end

    Print("saved report #" .. tostring(snapshot.id) .. ": " .. tostring(snapshot.name) .. "-" .. tostring(snapshot.realm))
    return snapshot
end

function addon:ExportSavedReport(arg)
    local snapshot, err = addon:FindSavedReport(arg)
    if not snapshot then
        Print(err)
        return
    end

    local message = addon:BuildExportSummaryFromPayload(snapshot.payload) or snapshot.message
    if not message then
        Print("saved report is empty")
        return
    end

    addon:SendSummaryMessage(message, snapshot.name)
end

function addon:ExportSummary(arg)
    local selected, err = addon:ResolveOverviewEntry(arg)
    if not selected then
        Print(err)
        return
    end

    local message = addon:BuildExportSummary(selected)
    if not message then
        Print("nothing to export")
        return
    end

    addon:StoreReportSnapshot(selected, "export")
    addon:SendSummaryMessage(message, selected and selected.req and selected.req.name)
end

function addon:PrintStatus()
    addon:PruneRaidScanHistory()
    local queued, ready, errorCount = addon:GetCounts()
    local fresh, stale = addon:GetFreshnessCounts(FRESHNESS_TTL_SECONDS)
    local playersWithIssues, totalIssues = addon:GetIssueTotals()
    local reports = addon:GetReportSnapshots()
    local savedReportFiles = addon:GetSavedReportFiles()
    local history = addon:GetRaidScanHistory()
    local livePending = addon.inspectQueue and #addon.inspectQueue or 0
    local liveActive = addon.inspectCurrent and (addon.inspectCurrent.name .. "-" .. addon.inspectCurrent.realm) or "-"

    Print("schema v" .. tostring(RaidInspectorDB.meta.schemaVersion))
    Print("requests: " .. tostring(#RaidInspectorDB.requests))
    Print("queued=" .. queued .. ", ready=" .. ready .. ", fresh=" .. fresh .. ", stale=" .. stale .. ", errors=" .. errorCount)
    Print("issues: total=" .. totalIssues .. ", playersWithIssues=" .. playersWithIssues)
    Print("overview mode: sort=" .. addon:GetSortMode() .. ", filter=" .. addon:GetFilterMode())
    Print("MS registering: " .. (addon:IsMSTrackingEnabled() and "ON" or "OFF")
        .. ", recorded=" .. tostring(addon:GetMainSpecCount()))
    Print("live inspect: pending=" .. tostring(livePending) .. ", active=" .. tostring(liveActive))
    Print("achievement compare: disabled")
    Print("saved reports=" .. tostring(#reports.items) .. ", raid scan history=" .. tostring(#history.scans))
    Print("detailed reports=" .. tostring(#savedReportFiles.items) .. ", activeSaved=" .. tostring(addon:GetSelectedSavedReportFile() ~= ""))

    local progress = addon:GetSnapshotProgress()
    if progress then
        Print("snapshot: fresh=" .. progress.ready .. "/" .. progress.total .. ", stale=" .. progress.stale .. ", missing=" .. progress.missing)
    end

    Print("mode: bridgeless live inspect + SavedVariables reports")
end

function addon:ClearQueue()
    local clearedMS = addon:GetMainSpecCount()

    RaidInspectorDB.requests = {}
    RaidInspectorDB.results = {}
    RaidInspectorDB.state.lastSnapshot = { at = 0, historyId = 0, members = {} }
    RaidInspectorDB.state.nextRequestId = 1
    RaidInspectorDB.reportFileQueue = { nextId = 1, items = {} }

    -- MS records survive rescans and relogs, but Clear is the explicit
    -- "wipe the list" action, so it takes them too.
    local tracking = addon:GetMSTracking()
    tracking.entries = {}
    tracking.nextSeq = 1

    addon.inspectQueue = {}
    addon.inspectQueuedKeys = {}
    addon.inspectCurrent = nil
    addon.inspectTickAccum = 0
    addon.inspectRetryAccum = 0
    addon.autoScanAccum = 0
    addon.autoScanRosterAccum = 0
    addon.autoScanRosterDirty = false
    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
    addon:SetSelectedKey("")
    if clearedMS > 0 then
        Print("queue + results cleared (" .. tostring(clearedMS) .. " MS records removed)")
    else
        Print("queue + results cleared")
    end
    addon:RefreshMainWindow()
end

function addon:RequestClearQueue()
    if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table" then
        addon:ClearQueue()
        return
    end

    StaticPopup_Hide("RAIDINSPECTOR_CONFIRM_CLEAR")
    StaticPopup_Show("RAIDINSPECTOR_CONFIRM_CLEAR")
end

if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs["RAIDINSPECTOR_CONFIRM_CLEAR"] = {
        text = "Clear queued requests, cached live-inspect results and recorded MS changes?",
        button1 = "Clear",
        button2 = CANCEL or "Cancel",
        OnAccept = function()
            addon:ClearQueue()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["RAIDINSPECTOR_CONFIRM_CLEAR_MS"] = {
        text = "Clear every recorded MS change?",
        button1 = "Clear MS",
        button2 = CANCEL or "Cancel",
        OnAccept = function()
            addon:ClearMainSpecRecords()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function addon:OnAddonLoaded(loadedName)
    -- Blizzard_AchievementUI is load-on-demand; hook it once it appears.
    if loadedName == "Blizzard_AchievementUI" then
        addon:InitAchievementLinkHook()
        return
    end

    if loadedName ~= addon.name then
        return
    end

    addon:InitDatabase()
    addon:InitInspectRuntime()
    addon:CreateMainWindow()
    addon:InitLFMMessageLinkHook()
end

function addon:OnPlayerLogin()
    addon:InitInspectRuntime()
    addon:InitLFMMessageLinkHook()
    if type(IsAddOnLoaded) == "function" and IsAddOnLoaded("Blizzard_AchievementUI") then
        addon:InitAchievementLinkHook()
    end
    Print("loaded (" .. addon.version .. ")")
    Print("type /ri help for commands")
    addon:RefreshMainWindow()
end

SLASH_RAIDINSPECTOR1 = "/ri"
SLASH_RAIDINSPECTOR2 = "/raidinspector"
SlashCmdList["RAIDINSPECTOR"] = function(message)
    SafeInvoke("slash", function()
        local raw = Trim(message or "")
        local command, args = string.match(raw, "^(%S+)%s*(.-)$")
        command = string.lower(command or "")
        args = args or ""

        if command == "help" then
            Print("commands:")
            Print("/ri - open main window (same as /ri show)")
            Print("/ri help - show this command list")
            Print("/ri show - open main window")
            Print("/ri hide - close main window")
            Print("/ri inspect <name> <realm> - inspect a matching target/party/raid unit")
            Print("/ri inspect <name-realm> - inspect a matching target/party/raid unit")
            Print("/ri inspecttarget - queue + live inspect current target")
            Print("/ri inspectraid - snapshot + live inspect current raid members")
            Print("/ri autoscan [on|off] - keep rescanning the raid automatically")
            Print("/ri ms [on|off] - start/stop recording \"MS <spec>\" lines from raid chat")
            Print("/ri ms list - print every recorded MS change")
            Print("/ri ms set <name> <spec> - set one player's MS by hand")
            Print("/ri ms share - post the MS list to the ticked Share channels")
            Print("/ri ms clear - wipe the recorded MS list (asks to confirm)")
            Print("/ri inspecttarget and /ri inspectraid also attempt in-game AP comparison (inspectable targets)")
            Print("/ri sort [recent|gs|issues|name|ms] - set or cycle sort")
            Print("/ri filter [all|snapshot|ready|queued|issues] - set or cycle filter")
            Print("/ri report - save a detailed roster report into SavedVariables")
            Print("/ri loadreport [latest|report-id] - load a saved report into the overview")
            Print("/ri share [name-realm] - short summary to selected chat channels")
            Print("/ri lfm - switch to the LFM tab")
            Print("/ri inspector - switch to the Inspector tab")
            Print("/ri post [message] - post LFM message to selected channels (uses delay + repeat)")
            Print("/ri cancel - cancel any pending LFM posts")
            Print("/ri savereport [name-realm] - save current or selected report snapshot")
            Print("/ri sharesaved [latest|id|name-realm] - share saved snapshot to chat")
            Print("/ri status - show queue summary")
            Print("/ri refreshstale [minutes] - queue refresh for stale results")
            Print("/ri clearqueue [confirm] - clear queue/results with confirmation")
            return
        end

        if command == "" or command == "show" then
            addon:ToggleWindow(true)
            return
        end

        if command == "hide" then
            addon:ToggleWindow(false)
            return
        end

        if command == "toggle" then
            addon:ToggleWindow()
            return
        end

        if command == "inspect" then
            addon:HandleInspectCommand(args)
            return
        end

        if command == "inspecttarget" then
            addon:QueueTarget()
            return
        end

        if command == "inspectraid" then
            addon:QueueRaidSnapshot()
            return
        end

        if command == "ms" then
            local rest = Trim(args)
            local sub, subArgs = string.match(rest, "^(%S*)%s*(.-)$")
            sub = string.lower(sub or "")

            if sub == "" or sub == "toggle" then
                addon:ToggleMSTracking()
            elseif sub == "on" or sub == "start" then
                addon:SetMSTrackingEnabled(true)
            elseif sub == "off" or sub == "stop" then
                addon:SetMSTrackingEnabled(false)
            elseif sub == "list" or sub == "status" then
                addon:PrintMainSpecRecords()
            elseif sub == "share" or sub == "report" then
                addon:ShareMainSpecChanges()
            elseif sub == "clear" then
                addon:RequestClearMainSpecRecords()
            elseif sub == "set" then
                local targetName, spec = string.match(Trim(subArgs), "^(%S+)%s+(.+)$")
                if not targetName or not spec then
                    Print("usage: /ri ms set <name> <spec>")
                else
                    local record = addon:RecordMainSpecChange(targetName, Trim(spec), "manual")
                    if record then
                        Print("MS set: " .. tostring(record.name) .. " = " .. tostring(record.spec))
                        addon:RefreshMainWindow()
                    else
                        Print("could not set MS for " .. tostring(targetName))
                    end
                end
            else
                Print("usage: /ri ms [on|off|list|set <name> <spec>|share|clear]")
            end
            return
        end

        if command == "autoscan" then
            local mode = string.lower(Trim(args))
            if mode == "on" or mode == "start" then
                addon:SetAutoScanEnabled(true)
            elseif mode == "off" or mode == "stop" then
                addon:SetAutoScanEnabled(false)
            elseif mode == "" then
                addon:ToggleAutoScan()
            else
                Print("usage: /ri autoscan [on|off]")
            end
            return
        end

        if command == "sync" or command == "forcesync" then
            Print("bridgeless mode: sync is disabled; use Target/Raid for live inspect")
            return
        end

        if command == "sort" then
            local mode = string.lower(Trim(args))
            if mode == "" then
                addon:CycleSortMode()
            elseif not addon:SetSortMode(mode) then
                Print("invalid sort mode. use: recent, gs, issues, name")
            end
            return
        end

        if command == "filter" then
            local mode = string.lower(Trim(args))
            if mode == "" then
                addon:CycleFilterMode()
            elseif not addon:SetFilterMode(mode) then
                Print("invalid filter mode. use: all, snapshot, ready, queued, issues")
            end
            return
        end

        if command == "savereport" then
            addon:SaveReportSnapshot(args)
            return
        end

        if command == "report" or command == "export" then
            addon:QueueDetailedReport()
            return
        end

        if command == "loadreport" then
            addon:LoadSavedReportFile(args)
            return
        end

        if command == "share" then
            addon:ExportSummary(args)
            return
        end

        if command == "lfm" then
            addon:SetActiveTab("lfm")
            addon:ToggleWindow(true)
            return
        end

        if command == "inspector" then
            addon:SetActiveTab("inspector")
            addon:ToggleWindow(true)
            return
        end

        if command == "post" then
            addon:CommitLFMInputsFromUI()
            if Trim(args or "") ~= "" then
                addon:SetLFMMessage(args)
            end
            addon:PostLFMMessage()
            addon:RefreshMainWindow()
            return
        end

        if command == "cancel" then
            addon:CancelLFMPostQueue()
            return
        end

        if command == "sharesaved" or command == "exportsaved" then
            addon:ExportSavedReport(args)
            return
        end

        if command == "status" then
            addon:PrintStatus()
            addon:RefreshMainWindow()
            return
        end

        if command == "refreshstale" then
            addon:QueueStaleRefresh(args)
            return
        end

        if command == "clearqueue" then
            local mode = string.lower(Trim(args or ""))
            if mode == "confirm" or mode == "force" or mode == "yes" then
                addon:ClearQueue()
            else
                addon:RequestClearQueue()
            end
            return
        end

        if command == "reload" then
            ReloadUI()
            return
        end

        Print("unknown command. use /ri help")
    end)
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("INSPECT_READY")
events:RegisterEvent("INSPECT_TALENT_READY")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
-- MS registering reads these; the handler no-ops while the toggle is off.
events:RegisterEvent("CHAT_MSG_RAID")
events:RegisterEvent("CHAT_MSG_RAID_LEADER")
events:RegisterEvent("CHAT_MSG_RAID_WARNING")
events:RegisterEvent("CHAT_MSG_PARTY")
events:RegisterEvent("CHAT_MSG_PARTY_LEADER")
events:SetScript("OnEvent", function(_, event, ...)
    local arg1, arg2, arg3, arg4 = ...
    SafeInvoke("event " .. tostring(event), function()
        if event == "ADDON_LOADED" then
            addon:OnAddonLoaded(arg1)
        elseif event == "PLAYER_LOGIN" then
            addon:OnPlayerLogin()
        elseif event == "INSPECT_READY" then
            addon:OnInspectReady(arg1)
        elseif event == "INSPECT_TALENT_READY" then
            addon:OnInspectTalentReady()
        elseif event == "CHAT_MSG_ADDON" then
            addon:OnCommReceived(arg1, arg2, arg3, arg4)
        elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
            addon:OnRosterChanged()
        elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER"
            or event == "CHAT_MSG_RAID_WARNING" or event == "CHAT_MSG_PARTY"
            or event == "CHAT_MSG_PARTY_LEADER" then
            addon:OnRaidChatMessage(event, arg1, arg2)
        end
    end)
end)
events:SetScript("OnUpdate", function(_, elapsed)
    SafeInvoke("onupdate", function()
        addon:OnUpdate(elapsed)
    end)
end)
