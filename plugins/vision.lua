--[[
Vision Plugin for Luna

Enables image input via @/path/to/image syntax.
Supports: PNG, JPEG, GIF, BMP, WebP, TIFF, HEIC

Usage:
    @screenshot.png Analyze this error
    @/absolute/path/to/image.jpg What do you see?
    @a.png @b.jpg Compare these images
]]

local M = {}

local log = require("utils.log")
local config = require("core.config")

-- Supported image formats
local SUPPORTED_FORMATS = {
    [".png"] = "image/png",
    [".jpg"] = "image/jpeg",
    [".jpeg"] = "image/jpeg",
    [".gif"] = "image/gif",
    [".bmp"] = "image/bmp",
    [".webp"] = "image/webp",
    [".tiff"] = "image/tiff",
    [".tif"] = "image/tiff",
    [".heic"] = "image/heic",
}

-- Base64 encoding table
local b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(data)
    local result = {}
    local i = 1
    local len = #data
    
    while i <= len do
        local byte1 = string.byte(data, i)
        local byte2 = i + 1 <= len and string.byte(data, i + 1) or 0
        local byte3 = i + 2 <= len and string.byte(data, i + 2) or 0
        
        local enc1 = math.floor(byte1 / 4)
        local enc2 = math.floor((byte1 % 4) * 16) + math.floor(byte2 / 16)
        local enc3 = math.floor((byte2 % 16) * 4) + math.floor(byte3 / 64)
        local enc4 = byte3 % 64
        
        table.insert(result, string.sub(b64_chars, enc1 + 1, enc1 + 1))
        table.insert(result, string.sub(b64_chars, enc2 + 1, enc2 + 1))
        
        if i + 1 <= len then
            table.insert(result, string.sub(b64_chars, enc3 + 1, enc3 + 1))
        else
            table.insert(result, "=")
        end
        
        if i + 2 <= len then
            table.insert(result, string.sub(b64_chars, enc4 + 1, enc4 + 1))
        else
            table.insert(result, "=")
        end
        
        i = i + 3
    end
    
    return table.concat(result)
end

local function is_supported_image(file_path)
    local ext = file_path:lower():match("%.%w+$") or ""
    return SUPPORTED_FORMATS[ext] ~= nil
end

local function get_mime_type(file_path)
    local ext = file_path:lower():match("%.%w+$") or ""
    return SUPPORTED_FORMATS[ext]
end

local function encode_image(file_path)
    local file = io.open(file_path, "rb")
    if not file then
        error("Cannot open file: " .. file_path)
    end
    local data = file:read("*all")
    file:close()
    return base64_encode(data)
end

local function is_anthropic_provider()
    local provider = os.getenv("API_PROVIDER") or ""
    return provider:lower() == "anthropic"
end

-- Resolve file path: try direct path, then relative to cwd
local function resolve_path(path)
    -- Try direct path first
    local file = io.open(path, "r")
    if file then
        file:close()
        return path  -- Direct path works
    end
    -- Try with current working directory prepended
    local lfs_available, lfs = pcall(require, "lfs")
    if lfs_available then
        local cwd = lfs.currentdir()
        local full_path = cwd .. "/" .. path
        file = io.open(full_path, "r")
        if file then
            file:close()
            return full_path
        end
    end
    return nil  -- File not found
end

function file_exists(path)
    return resolve_path(path) ~= nil
end

local function create_image_content_part(file_path)
    local resolved = resolve_path(file_path)
    if not resolved then
        error("Image not found: " .. file_path)
    end
    
    if not is_supported_image(resolved) then
        local mime = get_mime_type(resolved)
        error("Unsupported format: " .. (mime or "unknown"))
    end
    
    local base64_data = encode_image(resolved)
    local mime_type = get_mime_type(resolved)
    
    if is_anthropic_provider() then
        return {
            type = "image",
            source = {
                type = "base64",
                media_type = mime_type,
                data = base64_data,
            },
        }
    else
        return {
            type = "image_url",
            image_url = {
                url = "data:" .. mime_type .. ";base64," .. base64_data
            },
        }
    end
end

