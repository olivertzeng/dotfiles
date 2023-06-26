" vim: set foldmethod=marker foldlevel=0:
" ============================================================================
" BASIC SETTINGS {{{
" ============================================================================

filetype plugin on
filetype indent on
language C
syntax on

set wildmenu
set nocompatible
set encoding=utf-8
set langmenu=zh_TW
let $LANG = 'zh_TW'
source $VIMRUNTIME/delmenu.vim
source $VIMRUNTIME/menu.vim

if has('win32') || has('win64')
  set runtimepath=~/.vim,$VIMRUNTIME
  set viminfo+=n$USERPROFILE
endif

if has("gui_running")
  set guioptions=gmrLt
else
  set t_Co=256
  set mouse=
endif

if (has("termguicolors"))
    set termguicolors
  endif

set foldcolumn=1
set noshowmode
set lazyredraw
set ttyfast
set nowb noswapfile smartcase nobackup cursorline ruler showcmd nowrap hlsearch incsearch
set nu rnu cindent ts=4 sw=4
set completeopt=menu
set updatetime=1200
set shiftwidth=4
"set diffopt+=vertical
set laststatus=2
" eliminating delays on ESC in vim and zsh
set timeout timeoutlen=1000 ttimeoutlen=0
set backspace=indent,eol,start
set listchars=tab:»·,trail:·
"set list
"hi SpecialKey ctermbg=red guibg=red

" set buffer hidden when unloaded
set hidden

set colorcolumn=80

if executable("rg")
  set grepprg=rg\ --ignore-file\ ~/.ignore\ --vimgrep
endif
command! -nargs=+ -bang -complete=file Grep execute 'silent lgrep<bang> <args>' | lopen | wincmd p | redraw!
command! -nargs=+ -bang -complete=file GrepAdd execute 'silent lgrepadd<bang> <args>' | lopen | wincmd p | redraw!


" }}}
" ============================================================================
" VIM-PLUG BLOCK {{{
" ============================================================================

silent! if plug#begin('~/.vim/plugged')

Plug 'easymotion/vim-easymotion'
Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-surround'
Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
" {{{
let NERDTreeQuitOnOpen = 1
" }}}
Plug 'tiagofumo/vim-nerdtree-syntax-highlight'
Plug 'itchyny/lightline.vim'
" {{{
let g:lightline = {
\   'active': {
\   'left': [ [ 'mode', 'paste', 'list', 'ignorecase' ],
\             [ 'gitbranch', 'readonly', 'modified', 'filename' ] ]
\ },
\ 'component': {
\   'ignorecase': '%{&ignorecase?"IGNORECASE":""}',
\ }
\}
function! LightlineReadonly()
  return &readonly && &filetype !~# '\v(help|vimfiler|unite)' ? 'RO' : ''
endfunction

let g:unite_force_overwrite_statusline = 0
let g:vimfiler_force_overwrite_statusline = 0
let g:lightline.colorscheme = 'gruvbox_material'
" }}}
Plug 'dimasg/vim-mark'
Plug 'sainnhe/gruvbox-material'
" {{{
let g:gruvbox_improved_strings = 1
let g:gruvbox_improved_warnings = 1
let g:gruvbox_transparent_bg = 1
let g:gruvbox_invert_signs = 1
" }}}
Plug 'sjl/gundo.vim'
Plug 'vimwiki/vimwiki'
Plug 'vim-scripts/a.vim'
" {{{
let g:alternateSearchPath = 'sfr:../source,sfr:../src,sfr:../include,sfr:../inc,sfr:../shared'
let g:alternateNoDefaultAlternate = 1
let g:alternateRelativeFiles = 1
" }}}
Plug 'will133/vim-dirdiff', { 'on': 'DirDiff' }
" {{{
let g:DirDiffExcludes = ".svn,.git,.*.swp,*.o,*.o.cmd,tags,cscope.*,*.rej,*.orig"
let g:DirDiffIgnore = "Id:,Revision:,Date:"
" }}}
Plug 'ryanoasis/vim-devicons'
Plug 'vim-scripts/vcscommand.vim'
" {{{
let VCSCommandDisableMappings = 1
let VCSCommandDeleteOnHide = 1
augroup VCSCommand
autocmd User VCSBufferCreated silent! nmap <unique> <buffer> q :bwipeout<cr>
autocmd User VCSVimDiffFinish wincmd p
augroup VCSCommand

function! s:vcs_vertical_annotate()
  let origin = ''

  if exists("g:VCSCommandSplit")
    let origin = g:VCSCommandSplit
  endif
  let g:VCSCommandSplit='vertical'

  VCSAnnotate
  set scrollbind
  wincmd p
  set scrollbind
  wincmd p

  if origin == ''
    unlet g:VCSCommandSplit
  elseif origin != g:VCSCommandSplit
    let g:VCSCommandSplit = origin
  endif
endfunction
command! VCSVerticalAnnotate call s:vcs_vertical_annotate()
" }}}

call plug#end()
endif


