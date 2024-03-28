vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system {
		'git',
		'clone',
		'--filter=blob:none',
		'https://github.com/folke/lazy.nvim.git',
		'--branch=main',
		lazypath,
	}
end
vim.opt.rtp:prepend(lazypath)

local function diff_source()
	local gitsigns = vim.b.gitsigns_status_dict
	if gitsigns then
		return {
			added = gitsigns.added,
			modified = gitsigns.changed,
			removed = gitsigns.removed,
		}
	end
end

require('lazy').setup({
	'tpope/vim-fugitive',
	'tpope/vim-rhubarb',
	'tpope/vim-sleuth',

	{
		'neovim/nvim-lspconfig',
		dependencies = {
			-- Automatically install LSPs to stdpath for neovim
			'williamboman/mason.nvim',
			'williamboman/mason-lspconfig.nvim',

			-- Useful status updates for LSP
			-- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
			'j-hui/fidget.nvim',

			-- Additional lua configuration, makes nvim stuff amazing!
			'folke/neodev.nvim',
		},
	},
	{ "ellisonleao/glow.nvim", config = true, cmd = "Glow" },
	{ 'sQVe/sort.nvim' },
	{
		"p00f/clangd_extensions.nvim",
	},
	{
		'akinsho/git-conflict.nvim',
		version = "*",
		config = true,
	},

	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		dependencies = { "nvim-treesitter/nvim-treesitter-refactor", "HiPhish/rainbow-delimiters.nvim" },
		config = function () 
			local configs = require("nvim-treesitter.configs")

			configs.setup({
				ensure_installed = { "cpp", "lua", "vim", "vimdoc", "query", "python", "c", "bash", "gitignore", "git_rebase", "gitcommit", "markdown", "markdown_inline", "go", "make", "objc" },
				sync_install = false,
			highlight = { enable = true },
				indent = { enable = true },  
				incremental_selection = { enable = true },
				refactor = {
					highlight_definitions = {
						enable = true,
						-- Set to false if you have an `updatetime` of ~100.
						clear_on_cursor_move = true,
					},
					smart_rename = {
						enable = true,
						keymaps = {
							smart_rename = "grr",
						},
					},
					navigation = {
						enable = true,
						-- Assign keymaps to false to disable them, e.g. `goto_definition = false`.
						keymaps = {
							goto_definition = "gnd",
							list_definitions = "gnD",
							list_definitions_toc = "gO",
							goto_next_usage = "<a-*>",
							goto_previous_usage = "<a-#>",
						},
					},
					highlight_current_scope = { enable = true },
				},
			})
		end
	},

	{
		'glepnir/template.nvim',
		cmd = { 'Template' },
		temp_dir = '~/.config/nvim/templates',
		author = 'Oliver Tzeng',
		email = 'olivertzeng@proton.me',
		keys = { "<leader>t", "<cmd>Template<cr>", desc = "Start with template" },
	},

	{
		"folke/noice.nvim",
		event = "VeryLazy",
		view = "cmdline",
		opts = { cmdline = { view = "cmdline", } },
		dependencies = {
			"MunifTanjim/nui.nvim",
			"rcarriga/nvim-notify",
		}
	},
	{
		"startup-nvim/startup.nvim",
		requires = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
		opts = {
			theme = "dashboard",
		},
	},
	{
		"RRethy/vim-illuminate",
		opts = {
			delay = 200,
			large_file_cutoff = 2000,
			large_file_overrides = {
				providers = { "lsp" },
			},
		},
		config = function(_, opts)
			require("illuminate").configure(opts)

			local function map(key, dir, buffer)
				vim.keymap.set("n", key, function()
					require("illuminate")["goto_" .. dir .. "_reference"](false)
					end, { desc = dir:sub(1, 1):upper() .. dir:sub(2) .. " Reference", buffer = buffer })
			end

			map("]]", "next")
			map("[[", "prev")

			-- also set it after loading ftplugins, since a lot overwrite [[ and ]]
			vim.api.nvim_create_autocmd("FileType", {
				callback = function()
					local buffer = vim.api.nvim_get_current_buf()
					map("]]", "next", buffer)
					map("[[", "prev", buffer)
				end,
			})
		end,
		keys = {
			{ "]]", desc = "Next Reference" },
			{ "[[", desc = "Prev Reference" },
		},
	},
	{
		'windwp/nvim-autopairs',
		event = "InsertEnter",
		opts = {} -- this is equalent to setup({}) function
	},
	{
		'nmac427/guess-indent.nvim',
	},
	{
		'subnut/nvim-ghost.nvim'
	},
	{
		"folke/trouble.nvim",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
			opts = {
				color_icons = true,
				default = true,
				strict = true,
			},
		},
		cmd = { "TroubleToggle", "Trouble" },
		opts = { use_diagnostic_signs = true },
		keys = {
			{ "<leader>xx", "<cmd>TroubleToggle document_diagnostics<cr>", desc = "Document Diagnostics (Trouble)" },
			{ "<leader>xX", "<cmd>TroubleToggle workspace_diagnostics<cr>", desc = "Workspace Diagnostics (Trouble)" },
			{ "<leader>xL", "<cmd>TroubleToggle loclist<cr>", desc = "Location List (Trouble)" },
			{ "<leader>xQ", "<cmd>TroubleToggle quickfix<cr>", desc = "Quickfix List (Trouble)" },
			{
				"[q",
				function()
				if require("trouble").is_open() then
						require("trouble").previous({ skip_groups = true, jump = true })
					else
						local ok, err = pcall(vim.cmd.cprev)
						if not ok then
							vim.notify(err, vim.log.levels.ERROR)
						end
					end
				end,
				desc = "Previous trouble/quickfix item",
			},
			{
				"]q",
				function()
				if require("trouble").is_open() then
						require("trouble").next({ skip_groups = true, jump = true })
					else
						local ok, err = pcall(vim.cmd.cnext)
						if not ok then
							vim.notify(err, vim.log.levels.ERROR)
						end
					end
				end,
				desc = "Next trouble/quickfix item",
			},
		},
	},

	{ "chentoast/marks.nvim", },
	{
		-- Autocompletion
		'hrsh7th/nvim-cmp',
		version = false, -- last release is way too old
		dependencies = {
			-- Snippet Engine & its associated nvim-cmp source
			'L3MON4D3/LuaSnip',
			'saadparwaiz1/cmp_luasnip',
			'rafamadriz/friendly-snippets',
			'mireq/luasnip-snippets',

			-- Adds LSP completion capabilities
			'hrsh7th/cmp-nvim-lsp',
			'hrsh7th/cmp-buffer',
			'hrsh7th/cmp-path',
			'hrsh7th/cmp-cmdline',
			'hrsh7th/cmp-nvim-lsp-signature-help',
			'hrsh7th/cmp-nvim-lsp-document-symbol',
			'chrisgrieser/cmp-nerdfont',
			'Dosx001/cmp-commit',
			'L3MON4D3/cmp-luasnip-choice',
			'Dynge/gitmoji.nvim',
		},
		opts = function()
			vim.api.nvim_set_hl(0, "CmpGhostText", { link = "Comment", default = true })
			local cmp = require("cmp")
			local defaults = require("cmp.config.default")()
			return {
				completion = {
					completeopt = "menu,menuone,noinsert",
				},
				mapping = cmp.mapping.preset.insert({
					["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
					["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
					["<C-b>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(4),
					["<C-Space>"] = cmp.mapping.complete(),
					["<C-e>"] = cmp.mapping.abort(),
					["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
					["<S-CR>"] = cmp.mapping.confirm({
						behavior = cmp.ConfirmBehavior.Replace,
						select = true,
					}), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
					["<C-CR>"] = function(fallback)
						cmp.abort()
						fallback()
					end,
				}),
				sources = cmp.config.sources({
					{ name = "buffer" },
					{ name = "nerdfont" },
					{ name = "nvim_lsp" },
					{ name = "path" },
					{ name = 'buffer' },
					{ name = 'luasnip' },
					{ name = 'nvim_lsp_document_symbol' },
				{ name = 'nvim_lsp_signature_help' },
					{ name = 'luasnip_choice' },
				}),
				cmp.setup.filetype('gitcommit', {
					sources = {
						{ name = 'commit' },
						{ name = 'gitmoji' },
					}
				}),
				experimental = {
					ghost_text = {
						hl_group = "CmpGhostText",
					},
				},
				sorting = defaults.sorting,
			}
		end,
		config = function(_, opts)
			for _, source in ipairs(opts.sources) do
				source.group_index = source.group_index or 1
			end
			require("cmp").setup(opts)
		end,
	},

	-- snippets
	{
		"L3MON4D3/LuaSnip",
		build = "make install_jsregexp",
		dependencies = {
			{
				"rafamadriz/friendly-snippets",
				config = function()
					require("luasnip.loaders.from_vscode").lazy_load()
				end,
			},
			{
				"nvim-cmp",
				dependencies = {
					"saadparwaiz1/cmp_luasnip",
					"nvim-treesitter/nvim-treesitter",
				},
				opts = function(_, opts)
					opts.snippet = {
						expand = function(args)
							require("luasnip").lsp_expand(args.body)
						end,
					}
					table.insert(opts.sources, { name = "luasnip" })
				end,
			},
		},
		init = function()
			local ls = require('luasnip')
			ls.setup({
				-- Required to automatically include base snippets, like "c" snippets for "cpp"
				load_ft_func = require('luasnip_snippets.common.snip_utils').load_ft_func,
				ft_func = require('luasnip_snippets.common.snip_utils').ft_func,
				-- To enable auto expansin
				enable_autosnippets = true,
				-- Uncomment to enable visual snippets triggered using <c-x>
				store_selection_keys = '<c-x>',
			})
			-- LuaSnip key bindings
			vim.keymap.set({ "i", "s" }, "<Tab>",
				function() if ls.expand_or_jumpable() then ls.expand_or_jump() else vim.api.nvim_input(
				'<C-V><Tab>') end end, { silent = true })
			vim.keymap.set({ "i", "s" }, "<S-Tab>", function() ls.jump(-1) end, { silent = true })
			vim.keymap.set({ "i", "s" }, "<C-E>",
				function() if ls.choice_active() then ls.change_choice(1) end end, { silent = true })
		end,
		opts = {
			history = true,
			delete_check_events = "TextChanged",
		},
		-- stylua: ignore
		keys = {
			{
				"<tab>",
				function()
					return require("luasnip").jumpable(1) and "<Plug>luasnip-jump-next" or "<tab>"
				end,
				expr = true, silent = true, mode = "i",
			},
			{ "<tab>", function() require("luasnip").jump(1) end, mode = "s" },
			{ "<s-tab>", function() require("luasnip").jump(-1) end, mode = { "i", "s" } },
		},
	},
	-- Useful plugin to show you pending keybinds.
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			plugins = { spelling = true },
			defaults = {
				mode = { "n", "v" },
				["g"] = { name = "+goto" },
				["gs"] = { name = "+surround" },
				["z"] = { name = "+fold" },
				["]"] = { name = "+next" },
				["["] = { name = "+prev" },
				["<leader><tab>"] = { name = "+tabs" },
				["<leader>b"] = { name = "+buffer" },
				["<leader>c"] = { name = "+code" },
				["<leader>f"] = { name = "+file/find" },
				["<leader>g"] = { name = "+git" },
				["<leader>gh"] = { name = "+hunks" },
				["<leader>q"] = { name = "+quit/session" },
				["<leader>s"] = { name = "+search" },
				["<leader>t"] = { name = "+template" },
				["<leader>u"] = { name = "+ui" },
				["<leader>x"] = { name = "+diagnostics/quickfix" },
			},
		},
		config = function(_, opts)
			local wk = require("which-key")
			wk.setup(opts)
			wk.register(opts.defaults)
		end,
	},
	{
		-- Adds git related signs to the gutter, as well as utilities for managing changes
		'lewis6991/gitsigns.nvim',
		opts = {
			-- See `:help gitsigns.txt`
			signs = {
				add			 = { text = '󰐖' },
				change		 = { text = '' },
				delete		 = { text = '' },
				topdelete	 = { text = '󰛲' },
				changedelete = { text = '󰦓' },
				untracked	 = { text = '󰀧' },
			},
			signcolumn					 = true, -- Toggle with `:Gitsigns toggle_signs`
			numhl						 = true, -- Toggle with `:Gitsigns toggle_numhl`
			linehl						 = true, -- Toggle with `:Gitsigns toggle_linehl`
			word_diff					 = true, -- Toggle with `:Gitsigns toggle_word_diff`
			watch_gitdir				 = {
				follow_files = true
			},
			auto_attach					 = true,
			attach_to_untracked			 = false,
			current_line_blame			 = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
			current_line_blame_opts		 = {
				virt_text = true,
				virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
				delay = 1000,
				ignore_whitespace = false,
				virt_text_priority = 100,
			},
			current_line_blame_formatter = '<author>, <author_time:%Y-%m-%d> - <summary>',
			sign_priority				 = 6,
			update_debounce				 = 100,
			status_formatter			 = nil, -- Use default
			max_file_length				 = 40000, -- Disable if file is longer than this (in lines)
			preview_config				 = {
				-- Options passed to nvim_open_win
				border = 'single',
				style = 'minimal',
				relative = 'cursor',
				row = 0,
				col = 1
			},
			yadm						 = {
				enable = false
			},

			on_attach					 = function(bufnr)
				vim.keymap.set('n', '<leader>hp', require('gitsigns').preview_hunk,
					{ buffer = bufnr, desc = 'Preview git hunk' })

				-- don't override the built-in and fugitive keymaps
				local gs = package.loaded.gitsigns
				vim.keymap.set({ 'n', 'v' }, ']c', function()
					if vim.wo.diff then
						return ']c'
					end
					vim.schedule(function()
						gs.next_hunk()
					end)
					return '<Ignore>'
					end, { expr = true, buffer = bufnr, desc = 'Jump to next hunk' })
				vim.keymap.set({ 'n', 'v' }, '[c', function()
					if vim.wo.diff then
						return '[c'
					end
					vim.schedule(function()
						gs.prev_hunk()
					end)
					return '<Ignore>'
					end, { expr = true, buffer = bufnr, desc = 'Jump to previous hunk' })
			end,
		},
	},

	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		opts = {},

	},

	{
		'sainnhe/gruvbox-material',
		priority = 1000,
		config = function()
			vim.cmd.colorscheme 'gruvbox-material'
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		init = function()
			vim.g.lualine_laststatus = vim.o.laststatus
			if vim.fn.argc(-1) > 0 then
				-- set an empty statusline till lualine loads
				vim.o.statusline = " "
			else
				-- hide the statusline on the starter page
				vim.o.laststatus = 0
			end
		end,
		opts = function()
			-- PERF: we don't need this lualine require madness 🤷
			local lualine_require = require("lualine_require")
			lualine_require.require = require
			vim.o.laststatus = vim.g.lualine_laststatus
			return {
				options = {
					theme = "gruvbox-material",
					globalstatus = false,
					disabled_filetypes = { statusline = { "startup" } },
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diagnostics" },
					lualine_c = { {
						"filename",
						symbols = {
							modified = '󰐖', -- Text to show when the buffer is modified
							readonly = '󰌾', -- Text to show when the file is non-modifiable or readonly.
							unnamed = '󰜣', -- Text to show for unnamed buffers.
							newfile = '󰎜', -- Text to show for newly created file before first write
							alternate_file = '#', -- Text to show to identify the alternate file
							directory = '', -- Text to show when the buffer is a directory
						},
					} },

					lualine_x = { "fileformat", "filetype" },
					lualine_y = { { "progress", separator = " ", padding = { left = 1, right = 0 } }, },
					lualine_z = { { 'diff', source = diff_source }, "location" },
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = { 'filesize' },
					lualine_c = {},
					lualine_x = {},
					lualine_y = {},
					lualine_z = {}
				},
				extensions = { "lazy", "fugitive", "trouble", "nvim-tree" },
			}
		end,
	},
	-- "gc" to comment visual regions/lines
	{ 'numToStr/Comment.nvim' },
	{ "rcarriga/nvim-dap-ui",  dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" } },
	{
		"mfussenegger/nvim-dap",
		optional = true,
		dependencies = {
			"mfussenegger/nvim-dap-python",
			-- stylua: ignore
			keys = {
				{ "<leader>dPt", function() require('dap-python').test_method() end, desc = "Debug Method", ft = "python" },
				{ "<leader>dPc", function() require('dap-python').test_class() end, desc = "Debug Class", ft = "python" },
			},
			config = function()
				require("dap-python").setup("~/.venv/bin/python")
			end,
		},
	},
	{
		'linux-cultist/venv-selector.nvim',
		cmd = 'VenvSelect',
		dependencies = { 
			'neovim/nvim-lspconfig', 
			'nvim-telescope/telescope.nvim', 
			'mfussenegger/nvim-dap-python', 
		},
		opts = function(_, opts)
			return vim.tbl_deep_extend("force", opts, {
				name = {
					"venv",
					".venv",
					"env",
					".env",
				},
			})
		end,
		keys = { { "<leader>cv", "<cmd>:VenvSelect<cr>", desc = "Select VirtualEnv" } },
	},
	{ "mfussenegger/nvim-lint" },
	{
		"stevearc/conform.nvim",
		config = function()
			require("conform").setup({
				"stevearc/conform.nvim",
				event = { "BufWritePre" },
				cmd = { "ConformInfo" },
				-- Everything in opts will be passed to setup()
				opts = {
					-- Define your formatters
					formatters_by_ft = {
						lua = { "stylua" },
						python = { "black" },
						cpp = { "clang-format" }
					},
					-- Set up format-on-save
					format_on_save = { timeout_ms = 500, lsp_fallback = true },
				},
				init = function()
					-- If you want the formatexpr, here is the place to set it
					vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
				end,
			})
		end,
	},
	{
		'tanvirtin/vgit.nvim',
		requires = {
			'nvim-lua/plenary.nvim'
		}
	},
	-- Fuzzy Finder (files, lsp, etc)
	{
		'nvim-telescope/telescope.nvim',
		branch = 'master',
		dependencies = {
			'nvim-lua/plenary.nvim',
			-- Fuzzy Finder Algorithm which requires local dependencies to be built.
			-- Only load if `make` is available. Make sure you have the system
			-- requirements installed.
			{
				'nvim-telescope/telescope-fzf-native.nvim',
				-- NOTE: If you are having trouble with this installation,
				--		 refer to the README for telescope-fzf-native for more instructions.
				build = 'make',
				cond = function()
					return vim.fn.executable 'make' == 1
				end,
			},
			{
				'debugloop/telescope-undo.nvim',
			},
		},
	},
}, {})

