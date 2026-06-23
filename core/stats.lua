-- Stats tracking for Luna

local M = {}

-- Class-style alias for 1-1 parity with Python's Stats class
M.Stats = M

function M.new()
    local self = {
        api_requests = 0,
        api_success = 0,
        api_errors = 0,
        api_time_spent = 0,
        last_api_time = 0,
        messages_sent = 0,
        tokens_processed = 0,
        compactions = 0,
        prompt_tokens = 0,
        completion_tokens = 0,
        current_prompt_size = 0,
        current_prompt_size_estimated = false,
        last_user_prompt = "",
        usage_infos = {},
        user_interactions = 0,
        last_model = nil,
    }
    
    function self:increment_api_requests()
        self.api_requests = self.api_requests + 1
    end
    
    function self:increment_api_success()
        self.api_success = self.api_success + 1
    end
    
    function self:increment_api_errors()
        self.api_errors = self.api_errors + 1
    end
    
    function self:add_api_time(time_val)
        self.api_time_spent = self.api_time_spent + time_val
        self.last_api_time = time_val
    end
    
    function self:increment_messages_sent()
        self.messages_sent = self.messages_sent + 1
    end
    
    function self:add_tokens(prompt_tokens, completion_tokens)
        if prompt_tokens then
            self.prompt_tokens = self.prompt_tokens + prompt_tokens
        end
        if completion_tokens then
            self.completion_tokens = self.completion_tokens + completion_tokens
        end
        self.tokens_processed = self.prompt_tokens + self.completion_tokens
    end
    
    function self:increment_compactions()
        self.compactions = self.compactions + 1
    end
    
    function self:set_last_user_prompt(prompt)
        self.last_user_prompt = prompt or ""
    end
    
    function self:set_last_model(model)
        self.last_model = model
    end
    
    function self:set_current_prompt_size(size)
        self.current_prompt_size = size or 0
    end
    
    function self:mark_prompt_size_estimated()
        self.current_prompt_size_estimated = true
    end
    
    function self:add_usage_info(usage_info)
        if usage_info then
            table.insert(self.usage_infos, usage_info)
        end
    end
    
    function self:increment_user_interactions()
        self.user_interactions = self.user_interactions + 1
    end
    
    function self:add_prompt_tokens(count)
        if count then
            self.prompt_tokens = self.prompt_tokens + count
            self.tokens_processed = self.prompt_tokens + self.completion_tokens
        end
    end
    
    function self:add_completion_tokens(count)
        if count then
            self.completion_tokens = self.completion_tokens + count
            self.tokens_processed = self.prompt_tokens + self.completion_tokens
        end
    end

    function self:print_stats()
        local log = require("utils.log")
        log.info("=== Stats ===")
        log.info("API requests: " .. tostring(self.api_requests))
        log.info("API success: " .. tostring(self.api_success))
        log.info("API errors: " .. tostring(self.api_errors))
        log.info("API time: " .. tostring(self.api_time_spent) .. "s")
        log.info("Messages sent: " .. tostring(self.messages_sent))
        log.info("Tokens processed: " .. tostring(self.tokens_processed))
        log.info("  prompt: " .. tostring(self.prompt_tokens))
        log.info("  completion: " .. tostring(self.completion_tokens))
        log.info("Compactions: " .. tostring(self.compactions))
        log.info("User interactions: " .. tostring(self.user_interactions))
        log.info("Current prompt size: " .. tostring(self.current_prompt_size))
    end

    function self:reset()
        self.api_requests = 0
        self.api_success = 0
        self.api_errors = 0
        self.api_time_spent = 0
        self.last_api_time = 0
        self.messages_sent = 0
        self.tokens_processed = 0
        self.compactions = 0
        self.prompt_tokens = 0
        self.completion_tokens = 0
        self.current_prompt_size = 0
        self.current_prompt_size_estimated = false
        self.last_user_prompt = ""
        self.usage_infos = {}
        self.user_interactions = 0
    end

    return self
end

return M
