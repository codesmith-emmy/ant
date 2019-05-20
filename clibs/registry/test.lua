package.cpath = package.cpath ..";../?.dll"

local fs = require "filesystem.cpp"
local registry = require "registry"
local reg = registry.open [[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts]]

local FONTS = fs.path(os.getenv "SystemRoot") / "Fonts"
print("Fonts folder:", FONTS)

for name, file in registry.values(reg) do
    local font = fs.path(file)
    if not font:is_absolute() then
        font = fs.absolute(font, FONTS)
    end
    assert(fs.exists(font))
    print(name, font)
end
print "ok"