require('lint').linters_by_ft = {
	bash = {'shellcheck',},
	python = {'pylint',},
}

require("mason").setup({
	pip = {
		---@since 1.0.0
		-- Whether to upgrade pip to the latest version in the virtual environment before installing packages.
		upgrade_pip = true,
	},

	ui = {
		---@since 1.0.0
		-- The border to use for the UI window. Accepts same border values as |nvim_open_win()|.
		border = "none",

		---@since 1.0.0
		-- Width of the window. Accepts:
		-- - Integer greater than 1 for fixed width.
		-- - Float in the range of 0-1 for a percentage of screen width.
		width = 0.8,

		---@since 1.0.0
		-- Height of the window. Accepts:
		-- - Integer greater than 1 for fixed height.
		-- - Float in the range of 0-1 for a percentage of screen height.
		height = 0.9,

		icons = {
			---@since 1.0.0
			-- The list icon to use for installed packages.
			package_installed = "◍",
			---@since 1.0.0
			-- The list icon to use for packages that are installing, or queued for installation.
			package_pending = "◍",
			---@since 1.0.0
			-- The list icon to use for packages that are not installed.
			package_uninstalled = "◍",
		},

	},
})

-- [[ Setting options ]]
-- See `:help vim.o`

-- Set highlight on search
vim.o.hlsearch = true

