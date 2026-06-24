-- Generic AI Message Processor
-- Ported from Python core/ai_processor.py

local M = {}

local AIProcessorConfig = {}
AIProcessorConfig.__index = AIProcessorConfig

function AIProcessorConfig.new(opts)
    local self = setmetatable(opts or {}, AIProcessorConfig)
    self.system_prompt = self.system_prompt or nil
    self.max_retries = self.max_retries or nil
    self.timeout = self.timeout or nil
    return self
end

M.AIProcessorConfig = AIProcessorConfig

local AIProcessor = {}
AIProcessor.__index = AIProcessor

function AIProcessor.new(api_client, config)
    local self = setmetatable({}, AIProcessor)
    self.api_client = api_client
    self.config = config or {}
    return self
end

function AIProcessor:process_messages(messages, prompt, send_tools)
    send_tools = send_tools ~= false

    local all_messages = {}
    for _, msg in ipairs(messages) do
        table.insert(all_messages, msg)
    end

    table.insert(all_messages, {role = "user", content = prompt})

    local full_response = ""
    local log = require("utils.log")

    local function process_response()
        local response = self.api_client:send_request({
            messages = all_messages,
            send_tools = send_tools
        })

        full_response = response.content or ""
    end

    local ok, err = pcall(process_response)
    if not ok then
        log.warn("AI Processor failed: " .. tostring(err))
        error("AI Processor failed: " .. tostring(err))
    end

    return full_response:gsub("^%s+", ""):gsub("%s+$", "")
end

function AIProcessor:process(messages, prompt)
    return self:process_messages(messages, prompt, true)
end

M.AIProcessor = AIProcessor
M.new = AIProcessor.new

return M
