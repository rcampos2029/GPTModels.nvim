local cmd = require("gptmodels.cmd")

local _wca_api_call = ""
local generate_wca_api_call = function()
  if _wca_api_call == "" then
    local data_path = vim.fn.stdpath("data") .. "/wca_api_call.txt"
    local file = io.open(data_path, "r")
    if file then
      _wca_api_call = file:read("*a"):gsub("\n", "")
      file:close()
    else
      vim.notify(data_path .. " must contain the WCA API call.", vim.log.levels.ERROR)
    end
  end
  return _wca_api_call
end

local generate_access_token = function()
  local data_path = vim.fn.stdpath("data") .. "/wca_access_token.json"
  -- Utilities {
  local function save_data(data)
    local file = io.open(data_path, "w")
    if file then
      file:write(vim.json.encode(data))
      file:close()
    end
  end

  local function load_data()
    local file = io.open(data_path, "r")
    if file then
      local content = file:read("*a")
      file:close()
      return vim.json.decode(content)
    end
    return {}
  end
  -- Utilities }

  local access_data = load_data()

  local access_expired = function(data)
    if data.expiration == nil then
      return true
    end
    local now = os.time()
    local five_minutes_before = data.expiration - 300
    if now > five_minutes_before then
      return true
    end
    return false
  end

  -- https://cloud.ibm.com/docs/account?topic=account-iamtoken_from_apikey
  if access_expired(access_data) then
    cmd.exec({
      sync = true,
      cmd = "curl",
      args = {
        "https://iam.cloud.ibm.com/identity/token",
        "-H",
        "Content-Type: application/x-www-form-urlencoded",
        "-d",
        "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=" .. (os.getenv("WCA_API_KEY") or ""),
      },
      onread = vim.schedule_wrap(function(_, response)
        if not response then
          return
        end
        access_data = vim.json.decode(response)
        save_data(access_data)
      end),
      onexit = vim.schedule_wrap(function() end),
    })
  end

  return access_data
end

local base64_encode = function(x)
  return vim.fn.system("base64", x):gsub("\n", "")
end

local format_user_messages = function(llm_data)
  return base64_encode(vim.json.encode({ message_payload = { messages = llm_data.messages } }))
end

---@type LlmProvider
local provider = {
  name = "wca",

  -- TODO actually fetch models.
  -- There is no api available for this atm.
  fetch_models = function(cb)
    cb(nil, { "wca_model" })
    return {}
  end,

  generate = function(args)
    -- Like openai, wca expects only messages.
    ---@type LlmMessage[]
    ---@diagnostic disable-next-line: inject-field
    args.llm.messages = {
      { role = "user", content = args.llm.prompt },
    }

    for _, system_string in ipairs(args.llm.system or {}) do
      table.insert(args.llm.messages, {
        role = "system",
        content = system_string,
      })
    end

    args.llm.prompt = nil
    args.llm.system = nil

    local access_token = generate_access_token()

    -- curl --request POST \
    --   --url <REDACTED> \
    --   --header 'Authorization: Bearer <access_token>' \
    --   --header 'Request-ID: 9bdb1d8c-3a6b-428c-a9a0-204c5164ea1a' \
    --   --header 'content-type: multipart/form-data' \
    --   --form message="$(cat rest_api/simple_chat.json | base64)"
    local job = cmd.exec({
      cmd = "curl",
      args = {
        "--request",
        "POST",
        "--url",
        generate_wca_api_call(),
        "-H",
        "Content-Type: multipart/form-data",
        "-H",
        "Authorization: Bearer " .. access_token.access_token,
        "--no-buffer",
        "--no-progress-meter",
        "--form",
        "message=" .. format_user_messages(args.llm),
      },
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

        args.on_read(nil, decoded_data.response.message.content)
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
    local access_token = generate_access_token()
    -- curl --request POST \
    --   --url <REDACTED> \
    --   --header 'Authorization: Bearer <access_token>' \
    --   --header 'Request-ID: 9bdb1d8c-3a6b-428c-a9a0-204c5164ea1a' \
    --   --header 'content-type: multipart/form-data' \
    --   --form message="$(cat rest_api/simple_chat.json | base64)"
    local job = cmd.exec({
      cmd = "curl",
      args = {
        "--request",
        "POST",
        "--url",
        generate_wca_api_call(),
        "-H",
        "Content-Type: multipart/form-data",
        "-H",
        "Authorization: Bearer " .. access_token.access_token,
        "--no-buffer",
        "--no-progress-meter",
        "--form",
        "message=" .. format_user_messages(args.llm),
      },
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
          role = decoded_data.response.message.role,
          content = decoded_data.response.message.content,
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