-- Make line numbers default
vim.wo.number = true

-- Make line numbers indefinite
vim.wo.relativenumber = true

-- Enable mouse mode
vim.o.mouse = 'a'

-- Sync clipboard between OS and Neovim.
--	Remove this option if you want your OS clipboard to remain independent.
--	See `:help 'clipboard'`
vim.o.clipboard = 'unnamedplus'

-- Enable break indent

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or capital in search
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.wo.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250
vim.o.timeoutlen = 300

-- Set completeopt to have a better completion experience
vim.o.completeopt = 'menuone,noselect'

-- NOTE: You should make sure your terminal supports this
vim.o.termguicolors = true

-- Indentation
vim.o.tabstop = 4
vim.o.shiftwidth = 0
vim.o.expandtab = false
vim.o.breakindent = true

-- [[ Basic Keymaps ]]

-- Keymaps for better default experience
-- See `:help vim.keymap.set()`
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
	callback = function()
	require("lint").try_lint()
	end,
})

-- multiple indent colors for indent-blankline.nvim
local highlight = {
	"RainbowRed",
	"RainbowYellow",
	"RainbowBlue",
	"RainbowOrange",
	"RainbowGreen",
	"RainbowViolet",
	"RainbowCyan",
}

-- This module contains a number of default definitions
local rainbow_delimiters = require 'rainbow-delimiters'

