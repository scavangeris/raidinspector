-- Item tooltips open next to the mouse, not at the far end of a wide row.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

local anchors = {}
GameTooltip.SetOwner = function(self, owner, anchor) table.insert(anchors, anchor) end

-- Gear list row.
local row = { data = { item = { itemId = 50412, name = "Legguards of Lost Hope", ilvl = 277 }, slotKey = "legs" } }
anchors = {}
addon:ShowDetailRowTooltip(row)
check("gear row tooltip opens at the cursor", anchors[1] == "ANCHOR_CURSOR", anchors[1])

-- BIS LIST item button.
anchors = {}
addon:ShowBiSItemTooltip({ item = { id = 50640, name = "Broken Ram Skull Helm", ilvl = 277 } })
check("BIS item tooltip opens at the cursor", anchors[1] == "ANCHOR_CURSOR", anchors[1])

finish()
