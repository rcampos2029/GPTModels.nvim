local cmd = require("gptmodels.cmd")

local _ENVVARS = {
    api_key = "ANTHROPIC_API_KEY"
}

local _HEADERS = {
    api_key           = "x-api-key: " .. os.getenv(_ENVVARS.api_key),
    anthropic_version = "anthropic-version: 2023-06-01",
}

local _ENDPOINTS = {
    model   = "https://api.anthropic.com/v1/models",
    message = "https://api.anthropic.com/v1/messages",
}

local _MODEL_PARAMETERS = {
    temperature = 1,
    max_tokens  = 20000,
}

local list_model_args = {
    _ENDPOINTS.model,
    "-H", _HEADERS.api_key,
    "-H", _HEADERS.anthropic_version,
}

local helpers = {
    generate_message_args = function(llm_data)
        return {
            _ENDPOINTS.message,
            "--no-progress-meter",
            "-H", "Content-Type: application/json",
            "-H", _HEADERS.api_key,
            "-H", _HEADERS.anthropic_version,
            "-d", vim.json.encode({
            model = llm_data.model,
            temperature = _MODEL_PARAMETERS.temperature,
            max_tokens = _MODEL_PARAMETERS.max_tokens,
            messages = llm_data.messages,
        }),
        }
    end,
}

---@type LlmProvider
local provider = {
    name = "anthropic",

    fetch_models = function(cb)
        local response_aggregate = ""
        local job = cmd.exec({
            cmd = "curl",
            args = list_model_args,
            ---@param err string | nil
            ---@param json_response string | nil
            onread = vim.schedule_wrap(function(err, json_response)
                if err then
                    return cb(err)
                end
                if not json_response then
                    return
                end
                response_aggregate = response_aggregate .. json_response
            end),
            onexit = vim.schedule_wrap(function()
                ---@type boolean, nil | { data: nil | { id: string }[], error: nil | { message: string } }
                local status_ok, response = pcall(vim.fn.json_decode, response_aggregate)

                -- Failed fetches
                if not response or not status_ok then
                    return cb("error retrieving openai models")
                end

                -- Server error
                if response.error then
                    return cb(response.error.message)
                end

                ---@type string[]
                local models = {}

                for _, model in ipairs(response.data) do
                    table.insert(models, model.id)
                end

                return cb(nil, models)
            end),
        })

        return job
    end,

    generate = function(args)
        ---@type LlmMessage[]
        ---@diagnostic disable-next-line: inject-field
        args.llm.messages = {
            { role = "user", content = args.llm.prompt },
        }

        for _, system_string in ipairs(args.llm.system or {}) do
            table.insert(args.llm.messages, {
                role = "assistant",
                -- Note: a period is added as this provider does not allow assistant prompts to end in whitespace
                content = system_string .. ".",
            })
        end

        args.llm.prompt = nil
        args.llm.system = nil

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

                args.on_read(nil, decoded_data.content[1].text)
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
                    role = decoded_data.role,
                    content = decoded_data.content[1].text,
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