---@type rainbow_delimiters.config
vim.g.rainbow_delimiters = {
    strategy = {
        [''] = rainbow_delimiters.strategy['global'],
        vim = rainbow_delimiters.strategy['local'],
    },
    query = {
        [''] = 'rainbow-delimiters',
        lua = 'rainbow-blocks',
    },
    priority = {
        [''] = 110,
        lua = 210,
    },
    highlight = {
        'RainbowRed',
        'RainbowYellow',
        'RainbowBlue',
        'RainbowOrange',
        'RainbowGreen',
        'RainbowViolet',
        'RainbowCyan',
    },
}

local hooks = require "ibl.hooks"

-- create the highlight groups in the highlight setup hook, so they are reset
-- every time the colorscheme changes
hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
	vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
	vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
	vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
	vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
	vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
	vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
	vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
end)

require("ibl").setup { indent = { highlight = highlight } }

-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
	callback = function()
		vim.highlight.on_yank()
	end,
	group = highlight_group,
	pattern = '*',
})

-- [[ Configure Telescope ]]
-- See `:help telescope` and `:help telescope.setup()`
require('telescope').setup {
	defaults = {
		mappings = {
			i = {
				['<C-u>'] = false,
				['<C-d>'] = false,
			},
		},
	},
}

require('vgit').setup({
	keymaps = {
		['n <C-k>'] = function() require('vgit').hunk_up() end,
		['n <C-j>'] = function() require('vgit').hunk_down() end,
		['n <leader>gs'] = function() require('vgit').buffer_hunk_stage() end,
		['n <leader>gr'] = function() require('vgit').buffer_hunk_reset() end,
		['n <leader>gp'] = function() require('vgit').buffer_hunk_preview() end,
		['n <leader>gb'] = function() require('vgit').buffer_blame_preview() end,
		['n <leader>gf'] = function() require('vgit').buffer_diff_preview() end,
		['n <leader>gh'] = function() require('vgit').buffer_history_preview() end,
		['n <leader>gu'] = function() require('vgit').buffer_reset() end,
		['n <leader>gg'] = function() require('vgit').buffer_gutter_blame_preview() end,
		['n <leader>glu'] = function() require('vgit').buffer_hunks_preview() end,
		['n <leader>gls'] = function() require('vgit').project_hunks_staged_preview() end,
		['n <leader>gd'] = function() require('vgit').project_diff_preview() end,
		['n <leader>gq'] = function() require('vgit').project_hunks_qf() end,
		['n <leader>gx'] = function() require('vgit').toggle_diff_preference() end,
	},
	settings = {
		git = {
			cmd = 'git', -- optional setting, not really required
			fallback_cwd = vim.fn.expand("$HOME"),
			fallback_args = {
				"--git-dir",
				vim.fn.expand("$HOME/dots/yadm-repo"),
				"--work-tree",
				vim.fn.expand("$HOME"),
			},
		},
		hls = {
			GitBackground = 'Normal',
			GitHeader = 'NormalFloat',
			GitFooter = 'NormalFloat',
			GitBorder = 'LineNr',
			GitLineNr = 'LineNr',
			GitComment = 'Comment',
			GitSignsAdd = {
				gui = nil,
				fg = '#d7ffaf',
				bg = nil,
				sp = nil,
				override = false,
			},
			GitSignsChange = {
				gui = nil,
				fg = '#7AA6DA',
				bg = nil,
				sp = nil,
				override = false,
			},
			GitSignsDelete = {
				gui = nil,
				fg = '#e95678',
				bg = nil,
				sp = nil,
				override = false,
			},
			GitSignsAddLn = 'DiffAdd',
			GitSignsDeleteLn = 'DiffDelete',
			GitWordAdd = {
				gui = nil,
				fg = nil,
				bg = '#5d7a22',
				sp = nil,
				override = false,
			},
			GitWordDelete = {
				gui = nil,
				fg = nil,
				bg = '#960f3d',
				sp = nil,
				override = false,
			},
		},
		live_blame = {
			enabled = true,
			format = function(blame, git_config)
				local config_author = git_config['user.name']
				local author = blame.author
			if config_author == author then
					author = 'You'
				end
				local time = os.difftime(os.time(), blame.author_time)
				/ (60 * 60 * 24 * 30 * 12)
				local time_divisions = {
					{ 1, 'years' },
					{ 12, 'months' },
					{ 30, 'days' },
					{ 24, 'hours' },
					{ 60, 'minutes' },
					{ 60, 'seconds' },
				}
				local counter = 1
				local time_division = time_divisions[counter]
				local time_boundary = time_division[1]
				local time_postfix = time_division[2]
				while time < 1 and counter ~= #time_divisions do
					time_division = time_divisions[counter]
					time_boundary = time_division[1]
					time_postfix = time_division[2]
					time = time * time_boundary
					counter = counter + 1
				end
				local commit_message = blame.commit_message
				if not blame.committed then
					author = 'You'
					commit_message = 'Uncommitted changes'
					return string.format(' %s • %s', author, commit_message)
				end
				local max_commit_message_length = 255
				if #commit_message > max_commit_message_length then
					commit_message = commit_message:sub(1, max_commit_message_length) .. '...'
				end
				return string.format(
					' %s, %s • %s',
					author,
					string.format(
						'%s %s ago',
						time >= 0 and math.floor(time + 0.5) or math.ceil(time - 0.5),
						time_postfix
					),
					commit_message
				)
			end,
		},
		live_gutter = {
			enabled = true,
			edge_navigation = true, -- This allows users to navigate within a hunk
		},
		authorship_code_lens = {
			enabled = true,
		},
		scene = {
			diff_preference = 'unified', -- unified or split
			keymaps = {
				quit = 'q'
			}
		},
		diff_preview = {
			keymaps = {
				buffer_stage = 'S',
				buffer_unstage = 'U',
				buffer_hunk_stage = 's',
				buffer_hunk_unstage = 'u',
				toggle_view = 't',
			},
		},
		project_diff_preview = {
			keymaps = {
				buffer_stage = 's',
				buffer_unstage = 'u',
				buffer_hunk_stage = 'gs',
				buffer_hunk_unstage = 'gu',
				buffer_reset = 'r',
				stage_all = 'S',
				unstage_all = 'U',
				reset_all = 'R',
			},
		},
		project_commit_preview = {
			keymaps = {
				save = 'S',
			},
		},
		symbols = {
			void = '⣿',
		},
	}
})
require("noice").setup({
	lsp = {
		-- override markdown rendering so that **cmp** and other plugins use **Treesitter**
		override = {
			["vim.lsp.util.convert_input_to_markdown_lines"] = true,
			["vim.lsp.util.stylize_markdown"] = true,
			["cmp.entry.get_documentation"] = true,
		},
	},
	-- you can enable a preset for easier configuration
	presets = {
		bottom_search = true, -- use a classic bottom cmdline for search
		command_palette = true, -- position the cmdline and popupmenu together
		long_message_to_split = true, -- long messages will be sent to a split
		inc_rename = true, -- enables an input dialog for inc-rename.nvim
		lsp_doc_border = true, -- add a border to hover docs and signature help
	},
})

