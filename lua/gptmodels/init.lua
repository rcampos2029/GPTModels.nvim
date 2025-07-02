local util = require("gptmodels.util")
local code_window = require("gptmodels.windows.code")
local chat_window = require("gptmodels.windows.chat")

local anthropic = require("gptmodels.providers.anthropic")
local google = require("gptmodels.providers.google")

local M = {}

-- you can define your setup function here. Usually configurations can be merged, accepting outside params and
-- you can also put some validation here for those.
local config = {}
M.config = config
M.setup = function(args)
	M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

local providers = { "ollama", "openai", "wca", anthropic.name, google.name }

---@param opts { visual_mode: boolean }
---@see file plugin/init.lua
M.code = function(opts)
	if opts.visual_mode then
		local selection = util.get_visual_selection()
		code_window.build_and_mount(providers, selection)
	else
		code_window.build_and_mount(providers)
	end
end

---@param opts { visual_mode: boolean }
---@see file plugin/init.lua
M.chat = function(opts)
	if opts.visual_mode then
		local selection = util.get_visual_selection()
		chat_window.build_and_mount(providers, selection)
	else
		chat_window.build_and_mount(providers)
	end
end

return M
