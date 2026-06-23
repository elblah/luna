-- Markdown colorizer for AI output
-- Headers: bold red
-- Bold (* ** _): bold green
-- Code (`): green

local config = require("core.config")

local MarkdownColorizer = {}
MarkdownColorizer.__index = MarkdownColorizer

function MarkdownColorizer.new()
    local self = setmetatable({}, MarkdownColorizer)
    self:reset_state()
    return self
end

function MarkdownColorizer:reset_state()
    self._in_code = false
    self._code_tick_count = 0
    self._in_star = false
    self._star_count = 0
    self._in_bold = false
    self._at_line_start = true
    self._consecutive_count = 0
    self._can_be_bold = false
end

function MarkdownColorizer:print_with_colorization(content)
    if not content or content == "" then
        return content
    end

    local result = {}
    local colors = config.colors
    local i = 1
    local len = #content

    while i <= len do
        local char = content:sub(i, i)

        -- Count consecutive asterisks
        if char == "*" then
            self._consecutive_count = self._consecutive_count + 1
            if self._consecutive_count == 2 then
                self._can_be_bold = true
            elseif self._consecutive_count > 2 then
                self._can_be_bold = false
            end
        else
            self._consecutive_count = 0
        end

        -- Handle newlines
        if char == "\n" then
            self._at_line_start = true
            if self._in_code then
                table.insert(result, colors.reset)
                self._in_code = false
            end
            if self._in_star then
                table.insert(result, colors.reset)
                self._in_star = false
                self._star_count = 0
            end
            if self._in_bold then
                table.insert(result, colors.reset)
                self._in_bold = false
            end
            self._can_be_bold = false
            table.insert(result, char)
            i = i + 1

        -- In code block - only look for closing backticks
        elseif self._in_code then
            table.insert(result, char)
            if char == "`" then
                self._code_tick_count = self._code_tick_count - 1
                if self._code_tick_count == 0 then
                    table.insert(result, colors.reset)
                    self._in_code = false
                end
            end
            i = i + 1

        -- In star mode - keep formatting, look for closing stars
        elseif self._in_star then
            table.insert(result, char)
            if char == "*" then
                self._star_count = self._star_count - 1
                if self._star_count == 0 then
                    table.insert(result, colors.reset)
                    self._in_star = false
                    if self._can_be_bold then
                        self._in_bold = not self._in_bold
                    end
                    self._consecutive_count = 0
                    self._can_be_bold = false
                end
            end
            i = i + 1

        -- Backtick - start code
        elseif char == "`" then
            local tick_count = 0
            local j = i
            while j <= len and content:sub(j, j) == "`" do
                tick_count = tick_count + 1
                j = j + 1
            end
            table.insert(result, colors.green)
            table.insert(result, string.rep("`", tick_count))
            self._in_code = true
            self._code_tick_count = tick_count
            self._at_line_start = false
            i = i + tick_count

        -- Asterisk - start bold
        elseif char == "*" then
            local star_count = 0
            local j = i
            while j <= len and content:sub(j, j) == "*" do
                star_count = star_count + 1
                j = j + 1
            end
            table.insert(result, colors.green)
            table.insert(result, colors.bold)
            table.insert(result, string.rep("*", star_count))
            self._in_star = true
            self._star_count = star_count
            self._at_line_start = false
            i = i + star_count

        -- Header at line start
        elseif self._at_line_start and char == "#" then
            local header_end = content:find("\n", i) or (len + 1)
            local header_text = content:sub(i, header_end - 1)
            table.insert(result, colors.reset)
            table.insert(result, colors.bold)
            table.insert(result, colors.red)
            table.insert(result, header_text)
            table.insert(result, colors.reset)
            self._at_line_start = false
            i = header_end

        -- Underscore - bold
        elseif char == "_" then
            if self._in_bold then
                table.insert(result, colors.reset)
                self._in_bold = false
            else
                table.insert(result, colors.reset)
                table.insert(result, colors.bold)
                table.insert(result, colors.green)
                self._in_bold = true
            end
            table.insert(result, char)
            self._at_line_start = false
            i = i + 1

        -- Normal character
        else
            table.insert(result, char)
            if char ~= " " and char ~= "\t" then
                self._at_line_start = false
            end
            i = i + 1
        end
    end

    -- Close any open formatting
    if self._in_code or self._in_star or self._in_bold then
        table.insert(result, colors.reset)
    end

    return table.concat(result)
end

function MarkdownColorizer:colorize(text)
    return self:print_with_colorization(text)
end

function MarkdownColorizer:process_with_colorization(text)
    return self:print_with_colorization(text)
end

return MarkdownColorizer
