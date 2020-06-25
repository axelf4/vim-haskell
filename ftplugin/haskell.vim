" Vim filetype plugin
" Language: Haskell
" Author: Axel Forsman <axelsfor@gmail.com>

if exists('b:did_ftplugin') | finish | endif
let [b:did_ftplugin, b:did_indent] = [1, 1]

setlocal tabstop=8 shiftwidth=2 expandtab
setlocal indentexpr=GetHaskellIndent() indentkeys=!^F,o,O

setlocal comments=:--,s:{-,e:-} commentstring=--\ %s

if !hasmapto('<Plug>HaskellIndentN', 'i')
	imap <buffer> <C-T> <Plug>HaskellIndentN
endif
if !hasmapto('<Plug>HaskellIndentP', 'i')
	imap <buffer> <C-D> <Plug>HaskellIndentP
endif
imap <buffer> <expr> <Tab> <SID>BeforeNonBlank() ? "\<Plug>HaskellIndentN" : "\<Tab>"
imap <buffer> <expr> <BS> <SID>BeforeNonBlank() && col('.') > 1 ? "\<Plug>HaskellIndentP" : "\<BS>"
inoremap <buffer> <unique> <expr> <Plug>HaskellIndentN <SID>CycleIndentExpr(1)
inoremap <buffer> <unique> <expr> <Plug>HaskellIndentP <SID>CycleIndentExpr(-1)

" Haskell indenting is ambiguous
noremap <buffer> = <Nop>
inoremap <buffer> <C-F> <Nop>

let b:undo_ftplugin = 'setlocal tabstop< shiftwidth< expandtab<
			\ indentexpr< indentkeys<
			\ comments< commentstring<
			\| iunmap <buffer> <Plug>HaskellIndentN| iunmap <buffer> <Plug>HaskellIndentP
			\| iunmap <buffer> <C-T>| iunmap <buffer> <C-D>
			\| iunmap <buffer> <Tab>| iunmap <buffer> <BS>
			\| unmap <buffer> =| iunmap <buffer> <C-F>'

if exists("*GetHaskellIndent") | finish | endif
const s:keepcpo = &cpo | set cpo&vim

const s:endtoken = -1
" End of a layout list
const s:layoutEnd = -2
" A new item in a layout list
const s:layoutItem = -3
const [s:value,
			\ s:operator,
			\ s:comma, s:semicolon, s:lbrace, s:rbrace,
			\ s:lparen, s:rparen, s:lbracket, s:rbracket,
			\ s:if, s:then, s:else, s:let, s:in, s:do, s:case, s:of, s:where]
			\ = range(1, 19)

" Regex for matching tokens
" Note: Vim regexes only supports nine sub-Patterns...
"
" Keywords
let s:search_pat = '\C\(if\|then\|else\|let\|in\|do\|case\|of\|where\)[[:alnum:]''_]\@!'
" Values
let s:search_pat ..= '\|\([[:alnum:]''_]\+\|"\%(\\\_s\+\\\?\|\\\S\|[^"]\)*\%("\|\_$\)\)'
" Special single-character symbols
let s:search_pat ..= '\|\([,;(){}[\]]\)'
" Operators
let s:search_pat ..= '\|\([-:!#$%&*+./<=>?@\\\\^|~`]\+\)'

const s:str2Tok = {
			\ 'if': s:if, 'then': s:then, 'else': s:else, 'let': s:let, 'in': s:in,
			\ 'do': s:do, 'case': s:case, 'of': s:of, 'where': s:where,
			\ ',': s:comma, ';': s:semicolon, '{': s:lbrace, '}': s:rbrace,
			\ '(': s:lparen, ')': s:rparen, '[': s:lbracket, ']': s:rbracket,
			\ }

