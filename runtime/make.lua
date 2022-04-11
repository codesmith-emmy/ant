local lm = require "luamake"
local fs = require "bee.filesystem"

local runtime = false

local RuntimeBacklist = {
    filedialog = true,
    imgui = true,
    audio = true,
}

local EditorBacklist = {
    firmware = true,
    audio = (lm.os == "windows" and lm.compiler == "gcc") or (lm.os ~= "windows"),
    effeskeer = true,
}

local RuntimeModules = {}
local EditorModules = {}

local function checkAddModule(name, makefile)
    if not RuntimeBacklist[name] or not EditorBacklist[name] then
        lm:import(makefile)
    end
    if lm:has(name) then
        if not RuntimeBacklist[name] then
            RuntimeModules[#RuntimeModules + 1] = name
        end
        if not EditorBacklist[name] then
            EditorModules[#EditorModules + 1] = name
        end
    end
end

for path in fs.pairs(fs.path(lm.workdir) / "../clibs") do
    if fs.exists(path / "make.lua") then
        local name = path:stem():string()
        local makefile = ("../clibs/%s/make.lua"):format(name)
        checkAddModule(name, makefile)
    end
end

checkAddModule("efk", "../packages/efk/make.lua")

lm:copy "copy_mainlua" {
    input = "common/main.lua",
    output = "../"..lm.bindir,
}

lm:source_set "ant_common" {
    deps = "lua_source",
    includes = {
        "../clibs/lua",
        "../3rd/bgfx/include",
        "../3rd/bx/include",
        "common"
    },
    sources = {
        "common/runtime.cpp",
        "common/progdir.cpp",
    },
    windows = {
        sources = "windows/main.cpp",
    },
    macos = {
        sources = "osx/main.cpp",
    },
    ios = {
        includes = "../../clibs/window/ios",
        sources = {
            "common/ios/main.mm",
            "common/ios/ios_error.mm",
        }
    }
}

lm:source_set "ant_openlibs" {
    includes = "../clibs/lua",
    sources = "common/ant_openlibs.c",
}

lm:source_set "ant_links" {
    windows = {
        links = {
            "shlwapi",
            "user32",
            "gdi32",
            "shell32",
            "ole32",
            "oleaut32",
            "wbemuuid",
            "winmm",
            "ws2_32",
            "imm32",
            "advapi32",
            "version",
        }
    },
    macos = {
        frameworks = {
            "Carbon",
            "IOKit",
            "Foundation",
            "Metal",
            "QuartzCore",
            "Cocoa"
        }
    },
    ios = {
        frameworks = {
            "CoreTelephony",
            "SystemConfiguration",
            "Foundation",
            "CoreText",
            "UIKit",
            "Metal",
            "QuartzCore",
        },
        ldflags = {
            "-fembed-bitcode",
            "-fobjc-arc"
        }
    }
}

lm:source_set "ant_runtime" {
    deps = {
        "ant_common",
        RuntimeModules,
    },
    includes = {
        "../clibs/lua",
        "../3rd/bgfx/include",
        "../3rd/bx/include",
    },
    defines = "ANT_RUNTIME",
    sources = "common/modules.c",
}

lm:source_set "ant_editor" {
    deps = {
        "ant_common",
        EditorModules,
    },
    includes = {
        "../clibs/lua",
        "../3rd/bgfx/include",
        "../3rd/bx/include",
    },
    sources = "common/modules.c",
}

lm:exe "lua" {
    deps = {
        "ant_editor",
        "ant_openlibs",
        "bgfx-lib",
        "ant_links",
        "copy_mainlua"
    }
}

lm:exe "ant" {
    deps = {
        "ant_runtime",
        "ant_openlibs",
        "bgfx-lib",
        "ant_links",
        "copy_mainlua"
    }
}

lm:phony "editor" {
    deps = "lua"
}

lm:phony "runtime" {
    deps = "ant"
}