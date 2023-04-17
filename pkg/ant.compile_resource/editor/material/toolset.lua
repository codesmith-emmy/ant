local shader = require "editor.material.shader"

local lfs = require "filesystem.local"
local toolset = {}

local stage_types = {
	fs = "fragment",
	vs = "vertex",
	cs = "compute",
}

local shader_options = {
	direct3d9 = {
		vs = "s_3_0",
		fs = "s_3_0",
	},
	direct3d11 = {
		vs = "s_5_0",
		fs = "s_5_0",
		cs = "s_5_0",
	},
	direct3d12 = {
		vs = "s_5_0",
		fs = "s_5_0",
		cs = "s_5_0",
	},
	opengl = {
		vs = "120",
		fs = "120",
		cs = "430",
	},
	metal = {
		vs = "metal",
		fs = "metal",
		cs = "metal",
	},
	vulkan = {
		vs = "spirv",
		fs = "spirv",
		cs = "spirv",
	},
}

local function get_shader_option(plat, renderer, stage)
	if renderer == "noop" then
		local noop_redirect = {
			windows = "direct3d11",
			mac = "metal",
			ios = "metal",
			android = "vulkan",
		}
		renderer = noop_redirect[plat]
	end

	return shader_options[renderer][stage]
end

function toolset.compile(config)
	local commands = {
		"--platform", config.platform,
		"--type", stage_types[config.stage],
		"-p", get_shader_option(config.platform, config.renderer, config.stage),
		"-f", config.input:string(),
	}

	if config.includes then
		for _, p in ipairs(config.includes) do
			if not lfs.exists(p) then
				error(string.format("include path : %s, but not exist!", p))
			end
			assert(p:is_absolute(), p:string())
			commands[#commands+1] = "-i"
			commands[#commands+1] = p:string()
		end
	end

	if config.macros then
		local t = {}
		for _, m in ipairs(config.macros) do
			t[#t+1] = m
		end
		if #t > 0 then
			local defines = table.concat(t, ';')
			commands[#commands+1] = "--define"
			commands[#commands+1] = defines
		end
	end

	local level = config.optimizelevel
	if not level then
		if config.renderer:match("direct3d") then
			level = config.stage == "cs" and 1 or 3
		end
	end

	if config.debug then
		commands[#commands+1] = "--debug"
	else
		if level then
			commands[#commands+1] = "-O"
			commands[#commands+1] = tostring(level)
		end
	end

	if config.varying_path then
        commands[#commands+1] = "--varyingdef"
        commands[#commands+1] = tostring(config.varying_path)
    end
	return shader(commands, config.input, config.output)
end

return toolset