local function parse_image_references(text)
    -- Lua pattern for @ followed by file path with image extension
    local image_paths = {}
    local clean_text = text
    
    -- Pattern to match @ followed by path with image extension
    -- Must use alternation for jpg/jpeg since ? is literal in char class
    local img_pattern = "@([%w_%-%./]+%.[pP][nN][gG])" ..
                       "|[@]([%w_%-%./]+%.[jJ][pP][gG])" ..
                       "|[@]([%w_%-%./]+%.[jJ][pP][eE][gG])" ..
                       "|[@]([%w_%-%./]+%.[gG][iI][fF])" ..
                       "|[@]([%w_%-%./]+%.[bB][mM][pP])" ..
                       "|[@]([%w_%-%./]+%.[wW][eE][bB][pP])" ..
                       "|[@]([%w_%-%./]+%.[tT][iI][fF][fF]?)" ..
                       "|[@]([%w_%-%./]+%.[hH][eE][iI][cC])"
    
    -- Actually, use a simpler pattern that captures @path
    local simple_pattern = "@[%w_%-%./]+"
    local ext_patterns = {"png", "jpg", "jpeg", "gif", "bmp", "webp", "tiff", "tif", "heic"}
    
    for match in clean_text:gmatch(simple_pattern) do
        local path = match:sub(2)  -- Remove @
        local ext = path:match("%.(%w+)$")
        if ext then
            ext = ext:lower()
            for _, supported in ipairs(ext_patterns) do
                if ext == supported then
                    table.insert(image_paths, path)
                    break
                end
            end
        end
    end
    
    -- Remove @image references from text
    clean_text = clean_text:gsub(simple_pattern, "")
    clean_text = clean_text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    
    return clean_text, image_paths
end

local function create_user_message(text, image_paths)
    local content_parts = {}
    
    -- Add text part if present
    if text and text:match("%S") then
        table.insert(content_parts, {type = "text", text = text})
    end
    
    -- Add each valid image
    for _, path in ipairs(image_paths) do
        local success, image_part_or_err = pcall(create_image_content_part, path)
        if success then
            table.insert(content_parts, image_part_or_err)
        else
            table.insert(content_parts, {type = "text", text = "[Error loading image " .. path .. ": " .. image_part_or_err .. "]"})
        end
    end
    
    return {role = "user", content = content_parts}
end

local function transform_user_input(user_input, app)
    local clean_text, image_paths = parse_image_references(user_input)
    
    if #image_paths == 0 then
        return nil  -- No images, use normal processing
    end
    
    -- Validate images exist and resolve paths
    local valid_images = {}
    local missing = {}
    
    for _, path in ipairs(image_paths) do
        local resolved = resolve_path(path)
        if resolved then
            table.insert(valid_images, resolved)
        else
            table.insert(missing, path)
        end
    end
    
    if #valid_images == 0 and #missing > 0 then
        -- Only missing images - return error as text
        local error_msgs = {}
        for _, p in ipairs(missing) do
            table.insert(error_msgs, "[Image not found: " .. p .. "]")
        end
        return {role = "user", content = (clean_text .. " " .. table.concat(error_msgs, " ")):match("^%s*(.-)%s*$")}
    end
    
    -- Create multimodal message
    local message = create_user_message(clean_text, valid_images)
    
    -- Add missing image errors if any
    if #missing > 0 then
        local error_texts = {}
        for _, p in ipairs(missing) do
            table.insert(error_texts, "[Image not found: " .. p .. "]")
        end
        local error_text = table.concat(error_texts, " ")
        table.insert(message.content, {type = "text", text = error_text})
    end
    
    return message
end

