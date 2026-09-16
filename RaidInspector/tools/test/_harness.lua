-- Shared preamble for *_test.lua: loads the stub and the real addon files in
-- .toc order, boots the addon, and provides check()/finish().
dofile(STUB_PATH)

local i
for i = 1, #ADDON_FILES do
    local path = ADDON_DIR .. "/" .. ADDON_FILES[i]
    local ok, err = pcall(dofile, path)
    if not ok then
        print("LOAD FAILED: " .. tostring(err))
        os.exit(1)
    end
end

addon = _G.RaidInspector or _G.RaidInspectorAddon
if type(addon) ~= "table" then
    print("no addon table exposed")
    os.exit(1)
end

if addon.OnAddonLoaded then pcall(addon.OnAddonLoaded, addon, "RaidInspector") end
if addon.OnPlayerLogin then pcall(addon.OnPlayerLogin, addon) end

local pass, fail = 0, 0

function check(name, cond, extra)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print("FAIL: " .. name .. (extra ~= nil and ("  [" .. tostring(extra) .. "]") or ""))
    end
end

function finish()
    print(string.format("%d checks, %d failures", pass + fail, fail))
    if fail > 0 then os.exit(1) end
end
