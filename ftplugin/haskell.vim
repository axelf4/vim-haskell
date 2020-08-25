" Vim filetype plugin
" Language: Haskell
" Author: Axel Forsman <axelsfor@gmail.com>

if exists('b:did_ftplugin') | finish | endif
let b:did_ftplugin = 1

setlocal tabstop=8 shiftwidth=2 expandtab
setlocal comments=:--,s:{-,e:-} commentstring=--\ %s

let b:undo_ftplugin = 'setlocal tabstop< shiftwidth< expandtab<
			\ comments< commentstring<'
