---
-- luna_theme.lua - Luna color palette
--
-- A minimal theme plugin that applies the Luna color scheme.
---

local M = {}

local config = require("core.config")

-- Apply Luna theme
local function apply_theme(use_256)
    if use_256 then
        config.colors.red = "\x1b[38;5;218m"
        config.colors.green = "\x1b[38;5;191m"
        config.colors.yellow = "\x1b[38;5;220m"
        config.colors.blue = "\x1b[38;5;87m"
        config.colors.magenta = "\x1b[38;5;218m"
        config.colors.cyan = "\x1b[38;5;87m"
        config.colors.white = "\x1b[38;5;231m"
        config.colors.brightGreen = "\x1b[38;5;82m"
        config.colors.brightRed = "\x1b[38;5;213m"
        config.colors.brightYellow = "\x1b[38;5;226m"
        config.colors.brightBlue = "\x1b[38;5;123m"
        config.colors.brightMagenta = "\x1b[38;5;213m"
        config.colors.brightCyan = "\x1b[38;5;123m"
        config.colors.brightWhite = "\x1b[38;5;231m"
    else
        config.colors.red = "\x1b[38;2;255;175;255m"
        config.colors.green = "\x1b[38;2;215;255;95m"
        config.colors.yellow = "\x1b[38;2;255;215;0m"
        config.colors.blue = "\x1b[38;2;175;255;255m"
        config.colors.magenta = "\x1b[38;2;255;175;255m"
        config.colors.cyan = "\x1b[38;2;175;255;255m"
        config.colors.white = "\x1b[38;2;255;255;255m"
        config.colors.brightGreen = "\x1b[38;2;200;255;120m"
        config.colors.brightRed = "\x1b[38;2;255;200;255m"
        config.colors.brightYellow = "\x1b[38;2;255;235;50m"
        config.colors.brightBlue = "\x1b[38;2;150;255;255m"
        config.colors.brightMagenta = "\x1b[38;2;255;200;255m"
        config.colors.brightCyan = "\x1b[38;2;150;255;255m"
        config.colors.brightWhite = "\x1b[38;2;255;255;255m"
    end
end

function M.create_plugin(ctx)
    local disable_colors = os.getenv("AICODER_DISABLE_COLORS") == "1"
    
    if disable_colors then
        for k, _ in pairs(config.colors) do
            config.colors[k] = ""
        end
        if config.debug() then
            print("  - Luna theme applied (no colors, disabled via env)")
        end
        return {}
    end
    
    local in_screen = os.getenv("STY") ~= nil
    
    apply_theme(in_screen)
    
    if config.debug() then
        local mode = in_screen and "256 palette" or "true color"
        print("  - Luna theme applied (" .. mode .. ")")
    end
    
    return {}
end

return M.create_plugin
