local wezterm = require 'wezterm'
local config = wezterm.config_builder()
config.font_size = 17.9
config.font = wezterm.font 'IosevkaTerm Nerd Font'
config.color_scheme = 'Kanagawa (Gogh)'
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}


config.default_workspace = "~"
local workspace_switcher = wezterm.plugin.require("https://github.com/MLFlexer/smart_workspace_switcher.wezterm")
workspace_switcher.apply_to_config(config)

config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }
config.keys = {
  {
    key = "a",
    mods = "LEADER",
    action = workspace_switcher.switch_workspace(),
  },
  {
    key = "A",
    mods = "LEADER",
    action = workspace_switcher.switch_to_prev_workspace(),
  }
}

local docker = require("docker")
docker.apply_to_config(config)

return config
