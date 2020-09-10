" Vim indent file
" Language: Haskell

if exists('b:did_indent') | finish | endif
let b:did_indent = 1

setlocal indentexpr=GetHaskellIndent() indentkeys=0},0;,0),0],0,,!^F,o,O

if !hasmapto('<Plug>HaskellIndentN', 'i')
	imap <buffer> <C-T> <Plug>HaskellIndentN
endif
if !hasmapto('<Plug>HaskellIndentP', 'i')
	imap <buffer> <C-D> <Plug>HaskellIndentP
endif
inoremap <buffer> <unique> <expr> <Plug>HaskellIndentN <SID>CycleIndentExpr(1)
inoremap <buffer> <unique> <expr> <Plug>HaskellIndentP <SID>CycleIndentExpr(-1)

let b:undo_indent = 'setlocal indentexpr< indentkeys<
			\| iunmap <buffer> <Plug>HaskellIndentN| iunmap <buffer> <Plug>HaskellIndentP
			\| iunmap <buffer> <C-T>| iunmap <buffer> <C-D>'

if exists("*GetHaskellIndent") | finish | endif

let s:indent_dir = 0

" Set direction for indent cycling and return RHS for indenting.
"
" Note: Leaving Insert mode on blank line would reset indent.
function s:CycleIndentExpr(dir) abort
	let s:indent_dir = a:dir
	return mode() ==# 'i' ? "\<C-F>" : '=='
endfunction

function GetHaskellIndent() abort
	let prevIndent = indent(s:indent_dir ? v:lnum : prevnonblank(v:lnum))
	let indentations = haskell#Parse()

	let [dir, s:indent_dir] = [s:indent_dir, 0]
	if dir >= 0
		for indent in indentations
			if indent > prevIndent | return indent | endif
		endfor
		return indentations[-1]
	else
		for indent in reverse(indentations)
			if indent < prevIndent | return indent | endif
		endfor
		return indentations[-1] " List was reversed in-place
	endif
endfunction