" }}}
" ============================================================================
" COLOR SCHEME {{{
" ============================================================================
" Important!!
if has('termguicolors')
  set termguicolors
endif
" For dark version.
set background=dark
" For better performance
let g:gruvbox_material_better_performance = 1
colorscheme gruvbox-material
" }}}
" ============================================================================
" AUTOCMD {{{
" ============================================================================

autocmd BufNewFile,BufRead *.aidl   setf java		" android interface definition language
autocmd FileType java set et nu rnu
autocmd FileType c,cpp,asm,make set nu rnu
autocmd BufEnter \c*.c,\c*.cc,\c*.cpp,\c*.h,\c*.s call s:set_project() " '\c' to igonre case
" Remember the line I was on when I repone a file
" http://askubuntu.com/questions/202075/how-do-i-get-vim-to-remember-the-line-i-was-on-when-i-reopen-a-file
autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
" Status line not appear sometimes with lazyredraw enabled
" https://stackoverflow.com/questions/39595011/vim-status-line-wont-immediately-appear-unless-i-press-a-key
autocmd VimEnter * redraw


" }}}
" ============================================================================
" MAPPINGS {{{
" ============================================================================

" set leader to ','
let mapleader=','
let g:mapleader=','

map <leader>tp :if &paste == '' <bar> set paste <bar> echo 'paste on' <bar> else <bar> set nopaste <bar> echo 'paste off' <bar> endif<cr>
map <leader>te :if &et == '' <bar> set et <bar> echo 'expandtab on' <bar> else <bar> set noet <bar> echo 'expandtab off' <bar> endif<cr>
map <leader>th :if &hls == '' <bar> set hls <bar> echo 'hlsearch on' <bar> else <bar> set nohls <bar> echo 'hlsearch off' <bar> endif<cr>
map <leader>tl :if &list == '' <bar> set list <bar> echo 'list mode on' <bar> else <bar> set nolist <bar> echo 'list mode off' <bar> endif<cr>
map <leader>tm :if &mouse == '' <bar> set mouse=a <bar> echo 'mouse on' <bar> else <bar> set mouse= <bar> echo 'mouse off' <bar> endif<cr>
map <leader>tn :set nu! rnu!<cr>
map <leader>ti :if &ic == '' <bar> set ic <bar> echo 'ignore case' <bar> else <bar> set noic <bar> echo 'case sensitive' <bar> endif<cr>
map <leader>td :if &diff == '' <bar> diffthis <bar> echo 'diff on' <bar> else <bar> diffoff <bar> echo 'diff off' <bar> endif<cr>
map <leader>ts :SignifyToggle<cr>

nnoremap <silent> <f4>   :close<cr>
nnoremap <silent> <f5>   :NERDTreeToggle %:p:h<cr>
"nnoremap <silent> <f6>   :let &hlsearch = !&hlsearch<cr>
nnoremap <silent> <f7>   :lprevious<cr>
nnoremap <silent> <s-f7> :cprevious<cr>
nnoremap <silent> <f8>   :lnext<cr>
nnoremap <silent> <s-f8> :cnext<cr>
nnoremap <silent> <f12>  :TagbarToggle<cr>
nnoremap <silent> <c-]>  :tjump<cr>
"nnoremap <silent> <c-k>  :execute (line('.')-1>line('w0')) ? (line('.')+line('w0'))/2 : line('.')-1<cr>
"nnoremap <silent> <c-j>  :execute (line('.')+1<line('w$')) ? (line('.')+line('w$'))/2 : line('.')+1<cr>
nnoremap <silent> <s-w>  :let tmp_reg=@/<cr>/\<<cr>:let @/=tmp_reg<cr>	" search for next word
nnoremap <silent> <s-b>  :let tmp_reg=@/<cr>?\<<cr>:let @/=tmp_reg<cr>	" search for previous word
"nnoremap <silent> <c-w>o :if &diff == '' <bar> only <bar> else <bar> wincmd p <bar> close <bar> endif<cr>
nnoremap <silent> <c-w>o :only <bar> if &diff != '' <bar> diffoff <bar> endif<cr>
" Bash like keys for the command line
cnoremap <c-a> <home>
cnoremap <c-e> <end>
cnoremap <m-b> <s-left>
cnoremap <m-f> <s-right>
" Reselect visual block after indent/outdent
vnoremap < <gv
vnoremap > >gv
nnoremap gb :ls<CR>:b<Space>

" fzf
nnoremap <silent> <leader>ff	:GFiles<cr>
nnoremap <silent> <leader>ft	:BTags<cr>
nnoremap <silent> <leader>fs	:Tags<cr>
nnoremap <silent> <leader>fl	:BLines<cr>
nnoremap <silent> <leader>fc	:BCommits<cr>

" easymotion
nmap s <Plug>(easymotion-s2)
nmap t <Plug>(easymotion-t2)

nmap <leader>vd :VCSVimDiff<cr>
nmap <leader>va :VCSVerticalAnnotate<cr>
nmap <leader>vl :VCSLog <c-r>=matchstr(getline('.'), '^\s*\(\x\+\)')<cr><cr>