-- Enable telescope fzf native, if installed
pcall(require('telescope').load_extension, 'fzf')

-- See `:help telescope.builtin`
vim.keymap.set('n', '<leader>?', require('telescope.builtin').oldfiles, { desc = '[?] Find recently opened files' })
vim.keymap.set('n', '<leader><space>', require('telescope.builtin').buffers, { desc = '[ ] Find existing buffers' })
vim.keymap.set('n', '<leader>/', function()
	-- You can pass additional configuration to telescope to change theme, layout, etc.
	require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
		winblend = 10,
		previewer = false,
	})
	end, { desc = '[/] Fuzzily search in current buffer' })

vim.keymap.set('n', '<leader>gf', require('telescope.builtin').git_files, { desc = 'Search [G]it [F]iles' })
vim.keymap.set('n', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('n', '<leader>sh', require('telescope.builtin').help_tags, { desc = '[S]earch [H]elp' })
vim.keymap.set('n', '<leader>sw', require('telescope.builtin').grep_string, { desc = '[S]earch current [W]ord' })
vim.keymap.set('n', '<leader>sg', require('telescope.builtin').live_grep, { desc = '[S]earch by [G]rep' })
vim.keymap.set('n', '<leader>sd', require('telescope.builtin').diagnostics, { desc = '[S]earch [D]iagnostics' })
vim.keymap.set('n', '<leader>sr', require('telescope.builtin').resume, { desc = '[S]earch [R]esume' })
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- [[ Configure LSP ]]
--	This function gets run when an LSP connects to a particular buffer.
local on_attach = function(_, bufnr)
	local nmap = function(keys, func, desc)
		if desc then
			desc = 'LSP: ' .. desc
		end

		vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
	end

	nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
	nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

	nmap('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
	nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
	nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
	nmap('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
	nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
	nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

	-- See `:help K` for why this keymap
	nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
	nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

	-- Lesser used LSP functionality
	nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
	nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
	nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
	nmap('<leader>wl', function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end, '[W]orkspace [L]ist Folders')

	-- Create a command `:Format` local to the LSP buffer
	vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
		vim.lsp.buf.format()
		end, { desc = 'Format current buffer with LSP' })
end

vim.api.nvim_create_autocmd('LspAttach', {
	group = vim.api.nvim_create_augroup('UserLspConfig', {}),
	callback = function(ev)
		--enable omnifunc completion
		vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

		-- buffer local mappings
		local opts = { buffer = ev.buf }
		-- go to definition
		vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
		--puts doc header info into a float page
		vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)

		-- workspace management. Necessary for multi-module projects
		vim.keymap.set('n', '<space>wa', vim.lsp.buf.add_workspace_folder, opts)
		vim.keymap.set('n', '<space>wr', vim.lsp.buf.remove_workspace_folder, opts)
		vim.keymap.set('n', '<space>wl', function()
			print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end, opts)

		-- add LSP code actions
		vim.keymap.set({ 'n', 'v' }, '<space>ca', vim.lsp.buf.code_action, opts)

		-- find references of a type
		vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
	end,
})

-- document existing key chains
require('which-key').register {
	['<leader>c'] = { name = '[C]ode', _ = 'which_key_ignore' },
	['<leader>d'] = { name = '[D]ocument', _ = 'which_key_ignore' },
	['<leader>g'] = { name = '[G]it', _ = 'which_key_ignore' },
	['<leader>h'] = { name = 'More git', _ = 'which_key_ignore' },
	['<leader>r'] = { name = '[R]ename', _ = 'which_key_ignore' },
	['<leader>s'] = { name = '[S]earch', _ = 'which_key_ignore' },
	['<leader>w'] = { name = '[W]orkspace', _ = 'which_key_ignore' },
}

-- mason-lspconfig requires that these setup functions are called in this order
-- before setting up the servers.
require('mason').setup()
require('mason-lspconfig').setup()

local servers = {
	lua_ls = {
		Lua = {
			workspace = { checkThirdParty = false },
			telemetry = { enable = false },
		},
	},
}

-- Setup neovim lua configuration
require("neodev").setup({
	library = { plugins = { "nvim-dap-ui" }, types = true },
	...
})

-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

-- Ensure the servers above are installed
local mason_lspconfig = require 'mason-lspconfig'

mason_lspconfig.setup {
	ensure_installed = vim.tbl_keys(servers),
}

require('marks').setup {
	-- which builtin marks to show. default {}
	builtin_marks = { ".", "<", ">", "^" },
}

require 'lspconfig'.sourcekit.setup {
	cmd = { '$TOOLCHAIN_PATH/usr/bin/sourcekit-lsp' }
}

-- [[ Configure nvim-cmp ]]
-- See `:help cmp`
local cmp = require 'cmp'
local luasnip = require 'luasnip'
require('luasnip.loaders.from_vscode').lazy_load()
luasnip.config.setup {}

cmp.setup {
	snippet = {
		expand = function(args)
			luasnip.lsp_expand(args.body)
		end,
	},
	mapping = cmp.mapping.preset.insert {
		['<C-n>'] = cmp.mapping.select_next_item(),
		['<C-p>'] = cmp.mapping.select_prev_item(),
		['<C-d>'] = cmp.mapping.scroll_docs(-4),
		['<C-f>'] = cmp.mapping.scroll_docs(4),
		['<C-Space>'] = cmp.mapping.complete {},
		['<CR>'] = cmp.mapping.confirm {
			behavior = cmp.ConfirmBehavior.Replace,
			select = true,
		},
		['<Tab>'] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_next_item()
			elseif luasnip.expand_or_locally_jumpable() then
				luasnip.expand_or_jump()
			else
				fallback()
			end
		end, { 'i', 's' }),
		['<S-Tab>'] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_prev_item()
			elseif luasnip.locally_jumpable(-1) then
				luasnip.jump(-1)
			else
				fallback()
			end
		end, { 'i', 's' }),
	},
}


vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.do_filetype_lua = 1
