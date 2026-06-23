-- Web Search Plugin for Luna - Ultra-fast using search providers and lynx
--
-- Tools:
-- - web_search: Search to web
-- - get_url_content: Fetch URL using lynx -dump (plain text, not raw HTML)
--
-- Environment Variables:
-- - WEB_SEARCH_PROVIDERS: Semicolon-separated list of search providers
--   Format: "ProviderName,URL;Provider2Name,URL2;"
--   The URL should include the query parameter placeholder, the plugin appends the encoded query
--   Default: None (must be configured)

local M = {}

local config = require("core.config")
local shell = require("utils.shell_utils")
local log = require("utils.log")

-- In-memory cache
local _cache = {}
local _provider_index = 0
local _last_search_time = 0.0
local SEARCH_COOLDOWN = 180  -- 3 minutes

local DEFAULT_LINES_PER_PAGE = 150

-- Generic blocking indicators - provider-agnostic
local BLOCKING_INDICATORS = {
    "error-lite@",  -- DDG specific error
    "Too Many Requests",
    "Please complete the following challenge",
    "verify you are human",
    "Please solve the challenge below to continue",
    "Access denied",
    "Too many requests",
    "Your request has been flagged",
    "captcha for you",
    "your network appears to be sending automated queries",
    "If this persists, please [1]email us.",
    "Error getting results",
    "Our system has detected the type of high-volume traffic",
    "bots and scrapers",
    "please enter in the characters you see",
    "Why am I seeing CAPTCHA?",
    "Have trouble reading the CAPTCHA?",
}

-- URL encoding table
local URL_ENCODING = {
    [" "] = "+", ["!"] = "%21", ["\""] = "%22", ["#"] = "%23",
    ["$"] = "%24", ["&"] = "%26", ["'"] = "%27", ["("] = "%28",
    [")"] = "%29", ["*"] = "%2A", ["+"] = "%2B", [","] = "%2C",
    ["/"] = "%2F", [":"] = "%3A", [";"] = "%3B", ["="] = "%3D",
    ["?"] = "%3F", ["@"] = "%40", ["["] = "%5B", ["]"] = "%5D",
    ["{"] = "%7B", ["|"] = "%7C", ["}"] = "%7D",
}

local function url_encode(str)
    return str:gsub("[ !\"#$%&'()*+,/:;=?@%[%]{|}]", function(c)
        return URL_ENCODING[c] or string.format("%%%02X", string.byte(c))
    end)
end

local function validate_url(url)
    -- Basic URL validation
    if not url or url == "" then return false end
    return url:match("^https?://") ~= nil
end

local function detect_blocking(content)
    for _, indicator in ipairs(BLOCKING_INDICATORS) do
        if content:find(indicator, 1, true) then
            return true
        end
    end
    return false
end

local function fetch_url_text(url)
    -- Check if lynx is available
    local lynx_check = io.popen("which lynx 2>/dev/null || echo not_found")
    local result = lynx_check:read("*a")
    lynx_check:close()
    if result:match("not_found") then
        return "Error: lynx browser not installed. Install with: sudo apt install lynx"
    end
    
    local handle = io.popen("lynx -dump -nolist '" .. url:gsub("'", "'\\''") .. "' 2>&1")
    local content = handle:read("*a")
    local exit = {handle:close()}
    
    -- Detect if provider is blocking
    if detect_blocking(content) then
        local warning = "\n[!] WARNING: Search provider has blocked this request as bot traffic.\n    The AI cannot continue using web search until this is resolved.\n\n"
        content = warning .. content
    end
    
    return content
end

local function fetch_url_raw(url)
    -- Use curl for raw HTML
    local handle = io.popen("curl -sL -m 30 -A 'Mozilla/5.0' '" .. url:gsub("'", "'\\''") .. "' 2>&1")
    local content = handle:read("*a")
    handle:close()
    return content
end

