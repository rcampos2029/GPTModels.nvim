local cmd = require("gptmodels.cmd")
local util = require("gptmodels.util")

local _ENVVARS = {
    api_key = "GEMINI_API_KEY"
}

local _HEADERS = {
    api_key = "x-goog-api-key: " .. (os.getenv(_ENVVARS.api_key) or ""),
}

local _ENDPOINTS = {
    message = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
}

local helpers = {
    generate_message_args = function(llm_data)
        -- New list (table) to store messages in Gemini expected format.
        local contents = {}
        for _, msg in ipairs(llm_data.messages) do
            table.insert(contents, { parts = { { text = msg.content } }, role = msg.role })
        end

        return {
            _ENDPOINTS.message,
            "--no-progress-meter",
            "-H", "Content-Type: application/json",
            "-H", _HEADERS.api_key,
            "-d", vim.json.encode({
            contents = contents,
        }),
        }
    end,
    content_from_parts = function(parts)
        local content = ""
        for _, part in ipairs(parts) do
            content = content .. part.text
        end
        return content
    end,

}

---@type LlmProvider
local provider = {
    name = "google",
    check_deps = function()
        if not util.has_env_var(_ENVVARS.api_key) then
            return {
                INFO = "GPTModels.nvim is missing optional " .. _ENVVARS.api_key .. " env var. " ..
                    "Gemini models will be unavailable.",
            }
        end
    end,
    fetch_models = function(cb)
        if util.has_env_var(_ENVVARS.api_key) then
            cb(nil, { "gemini-2.5-flash" })
        end
        return { handle = nil }
    end,

    generate = function(args)
        ---@type LlmMessage[]
        ---@diagnostic disable-next-line: inject-field
        args.llm.messages = {
            { role = "user", content = args.llm.prompt },
        }

        for _, system_string in ipairs(args.llm.system or {}) do
            table.insert(args.llm.messages, {
                role = "model",
                content = system_string,
            })
        end

        local job = cmd.exec({
            cmd = "curl",
            args = helpers.generate_message_args(args.llm),
            onread = vim.schedule_wrap(function(err, response)
                if err then
                    return args.on_read(err, nil)
                end
                if not response then
                    return
                end

                local status_ok, decoded_data = pcall(vim.fn.json_decode, response)
                if not status_ok or not decoded_data then
                    -- TODO How to deal with errors?
                    vim.notify("error occurred: " .. response, vim.log.levels.ERROR)
                    return
                end

                args.on_read(nil, helpers.content_from_parts(decoded_data.candidates[1].content.parts))
            end),

            -- TODO Test that this doesn't throw when on_end isn't passed in
            onexit = vim.schedule_wrap(function()
                if args.on_end then
                    args.on_end()
                end
            end),
        })
        return job
    end,

    chat = function(args)
        local job = cmd.exec({
            cmd = "curl",
            args = helpers.generate_message_args(args.llm),
            onread = vim.schedule_wrap(function(err, response)
                if err then
                    return args.on_read(err, nil)
                end
                if not response then
                    return
                end

                local status_ok, decoded_data = pcall(vim.fn.json_decode, response)
                if not status_ok or not decoded_data then
                    vim.notify("error occurred: " .. response, vim.log.levels.ERROR)
                    return
                end
                args.on_read(nil, {
                    role = decoded_data.candidates[1].content.role,
                    content = helpers.content_from_parts(decoded_data.candidates[1].content.parts),
                })
            end),

            -- TODO Test that this doesn't throw when on_end isn't passed in
            onexit = vim.schedule_wrap(function()
                if args.on_end then
                    args.on_end()
                end
            end),
        })
        return job
    end,
}

return provider