" Lex the next token and move the cursor to its start.
" Returns "s:endtoken" if no token was found.
function s:LexToken(stopline, at_cursor) abort
	let match = search(s:search_pat, (a:at_cursor ? 'c' : '') .. 'pWz', a:stopline, 0,
				\ {-> synID(line('.'), col('.'), 1)->synIDattr('name') =~# 'hs\%(Line\|Block\)Comment'})
	return match == 2 ? s:str2Tok[expand('<cword>')]
				\ : match == 3 ? s:value
				\ : match == 4 ? s:str2Tok[getline('.')[col('.') - 1]]
				\ : match == 5 ? s:operator
				\ : s:endtoken
endfunction

" Note: May move the cursor.
function HaskellParse() abort
	let initial_line = line('.')

	" Move to first line with zero indentation
	normal! -
	if !search('^\S\|\%^', 'bcW', 0, 0, {-> synID(line('.'), col('.'), 1)->synIDattr('name')
				\ =~# 'hs\%(Line\|Block\)Comment\|hsString'})
		call cursor(1, 1)
	endif

	if line('.') == initial_line | return [0] | endif " At beginning of file

	let parser = #{token: v:null, nextToken: v:null,
				\ currentLine: 1, currentCol: 1,
				\ initial_line: initial_line,
				\ layoutCtx: 0,
				\ indentations: [0],
				\ following: s:endtoken,
				\ }

	function parser.next() abort
		if self.token is s:endtoken | return s:endtoken | endif

		" If has pending token: Return it
		if self.nextToken isnot v:null
			let self.token = self.nextToken
			let self.nextToken = v:null
			return self.token
		endif

		let [prevLine, prevCol] = [self.currentLine, self.currentCol]
		" Lex the next token and jump to its start
		let self.token = s:LexToken(self.initial_line, self.token is v:null)
		if line('.') == self.initial_line
			let self.following = self.token
		elseif self.token is s:endtoken
			let self.following = s:LexToken(0, 0) " Zero stopline means absence
		endif
		if line('.') >= self.initial_line
			let self.token = s:endtoken
		endif
		if self.token isnot s:endtoken
			let [self.currentLine, self.currentCol] = [line('.'), col('.')]
		endif

		" Layout rule if implicit layout is active
		if prevLine < self.currentLine && self.layoutCtx > 0
			let layoutIndent = self.layoutCtx

			let self.nextToken = self.token
			if self.currentCol < layoutIndent
				let self.token = s:layoutEnd
			elseif self.currentCol == layoutIndent
				let self.token = s:layoutItem
			else
				let self.nextToken = v:null
			endif
		endif

		echom "parsed:" self.token

		return self.token
	endfunction

	function parser.peek() abort
		" TODO Just lex token initially, to make sure it is never null
		return self.token is v:null ? self.next() : self.token
	endfunction

	let result = s:TopLevel(parser)
	return parser.indentations->sort('n')
endfunction

" s:retNone is same as s:retError except not even the first token matched.
" TODO Remove s:retError and just skip forward instead
" FIXME Remove s:retFinished too, and instead do p.peek() == s:endtoken?
const [s:retOk, s:retNone, s:retError, s:retFinished] = [1, 2, 3, 4]

function s:Token(token) abort
	function! s:TokenRet(p) abort closure
		if a:p.peek() is s:endtoken | return #{status: s:retFinished} | endif
		if a:p.peek() is a:token
			call a:p.next()
			return #{status: s:retOk}
		endif
		return #{status: s:retNone}
	endfunction
	return funcref('s:TokenRet')
endfunction

function s:Or(...) abort
	let alts = a:000
	function! s:OrRet(p) abort closure
		for Alt in alts
			let result = Alt(a:p)
			let status = result.status
			if status == s:retOk || status == s:retFinished || status == s:retError
				return result
			endif
		endfor
		return #{status: s:retNone}
	endfunction
	return funcref('s:OrRet')
endfunction

function s:FromDict(dict) abort
	function! s:FromDictRet(p) abort closure
		if a:p.peek() == s:endtoken | return #{status: s:retFinished} | endif
		let Parser = a:dict->get(a:p.peek(), v:null)
		if Parser is v:null | return #{status: s:retNone} | endif
		return Parser(a:p)
	endfunction
	return funcref('s:FromDictRet')
endfunction

function s:Seq(...) abort
	let alts = a:000
	function! s:SeqRet(p) abort closure
		for Alt in alts
			let result = Alt(a:p)
			let status = result.status
			if status == s:retNone || status == s:retFinished || status == s:retError
				return result
			endif
		endfor
		return #{status: s:retOk}
	endfunction
	return funcref('s:SeqRet')
endfunction

function s:Many(Parser) abort
	function! s:ManyRet(p) closure
		let first = 1
		while 1
			let result = a:Parser(a:p)
			let status = result.status
			if status == s:retNone
				return #{status: first ? s:retNone : s:retOk}
			endif
			if status == s:retFinished || status == s:retError
				return result
			endif
			let first = 0
		endwhile
	endfunction
	return funcref('s:ManyRet')
endfunction

function s:Lazy(Cb) abort
	let Parser = v:null
	function! s:LazyRet(p) abort closure
		if Parser is v:null | let Parser = a:Cb() | endif
		return Parser(a:p)
	endfunction
	return funcref('s:LazyRet')
endfunction

let s:Empty = {-> #{status: s:retOk}}

function s:Opt(Parser) abort
	return s:Or(a:Parser, s:Empty)
endfunction

function s:Layout(Item) abort
	function! s:LayoutRet(p) abort closure
		let token = a:p.peek()
		if token is s:lbrace
			throw 'Not yet implemented'
		elseif token == s:endtoken
			eval a:p.indentations->add(indent(a:p.currentLine) + shiftwidth())
			return #{status: s:retFinished}
		else
			let prevLayoutCtx = a:p.layoutCtx
			" Store indentation column of the enclosing layout context
			let a:p.layoutCtx = a:p.currentCol " FIXME: Handle tabs

			while 1
				let result = a:Item(a:p)
				let status = result.status
				if status == s:retNone | break | endif " parse-error clause

				let following = a:p.peek()
				if following == s:endtoken
					eval a:p.indentations->add(a:p.layoutCtx - 1)
					return #{status: s:retFinished}
				endif
				if following == s:layoutEnd || following == s:layoutItem || following == s:semicolon
					call a:p.next()
				endif
				if !(following == s:layoutItem || following == s:semicolon)
					break
				endif
			endwhile

			let a:p.layoutCtx = prevLayoutCtx
		endif

		return #{status: s:retOk}
	endfunction
	return funcref('s:LayoutRet')
endfunction

function s:Sep(Parser, sep) abort
	function! s:SepRet(p) abort closure
		let result = a:Parser(a:p)
		let status = result.status
		if status == s:retNone | return #{status: s:retNone} | endif
		if status == s:retFinished | return #{status: s:retFinished} | endif

		while a:p.peek() == a:sep
			call a:p.next()

			let result = a:Parser(a:p)
			let status = result.status
			if status == s:retNone | break | endif
			if status == s:retFinished | return #{status: s:retFinished} | endif
		endwhile

		return #{status: s:retOk}
	endfunction
	return funcref('s:SepRet')
endfunction

function s:AddIndent(Parser) abort
	function! s:AddIndentRet(p) abort closure
		call a:p.peek() " TODO Unnecessary?
		let currentIndent = max([indent(a:p.currentLine), a:p.layoutCtx - 1])
		let result = a:Parser(a:p)
		if result.status == s:retFinished
			eval a:p.indentations->add(currentIndent + shiftwidth())
		endif
		return result
	endfunction
	return funcref('s:AddIndentRet')
endfunction

let s:ExpressionLayout = s:Layout(s:Lazy({-> s:Expression}))
let s:DeclarationLayout = s:Layout(s:Lazy({-> s:Declaration}))

let s:expression_list = {
			\ s:value: s:Token(s:value),
			\ s:operator: s:Token(s:operator),
			\ s:let: s:Token(s:let)->s:Seq(s:DeclarationLayout, s:Token(s:in), s:Lazy({-> s:Expression})),
			\ s:if: s:Token(s:if)->s:Seq(s:Lazy({-> s:Expression}), s:Token(s:then), s:Lazy({-> s:Expression}), s:Seq(s:Token(s:else), s:Lazy({-> s:Expression}))->s:Opt()),
			\ s:do: s:Token(s:do)->s:Seq(s:ExpressionLayout),
			\ s:case: s:Token(s:case)->s:Seq(s:Lazy({-> s:Expression}), s:Token(s:of), s:ExpressionLayout),
			\ s:lparen: s:Seq(s:Token(s:lparen), s:Lazy({-> s:Expression})->s:Sep(s:comma), s:Token(s:rparen)),
			\ s:lbracket: s:Seq(s:Token(s:lbracket), s:Lazy({-> s:Expression})->s:Sep(s:comma), s:Token(s:rbracket)),
			\ s:lbrace: s:Seq(s:Token(s:lbrace), s:Lazy({-> s:Expression})->s:Sep(s:comma), s:Token(s:rbrace)),
			\ }

let s:Expression = s:AddIndent(s:FromDict(s:expression_list)->s:Many())

let s:Declaration = s:Token(s:value)->s:Sep(s:comma)->s:Seq(s:Expression,
			\ s:Opt(s:Token(s:where)->s:Seq(s:DeclarationLayout)))

" Parse topdecls.
let s:TopLevel = s:Declaration

" Return whether all characters to the left of the cursor are blank.
function s:BeforeNonBlank() abort
	return col('.') <= indent(line('.')) + 1 " FIXME
endfunction

" Set direction for indent cycling and return RHS for indenting.
" Note: Leaving Insert mode with blank line would reset indent.
function s:CycleIndentExpr(dir) abort
	let s:indent_dir = a:dir
	return "\<C-F>"
endfunction

let s:indent_dir = 0

function GetHaskellIndent() abort
	let prevIndent = indent(s:indent_dir ? v:lnum : prevnonblank(v:lnum))
	let indentations = HaskellParse()

	let [dir, s:indent_dir] = [s:indent_dir, 0]
	if dir >= 0
		for indent in indentations
			if indent > prevIndent | return indent | endif
		endfor
		return indentations[-1]
	else
		for indent in indentations->reverse()
			if indent < prevIndent | return indent | endif
		endfor
		return indentations[-1] " List was reversed in-place
	endif
endfunction

let &cpo = s:keepcpo | unlet s:keepcpo