local function parse_providers()
    local providers_str = os.getenv("WEB_SEARCH_PROVIDERS") or ""
    providers_str = providers_str:match("^%s*(.*%S)") or providers_str
    if providers_str == "" then
        return nil  -- Not configured
    end
    
    local providers = {}
    for part in providers_str:gmatch("[^;]+") do
        part = part:match("^%s*(.*%S)") or part
        if part and part ~= "" then
            local idx = part:find(",", 1, true)
            if idx then
                local name = part:sub(1, idx - 1)
                local url = part:sub(idx + 1)
                name = name:match("^%s*(.*%S)") or name
                url = url:match("^%s*(.*%S)") or url
                if name and url and name ~= "" and url ~= "" then
                    table.insert(providers, {name = name, url = url})
                end
            end
        end
    end
    
    return #providers > 0 and providers or nil
end

SEARCH_PROVIDERS = parse_providers()

local function web_search(query)
    -- Handle table argument format (when called as tool)
    if type(query) == "table" then
        query = query.query
    end
    if not query or query:match("^%s*$") then
        return {
            tool = "web_search",
            friendly = "Error: Query cannot be empty",
            detailed = "Query cannot be empty",
        }
    end
    
    if not SEARCH_PROVIDERS then
        local example = "WEB_SEARCH_PROVIDERS=MySearch,https://search.example.com/search?q="
        return {
            tool = "web_search",
            friendly = "Web search not configured",
            detailed = "Plugin not configured. Set the WEB_SEARCH_PROVIDERS environment variable.\n\n"
                .. "Example format:\n  export " .. example .. "\n\n"
                .. "Format: 'Name,URL;Name2,URL2;' - the URL should include a query parameter placeholder",
        }
    end
    
    -- Check cache first
    if _cache[query] then
        local content = _cache[query]
        local lines = {}
        for line in content:gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        local page_lines = {}
        for i = 1, math.min(#lines, DEFAULT_LINES_PER_PAGE) do
            table.insert(page_lines, lines[i])
        end
        return {
            tool = "web_search",
            friendly = "Web search for '" .. query .. "' (cached)",
            detailed = "Web search results:\n\n" .. table.concat(page_lines, "\n"),
        }
    end
    
    -- Reset to preferred provider if enough time has passed
    local datetime = require("utils.datetime_utils")
    local now = datetime.get_time()
    if now - _last_search_time > SEARCH_COOLDOWN then
        _provider_index = 0
    end
    _last_search_time = now
    
    local failed_providers = {}
    local encoded = url_encode(query)
    local num_providers = #SEARCH_PROVIDERS
    
    -- Rotate through providers starting from last used index
    for i = 0, num_providers - 1 do
        local idx = ((_provider_index + i) % num_providers) + 1
        local provider = SEARCH_PROVIDERS[idx]
        local provider_name = provider.name
        local base_url = provider.url
        
        local content = fetch_url_text(base_url .. encoded)
        
        -- Check if this provider blocked us
        if detect_blocking(content) then
            table.insert(failed_providers, {name = provider_name, reason = "blocked"})
        else
            -- Update rotation index and cache successful result
            _provider_index = ((idx + 1) % num_providers) + 1
            _cache[query] = content
            
            local lines = {}
            for line in content:gmatch("[^\n]+") do
                table.insert(lines, line)
            end
            local page_lines = {}
            for i = 1, math.min(#lines, DEFAULT_LINES_PER_PAGE) do
                table.insert(page_lines, lines[i])
            end
            return {
                tool = "web_search",
                friendly = "Web search for '" .. query .. "' (via " .. provider_name .. ")",
                detailed = "Web search results:\n\n" .. table.concat(page_lines, "\n"),
            }
        end
    end
    
    -- All providers failed
    local error_details = {}
    for _, f in ipairs(failed_providers) do
        table.insert(error_details, "  - " .. f.name .. ": " .. f.reason)
    end
    return {
        tool = "web_search",
        friendly = "[!] All search providers failed",
        detailed = "Failed to search '" .. query .. "'. Tried providers:\n" .. table.concat(error_details, "\n"),
    }
end

local function get_url_content(args)
    local url = args.url or ""
    local page = args.page or 1
    local raw = args.raw or false
    
    if not url or url:match("^%s*$") then
        return {
            tool = "get_url_content",
            friendly = "Error: URL cannot be empty",
            detailed = "URL cannot be empty",
        }
    end
    
    if not validate_url(url) then
        return {
            tool = "get_url_content",
            friendly = "Error: Invalid URL format",
            detailed = "Invalid URL format",
        }
    end
    
    -- Cache key includes raw flag
    local cache_key = url .. "?raw=" .. tostring(raw)
    
    -- Check cache first (only for non-raw content)
    if not raw and _cache[cache_key] then
        local content = _cache[cache_key]
        local lines = {}
        for line in content:gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        local total = #lines
        local max_page = math.ceil(total / DEFAULT_LINES_PER_PAGE)
        local start_idx = (page - 1) * DEFAULT_LINES_PER_PAGE + 1
        local end_idx = math.min(page * DEFAULT_LINES_PER_PAGE, total)
        local paginated = {}
        for i = start_idx, end_idx do
            table.insert(paginated, lines[i])
        end
        local footer = "\n[page " .. page .. "/" .. max_page .. "]"
        if max_page > 1 then
            footer = footer .. " | more: page=" .. math.min(page + 1, max_page)
        end
        return {
            tool = "get_url_content",
            friendly = "Fetched " .. url .. " (page " .. page .. "/" .. max_page .. ", cached)",
            detailed = table.concat(paginated, "\n") .. footer,
        }
    end
    
    local content
    if raw then
        content = fetch_url_raw(url)
    else
        content = fetch_url_text(url)
    end
    
    -- Only cache non-raw content
    if not raw then
        _cache[cache_key] = content
    end
    
    -- Paginate
    if raw then
        local chars_per_page = DEFAULT_LINES_PER_PAGE * 80
        local total = #content
        local max_page = math.ceil(total / chars_per_page)
        local start_idx = (page - 1) * chars_per_page + 1
        local end_idx = math.min(page * chars_per_page, total)
        local paginated = content:sub(start_idx, end_idx)
        local footer = "\n[page " .. page .. "/" .. max_page .. "]"
        if max_page > 1 then
            footer = footer .. " | more: page=" .. math.min(page + 1, max_page)
        end
        return {
            tool = "get_url_content",
            friendly = "Fetched " .. url .. " (page " .. page .. "/" .. max_page .. ", raw HTML)",
            detailed = paginated .. footer,
        }
    else
        local lines = {}
        for line in content:gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        local total = #lines
        local max_page = math.ceil(total / DEFAULT_LINES_PER_PAGE)
        local start_idx = (page - 1) * DEFAULT_LINES_PER_PAGE + 1
        local end_idx = math.min(page * DEFAULT_LINES_PER_PAGE, total)
        local paginated = {}
        for i = start_idx, end_idx do
            table.insert(paginated, lines[i])
        end
        local footer = "\n[page " .. page .. "/" .. max_page .. "]"
        if max_page > 1 then
            footer = footer .. " | more: page=" .. math.min(page + 1, max_page)
        end
        return {
            tool = "get_url_content",
            friendly = "Fetched " .. url .. " (page " .. page .. "/" .. max_page .. ")",
            detailed = table.concat(paginated, "\n") .. footer,
        }
    end
end

local function format_get_url_content(args)
    local url = args.url or ""
    local page = args.page or 1
    local raw = args.raw or false
    local raw_str = raw and " (raw HTML)" or " (lynx text)"
    return "URL: " .. url .. "\nPage: " .. tostring(page) .. raw_str
end

function M:create_plugin(ctx)
    -- Register web_search tool
    ctx:register_tool(
        "web_search",
        web_search,
        "Search to web for information",
        {
            type = "object",
            properties = {
                query = {
                    type = "string",
                    description = "Search query string"
                }
            },
            required = {"query"}
        },
        true  -- auto_approved
    )
    
    -- Register get_url_content tool
    ctx:register_tool(
        "get_url_content",
        get_url_content,
        "Fetch URL content. Default: lynx -dump (plain text). Set raw=true for raw HTML via curl.",
        {
            type = "object",
            properties = {
                url = {
                    type = "string",
                    description = "URL to fetch (https only)"
                },
                page = {
                    type = "integer",
                    description = "Page number for pagination (default: 1)",
                    default = 1
                },
                raw = {
                    type = "boolean",
                    description = "Fetch raw HTML instead of lynx-processed text (default: false)",
                    default = false
                }
            },
            required = {"url"}
        },
        false,  -- not auto_approved
        format_get_url_content
    )
    
    if config.debug() then
        log.info("  - web_search tool (auto-approved)")
        log.info("  - get_url_content tool")
    end
    
    return true
end

return M
