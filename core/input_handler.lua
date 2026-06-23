-- Input Handler for Luna
-- Uses FFI readline for history and completion

local config = require("core.config")
local log = require("utils.log")
local prompt_history = require("core.prompt_history")

local InputHandler = {}
InputHandler.__index = InputHandler

-- FFI readline
local ffi_loaded = false
local rl = nil
local ffi = nil

-- Try to initialize FFI readline at module load
pcall(function()
    ffi = require("ffi")
    if ffi then
        ffi.cdef[[
            void *malloc(size_t size);
            void free(void *);
            char *readline(const char *prompt);
            void add_history(const char *line);
            void using_history(void);
            
            // completion function types
            typedef char **rl_completion_func_t(const char *, int, int);
            typedef char *rl_compentry_func_t(const char *, int);
            
            // completion matching
            char **rl_completion_matches(const char *, rl_compentry_func_t *);
            
            // completion function pointer
            rl_completion_func_t *rl_attempted_completion_function;
            int rl_attempted_completion_over;
            
            // word delimiters
            char *rl_completer_word_break_characters;
            
            // line buffer
            char *rl_line_buffer;
        ]]
        rl = ffi.load("readline")
        rl.using_history()
        
        -- Remove @ from word delimiters so @@snippet completion works
        local delim_ptr = rl.rl_completer_word_break_characters
        if delim_ptr ~= nil then
            -- Default delimiters include @, we remove it
            local new_delims = " \t\n\"\\'`$><=;|&{("
            ffi.copy(delim_ptr, new_delims)
        end
        
        ffi_loaded = true
    end
end)

-- Expose FFI state for debugging
InputHandler.ffi_loaded = ffi_loaded
InputHandler.rl = rl

-- Module-level reference for completion function
local _current_handler = nil

function InputHandler.new(context_bar, stats, message_history)
    local self = setmetatable({}, InputHandler)
    self.history = {}
    self.context_bar = context_bar
    self.stats = stats
    self.message_history = message_history
    self.is_interactive = true
    self.completers = {}
    
    -- Store reference for completion function
    _current_handler = self
    
    -- Set up readline completion if FFI is available
    if ffi_loaded and rl then
        self:_setup_readline_completion()
    end
    
    -- Load history from file
    self:_load_prompt_history()
    
    return self
end

-- Setup readline completion
function InputHandler:_setup_readline_completion()
    local handler = self
    
    rl.rl_attempted_completion_function = function(word, startpos, endpos)
        local strword = ffi.string(word)
        
        -- If word doesn't start with @@, check if there's @@ before cursor
        -- (readline might split on @ delimiter)
        if not strword:match("^@@") and startpos >= 1 then
            local line = ffi.string(rl.rl_line_buffer)
            local before_cursor = line:sub(1, endpos)
            -- Find last @@ in text before cursor
            local at_pos = before_cursor:match(".*()@@")  -- position where @@ starts
            if at_pos then
                local after_at = before_cursor:sub(at_pos + 2)  -- +2 to skip past @@
                strword = "@@" .. after_at
            end
        end
        
        -- Build all matches from completers (generator pattern)
        local all_matches = {}
        
        for _, completer in ipairs(handler.completers) do
            local state = 0
            while true do
                local ok, result = pcall(completer, strword, state)
                if not ok or result == nil then
                    break
                end
                if type(result) == "string" and result ~= "" then
                    table.insert(all_matches, result)
                elseif type(result) == "table" then
                    for _, match in ipairs(result) do
                        if match and match ~= "" then
                            table.insert(all_matches, match)
                        end
                    end
                    break
                else
                    break
                end
                state = state + 1
            end
        end
        
        if #all_matches == 0 then
            rl.rl_attempted_completion_over = 1
            return nil
        end
        
        -- Allocate C strings for all matches
        local c_matches = {}
        for _, match in ipairs(all_matches) do
            local buf = ffi.C.malloc(#match + 1)
            ffi.copy(buf, match)
            table.insert(c_matches, buf)
        end
        
        -- Return generator that returns one match at a time via closure
        local idx = 0
        rl.rl_attempted_completion_over = 1
        return rl.rl_completion_matches(word, function(text, state)
            if state < #c_matches then
                return c_matches[state + 1]
            end
            return nil
        end)
    end
end

function InputHandler:get_user_input()
    -- Check context bar and stats availability
    if self.context_bar and self.stats and self.message_history then
        self.context_bar:print_context_bar_for_user(self.stats, self.message_history)
    end
    
    -- Clear last API time before new user input
    if self.stats then
        self.stats.last_api_time = 0
    end
    
    local line
    if ffi_loaded and rl then
        -- Use readline with history
        local line_ptr = rl.readline("> ")
        if line_ptr ~= nil then
            line = ffi.string(line_ptr)
            -- Add to history
            rl.add_history(line)
        else
            line = nil
        end
    else
        -- Fallback to simple io.read
        io.stdout:write("> ")
        io.stdout:flush()
        line = io.stdin:read()
    end
    
    if line == nil then
        return ""
    end
    
    -- Trim
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Save to history
    if line ~= "" then
        self:_save_prompt(line)
    end
    
    -- Reset Ctrl+C counter after successful user input
    if line and line ~= "" and _G.reset_ctrl_c_count then
        _G.reset_ctrl_c_count()
    end
    
    return line
end

function InputHandler:close()
    -- Cleanup if needed
end

-- Register a tab completer function
function InputHandler:register_completer(completer)
    if type(completer) == "function" then
        table.insert(self.completers, completer)
    end
end

-- Get completion candidates for current input
function InputHandler:_completer(text)
    local candidates = {}
    for _, fn in ipairs(self.completers) do
        local ok, result = pcall(fn, text)
        if ok and type(result) == "table" then
            for _, c in ipairs(result) do
                table.insert(candidates, c)
            end
        end
    end
    return candidates
end

-- Load prompt history from .aicoder/history via prompt_history module
function InputHandler:_load_prompt_history()
    local entries = prompt_history.read_history()
    self.history = {}
    for _, entry in ipairs(entries) do
        local prompt = entry.prompt
        if not prompt:match("^/") then
            table.insert(self.history, prompt)
            -- Add to readline history
            if ffi_loaded and rl then
                rl.add_history(prompt)
            end
        end
    end
end

-- Save a prompt to history
function InputHandler:_save_prompt(prompt)
    prompt_history.save_prompt(prompt)
end

-- Handle SIGINT (Ctrl-C) - reset state cleanly
function InputHandler:handle_sigint()
    if self.context_bar then
        self.context_bar:reset()
    end
    io.stdout:write("\n")
    io.stdout:flush()
end

return InputHandler