function M.create_plugin(self, ctx)
    -- Register hook for transforming user input with @image references
    ctx:register_hook("after_user_prompt", function(user_input)
        local clean_text, image_paths = parse_image_references(user_input)
        
        if #image_paths == 0 then
            return nil  -- No images, use normal processing
        end
        
        -- Validate images exist and resolve paths
        local valid_images = {}
        local missing = {}
        
        for _, path in ipairs(image_paths) do
            local resolved = resolve_path(path)
            if resolved then
                table.insert(valid_images, resolved)
            else
                table.insert(missing, path)
            end
        end
        
        if #valid_images == 0 and #missing > 0 then
            -- All missing - return error text
            local error_msgs = {}
            for _, p in ipairs(missing) do
                table.insert(error_msgs, "[Image not found: " .. p .. "]")
            end
            return clean_text .. " " .. table.concat(error_msgs, " ")
        end
        
        -- Create and add multimodal message
        local message = create_user_message(clean_text, valid_images)
        
        -- Add missing image errors if any
        if #missing > 0 then
            local error_text = " " .. table.concat(missing, " ") .. " not found"
            table.insert(message.content, {type = "text", text = error_text})
        end
        
        ctx.app.message_history:add_user_message(message)
        
        -- Return cleaned text (without @paths) so API is still called
        if clean_text and clean_text:match("%S") then
            return clean_text
        end
        return "analyze the image"
    end)
    
    -- Register read_image tool
    ctx:register_tool("read_image", function(args)
        local file_path = args and args.path or ""
        
        if not file_path or file_path == "" then
            return {
                tool = "read_image",
                friendly = "Error: No path provided",
                detailed = "Please provide a file path to the image."
            }
        end
        
        if not file_exists(file_path) then
            return {
                tool = "read_image",
                friendly = "Error: File not found: " .. file_path,
                detailed = "The file '" .. file_path .. "' does not exist."
            }
        end
        
        if not is_supported_image(file_path) then
            local formats = {}
            for ext, _ in pairs(SUPPORTED_FORMATS) do
                table.insert(formats, ext)
            end
            return {
                tool = "read_image",
                friendly = "Error: Unsupported image format: " .. file_path,
                detailed = "Supported formats: " .. table.concat(formats, ", ")
            }
        end
        
        local full_vision = os.getenv("AICODER_FULL_VISION") == "1"
        local force_ascii = args.force_ascii
        
        if full_vision and not force_ascii then
            local success, err = pcall(function()
                local image_part = create_image_content_part(file_path)
                local user_message = {
                    role = "user",
                    content = {
                        {type = "text", text = "This is the image you requested: path=" .. file_path},
                        image_part
                    }
                }
                ctx.app.message_history:add_user_message(user_message)
            end)
            
            if success then
                return {
                    tool = "read_image",
                    friendly = "Image loaded: " .. file_path .. " (full vision)",
                    detailed = "Image loaded: " .. file_path .. ". A user message with the image has been added to the conversation."
                }
            else
                return {
                    tool = "read_image",
                    friendly = "Error loading image: " .. tostring(err),
                    detailed = tostring(err)
                }
            end
        else
            -- Use chafa for ASCII art
            local handle = io.popen("which chafa 2>/dev/null || echo not_found")
            local chafa_check = handle:read("*a"):gsub("%s+", "")
            handle:close()
            
            if chafa_check == "not_found" then
                return {
                    tool = "read_image",
                    friendly = "Error: chafa not installed",
                    detailed = "chafa is not installed. Install it with: sudo apt install chafa\nOr set AICODER_FULL_VISION=1 to send images directly."
                }
            end
            
            local cmd = "chafa --symbols=block --fit-width --colors=none --size 100x " .. 
                        file_path:gsub(" ", "\\ ") .. " 2>&1"
            
            local handle = io.popen(cmd)
            local result = handle:read("*a")
            handle:close()
            
            local exit_code = os.execute("echo >/dev/null 2>&1")  -- Check if previous command succeeded
            
            -- Parse exit code from result (chafa returns non-zero if it fails)
            if result:match("^Error:") or result:match("cannot open") then
                return {
                    tool = "read_image",
                    friendly = "Error: chafa failed for " .. file_path,
                    detailed = result
                }
            end
            
            local ascii_art = result
            if #ascii_art > 15000 then
                ascii_art = ascii_art:sub(1, 15000) .. "\n[... truncated ...]"
            end
            
            return {
                tool = "read_image",
                friendly = "ASCII representation of " .. file_path,
                detailed = "ASCII art of " .. file_path .. ":\n```\n" .. ascii_art .. "\n```"
            }
        end
    end, "Read and analyze an image file. If AICODER_FULL_VISION=1, sends the image directly to the AI. Otherwise, converts to ASCII art using chafa.", {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to the image file"
            },
            force_ascii = {
                type = "boolean",
                description = "Force ASCII art output even if AICODER_FULL_VISION=1",
                default = false
            }
        },
        required = {"path"}
    }, false, function(args)
        local path = args and args.path or ""
        local full_vision = os.getenv("AICODER_FULL_VISION") == "1"
        local force_ascii = args and args.force_ascii
        
        local mode
        if force_ascii then
            mode = "ASCII (forced)"
        else
            mode = full_vision and "full vision" or "ASCII (chafa)"
        end
        
        return "Path: " .. path .. "\nMode: " .. mode
    end)

    -- Screenshot command
    local function has_x11_access()
        local f = io.popen("xset q 2>/dev/null")
        if not f then return false end
        local result = f:read("*a")
        f:close()
        return result ~= ""
    end
    
    local function screenshot_exists(path)
        local f = io.open(path, "r")
        if f then f:close() return true end
        return false
    end
    
    local function handle_screenshot(args)
        local temp_utils = require("utils.temp_file_utils")
        local screenshot_path = temp_utils.get_temp_dir() .. "/screenshot.png"
        
        if not has_x11_access() then
            print("Error: No X11 access. Run 'xhost +' on your host.")
            return
        end
        
        local f = io.popen("which flameshot 2>/dev/null")
        if not f then
            print("Error: flameshot not found.")
            return
        end
        local result = f:read("*a")
        f:close()
        if not result or result == "" then
            print("Error: flameshot not found.")
            return
        end
        
        print("Launching Flameshot...")
        os.execute("flameshot gui --path " .. screenshot_path .. " 2>/dev/null")
        
        if not screenshot_exists(screenshot_path) then
            print("Screenshot cancelled.")
            return
        end
        
        local ok, err = pcall(function()
            local image_part = create_image_content_part(screenshot_path)
            ctx.app:add_plugin_message({
                role = "user",
                content = {
                    {type = "text", text = "Screenshot taken:"},
                    image_part
                }
            })
            print("Screenshot added to conversation.")
        end)
        
        if not ok then
            print("Error: " .. tostring(err))
        end
        
        os.remove(screenshot_path)
    end
    
    ctx:register_command("screenshot", handle_screenshot, "Take a screenshot with flameshot")
    ctx:register_command("ss", handle_screenshot, "Alias for /screenshot")
end

return M