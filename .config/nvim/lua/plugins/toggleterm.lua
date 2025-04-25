return {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
        require("toggleterm").setup()

        local Terminal = require("toggleterm.terminal").Terminal

        local function close_terminal_on_zero_exit(terminal, _, exit_code)
            if exit_code == 0 then
                terminal:close()
            end
        end

        local lazygit = Terminal:new({
            cmd = "lazygit",
            direction = "float",
            hidden = true,
            on_exit = close_terminal_on_zero_exit,
        })

        local dotfileslazygit = Terminal:new({
            cmd = "lazygit --git-dir=$HOME/.local/share/yadm/repo.git --work-tree=$HOME",
            direction = "float",
            hidden = true,
            on_exit = close_terminal_on_zero_exit,
        })

        local ok, wk = pcall(require, "which-key")
        if not ok then
            vim.notify(
                "which-key not found, not setting toggleterm keybindings"
            )
            return
        end

        wk.add({
            {
                -- Nested mappings are allowed and can be added in any order
                -- Most attributes can be inherited or overridden on any level
                -- There's no limit to the depth of nesting
                mode = { "n", "v" }, -- NORMAL and VISUAL mode
                {
                    "<leader>gg",
                    function()
                        if
                            vim.loop.cwd() == vim.call("expand", "~/.config")
                        then
                            dotfileslazygit:toggle()
                        else
                            lazygit:toggle()
                        end
                    end,
                    desc = "LazyGit",
                }, -- no need to specify mode since it's inherited
            },
        })
    end,
}
