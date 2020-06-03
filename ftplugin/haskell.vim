" Vim filetype plugin
" Language: Haskell
" Author: Axel Forsman <axelsfor@gmail.com>

if exists('b:did_ftplugin') | finish | endif
let [b:did_ftplugin, b:did_indent] = [1, 1]

setlocal tabstop=8 shiftwidth=2 expandtab
setlocal indentexpr=GetHaskellIndent() indentkeys=0},0),0],0,,0;!^F,o,O

inoremap <buffer> <silent> <expr> <Tab> <SID>TabBSExpr("\<Tab>")
inoremap <buffer> <silent> <expr> <BS> <SID>TabBSExpr("\<BS>")
inoremap <buffer> <silent> <expr> <C-T> <SID>TabBSExpr("\<C-T>")
inoremap <buffer> <silent> <expr> <C-D> <SID>TabBSExpr("\<C-D>")
" Haskell indenting is ambiguous
nnoremap <buffer> = <Nop>
inoremap <buffer> <C-F> <Nop>

if exists("*GetHaskellIndent") | finish | endif
let s:keepcpo = &cpo | set cpo&vim

const s:endtoken = -1
" End of a layout list
const s:layoutEnd = -2
" A new item in a layout list
const s:layoutItem = -3
const [s:value,
			\ s:lbrace, s:semicolon,
			\ s:operator,
			\ s:if, s:then, s:else, s:let, s:in, s:do, s:case, s:of, s:where]
			\ = range(1, 13)

" Shiftwidth
const s:ind = 2

" Regex for matching tokens
" Note: Vim regexes only supports nine sub-Patterns...
"
" Keywords
let s:search_pat = '\C\(if\|then\|else\|let\|in\|do\|case\|of\|where\)[[:alnum:]''_]\@!'
" Values
let s:search_pat ..= '\|\([[:alnum:]''_]\+\)'
" Braces and semicolons
let s:search_pat ..= '\|\({\)\|\(;\)'
" Special symbols
" let s:search_pat ..= '\|\%(\(=\)\)[-:!#$%&*+./<=>?@\\\\^|~]\@!'
" Operators
let s:search_pat ..= '\|\([-:!#$%&*+./<=>?@\\\\^|~`]\+\)'

let s:str2Tok = {
			\ 'if': s:if, 'then': s:then, 'else': s:else, 'let': s:let, 'in': s:in,
			\ 'do': s:do, 'case': s:case, 'of': s:of, 'where': s:where,
			\ }

" Lex the next token and move the cursor to its start.
" Returns "s:endtoken" if no token was found.
function s:LexToken(stopline, at_cursor) abort
	while 1
		let match = search(s:search_pat, (a:at_cursor ? 'c' : '') .. 'pWz', a:stopline)
		if match == 0
			return s:endtoken
		endif
		if synID(line('.'), col('.'), 1)->synIDattr('name') =~# 'hs\%(Line\|Block\)Comment'
			continue
		endif
		if match == 2 " Keyword
			return s:str2Tok[expand('<cword>')]
		endif
		return match - 1 - 1
	endwhile
endfunction

" Note: May move the cursor.
function HaskellParse() abort
	let initial_line = line('.')

	" Move to first line with zero indentation
	while 1
		let match = search('^\S\|\%^', 'bW')
		if synID(line('.'), col('.'), 1)->synIDattr('name')
					\ !~# 'hs\%(Line\|Block\)Comment\|hsString'
					\ || line('.') <= 1
			break
		endif
	endwhile

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

function s:AddIndent(Parser) abort
	function s:AddIndentRet(p) abort closure
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

" TODO Should only declaration be allowed to have while?

let s:expression_list = {
			\ s:value: s:Token(s:value),
			\ s:operator: s:Token(s:operator),
			\ s:let: s:Token(s:let)->s:Seq(s:DeclarationLayout, s:Token(s:in), s:Lazy({-> s:Expression})),
			\ s:where: s:Token(s:where)->s:Seq(s:DeclarationLayout),
			\ s:if: s:Token(s:if)->s:Seq(s:Lazy({-> s:Expression}), s:Token(s:then), s:Lazy({-> s:Expression}), s:Seq(s:Token(s:else), s:Lazy({-> s:Expression}))->s:Opt()),
			\ s:do: s:Token(s:do)->s:Seq(s:ExpressionLayout),
			\ s:case: s:Token(s:case)->s:Seq(s:Lazy({-> s:Expression}), s:Token(s:of), s:ExpressionLayout),
			\ }

let s:Expression = s:AddIndent(s:FromDict(s:expression_list)->s:Many())

function s:Separated(p, parser, separator, stmt_sep) abort
	call a:parser(a:p)
	" TODO
endfunction

" Parse a declaration.
"
" This is used for both let expressions and top-level declarations, therefore
" it needs to be able to parse multiple ones.
let s:Declaration = s:Expression

" Parse topdecls.
let s:TopLevel = s:Declaration

function s:TabBSExpr(key) abort
	" If there are non-blank characters to the left of the cursor
	if (a:key ==# "\<Tab>" || a:key ==# "\<BS>")
				\ && indent(line('.')) + 1 < col('.') " FIXME
		return a:key
	endif
	let s:indent_dir = a:key ==# "\<Tab>" || a:key ==# "\<C-T>" ? 1 : -1
	return "\<C-F>"
endfunction

let s:indent_dir = 0

function GetHaskellIndent() abort
	let prevIndent = indent(s:indent_dir == 0 ? prevnonblank(v:lnum) : v:lnum)
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
