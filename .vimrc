" 基础设置
set nocompatible
syntax enable
filetype plugin indent on

set encoding=utf-8
set number
set cursorline
set ruler
set showcmd
set wildmenu

" 缩进
set autoindent
set smartindent
set expandtab
set tabstop=4
set softtabstop=4
set shiftwidth=4

" 搜索
set ignorecase
set smartcase
set incsearch
set hlsearch

" 编辑体验
set backspace=indent,eol,start
set scrolloff=5
set splitbelow
set splitright
set nowrap

" 禁止 Vim 接管鼠标
" 鼠标拖动将选择终端文字，不会进入 Visual 模式
set mouse=

" 常用快捷键
let mapleader=" "
nnoremap <leader>w :write<CR>
nnoremap <leader>q :quit<CR>
nnoremap <Esc><Esc> :nohlsearch<CR>