" Setup meta keys
" {{{
" Fix meta-keys that break out of Insert mode
" https://vim.fandom.com/wiki/Fix_meta-keys_that_break_out_of_Insert_mode
if has("unix")
  execute "set <M-1>=\e1"
  execute "set <M-2>=\e2"
  execute "set <M-3>=\e3"
  execute "set <M-4>=\e4"
  execute "set <M-5>=\e5"
  execute "set <M-6>=\e6"
  execute "set <M-7>=\e7"
  execute "set <M-8>=\e8"
  execute "set <M-9>=\e9"
  execute "set <M-0>=\e0"
  execute "set <M-,>=\e,"
  execute "set <M-.>=\e."
  execute "set <M-b>=\eb"
  execute "set <M-f>=\ef"
elseif has("win32")
  execute "set <M-1>=±"
  execute "set <M-2>=²"
  execute "set <M-3>=³"
  execute "set <M-4>=´"
  execute "set <M-5>=µ"
  execute "set <M-6>=¶"
  execute "set <M-7>=·"
  execute "set <M-8>=¸"
  execute "set <M-9>=¹"
  execute "set <M-0>=°"
  execute "set <M-,>=¬"
  execute "set <M-.>=®"
endif

" The alt (option) key on macs now behaves like the 'meta' key. This means we
" can now use <m-x> or similar as maps. This is buffer local, and it can easily
" be turned off when necessary (for instance, when we want to input special
" characters) with :set nomacmeta.
if has("gui_macvim")
  set macmeta
endif
" }}}
" }}}
" ============================================================================
" PROJECT SETTINGS {{{
" ============================================================================

nnoremap <C-]>  :lcs find g <C-R>=expand("<cword>")<CR><CR>
nnoremap <C-[>s :lcs find s <C-R>=expand("<cword>")<CR><CR>
nnoremap <C-[>g :lcs find g <C-R>=expand("<cword>")<CR><CR>
nnoremap <C-[>d :lcs find d <C-R>=expand("<cword>")<CR><CR>
nnoremap <C-[>c :lcs find c <C-R>=expand("<cword>")<CR><CR>
nnoremap <C-[>t :lcs find t <C-R>=expand("<cword>")<CR><CR>
nnoremap <C-[>e :lcs find e <C-R>=expand("<cword>")<CR><CR>
nnoremap <C-[>f :lcs find f <C-R>=expand("<cfile>")<CR><CR>
nnoremap <C-[>i :lcs find i <C-R>=expand("<cfile>")<CR><CR>
nnoremap <C-[>a :lcs find a <C-R>=expand("<cword>")<CR><CR>

let current_project = ''
let projects = []
" global or gtags not support caller search (only support reference search)
" So, you can search where a function be called (referenced), but don't know
" which function calls the searched function
let use_cscope = 1 " 1: cscope; 0: gtags

if (g:use_cscope == 1)
  let cs_prg = "cscope"
  let cs_db = "cscope.out"
else
  let cs_prg = "gtags-cscope"
  let cs_db = "GTAGS"
endif

execute "set cscopeprg=" . g:cs_prg
execute "set cscopequickfix=s-,c-,d-,i-,t-,e-"
execute "set cscopetag"
execute "set cscopetagorder=0"
execute "cs kill -1"

function! s:set_project() " {{{
  "let path = substitute(expand("%:p:h"), "\\", "/", "g")
  let path = resolve(expand("%:p:h"))

  " igonre existing project
  for project in g:projects
    if (path =~ project)
      return
    endif
  endfor

  " search a readable database
  let db_found = 0
  while (isdirectory(path))
    if filereadable(path . '/' . g:cs_db)
      let db_found = 1
      break
    elseif (path == '/')
      break
    endif
    let path = fnamemodify(path, ":h")
  endwhile

  if (db_found)
    let g:current_project = path
    call add(g:projects, g:current_project)

    execute "set tags+=" . g:current_project . "/tags"
    execute "cs add " . g:current_project . '/' . g:cs_db
  endif
endfunction " }}}


" }}}
" ============================================================================
" TAB SETTINGS {{{
" ============================================================================

noremap <M-1> 1gt
noremap <M-2> 2gt
noremap <M-3> 3gt
noremap <M-4> 4gt
noremap <M-5> 5gt
noremap <M-6> 6gt
noremap <M-7> 7gt
noremap <M-8> 8gt
noremap <M-9> 9gt
noremap <M-0> 10gt
noremap <M-,> :execute "silent! tabmove " . (tabpagenr()-2)<cr>
noremap <M-.> :execute "silent! tabmove " . (tabpagenr()+1)<cr>

noremap th :tabprevious<cr>
noremap tl :tabnext<cr>
noremap tn :tabnew<cr>
noremap tc :tabclose<cr>
noremap ts :tab split <bar> if &diff != '' <bar> diffoff <bar> endif<cr>

" }}}
" ============================================================================

