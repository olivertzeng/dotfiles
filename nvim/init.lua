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
			removed = gitsigns.removed
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
			{ 'j-hui/fidget.nvim', tag = 'legacy', opts = {} },

			-- Additional lua configuration, makes nvim stuff amazing!
			'folke/neodev.nvim',
		},
	},
	{ "ellisonleao/glow.nvim", config = true, cmd = "Glow" },
	{
		'akinsho/git-conflict.nvim',
		version = "*",
		config = true,
	},

	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		indent = { enable = true },
	},

	{
		'glepnir/template.nvim',
		cmd = { 'Template' },
		config = function()
			require('template').setup({
				temp_dir = '~/.config/nvim/templates',
				author = 'Oliver Tzeng',
				email = 'olivertzeng@proton.me',
				vim.keymap.set('n', '<Leader>t', function()
					vim.fn.feedkeys(':Template ')
				end, { remap = true })
			})
		end
	},

	{
		"folke/noice.nvim",
		event = "VeryLazy",
		view = "cmdline",
		opts = {
			-- add any options here
		},
		dependencies = {
			-- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
			"MunifTanjim/nui.nvim",
			-- OPTIONAL:
			--	 `nvim-notify` is only needed, if you want to use the notification view.
			--	 If not available, we use `mini` as the fallback
			"rcarriga/nvim-notify",
		}
	},
	{
		"startup-nvim/startup.nvim",
		requires = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
		config = function()
			require "startup".setup({ theme = "dashboard" })
		end
	},
{"Dosx001/cmp-commit", requires = "hrsh7th/nvim-cmp"},
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
		config = function() require('guess-indent').setup {} end,
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
		'rafamadriz/friendly-snippets',
		'mireq/luasnip-snippets',
		dependencies = { 'L3MON4D3/LuaSnip' },
		init = function()
			-- Mandatory setup function
			require('luasnip_snippets.common.snip_utils').setup()
		end

	},
	{
		-- Autocompletion
		'hrsh7th/nvim-cmp',
		version = false, -- last release is way too old
		dependencies = {
			-- Snippet Engine & its associated nvim-cmp source
			'L3MON4D3/LuaSnip',
			'saadparwaiz1/cmp_luasnip',

			-- Adds LSP completion capabilities
			'hrsh7th/cmp-nvim-lsp',
			'hrsh7th/cmp-buffer',
			'hrsh7th/cmp-path',
			'hrsh7th/cmp-cmdline',
			'hrsh7th/cmp-emoji',
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
					{ name = "nvim_lsp" },
					{ name = "path" },
				}, {
					{ name = "buffer" },
				}),
				cmp.setup.filetype('gitcommit', {
					sources = {
						{ name = 'commit' }
					}
				}),
				formatting = {
					format = function(_, item)
						local icons = require("lazyvim.config").icons.kinds
						if icons[item.kind] then
							item.kind = icons[item.kind] .. item.kind
						end
						return item
					end,
				},
				experimental = {
					ghost_text = {
						hl_group = "CmpGhostText",
					},
				},
				sorting = defaults.sorting,
			}
		end,
		---@param opts cmp.ConfigSchema
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
					["<leader>u"] = { name = "+ui" },
					["<leader>w"] = { name = "+windows" },
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
		{ 'numToStr/Comment.nvim', opts = {} },
		{ "rcarriga/nvim-dap-ui",  dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" } },
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

	mason_lspconfig.setup_handlers {
		function(server_name)
			require('lspconfig')[server_name].setup {
				capabilities = capabilities,
				on_attach = on_attach,
				settings = servers[server_name],
				filetypes = (servers[server_name] or {}).filetypes,
			}
		end,
	}

	require('marks').setup {
		-- whether to map keybinds or not. default true
		default_mappings = true,
		-- which builtin marks to show. default {}
		builtin_marks = { ".", "<", ">", "^" },
		-- whether movements cycle back to the beginning/end of buffer. default true
		cyclic = true,
		-- whether the shada file is updated after modifying uppercase marks. default false
		force_write_shada = false,
		-- how often (in ms) to redraw signs/recompute mark positions.
		-- higher values will have better performance but may cause visual lag,
		-- while lower values may cause performance penalties. default 150.
		refresh_interval = 250,
		-- sign priorities for each type of mark - builtin marks, uppercase marks, lowercase
		-- marks, and bookmarks.
		-- can be either a table with all/none of the keys, or a single number, in which case
		-- the priority applies to all marks.
		-- default 10.
		sign_priority = { lower = 10, upper = 15, builtin = 8, bookmark = 20 },
		-- disables mark tracking for specific filetypes. default {}
		excluded_filetypes = {},
		-- marks.nvim allows you to configure up to 10 bookmark groups, each with its own
		-- sign/virttext. Bookmarks can be used to group together positions and quickly move
		-- across multiple buffers. default sign is '!@#$%^&*()' (from 0 to 9), and
		-- default virt_text is "".
		bookmark_0 = {
			sign = "⚑",
			virt_text = "hello world",
			-- explicitly prompt for a virtual line annotation when setting a bookmark from this group.
			-- defaults to false.
			annotate = false,
		},
		mappings = {}
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
		sources = cmp.config.sources({
			{ name = 'nvim_lsp' },
			{ name = 'luasnip' },
			{ name = 'emoji' },
			{ name = 'buffer' },
		})
	}


	vim.g.mapleader = ' '
	vim.g.maplocalleader = ' '
	vim.g.do_filetype_lua = 1
