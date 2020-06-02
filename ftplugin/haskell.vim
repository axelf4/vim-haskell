" Vim filetype plugin
" Language: Haskell
" Maintainer: Axel Forsman <axelsfor@gmail.com>

setlocal tabstop=8 shiftwidth=2 expandtab

const s:endtoken = -1
" End of a layout list
const s:layoutEnd = -2
" A new item in a layout list
const s:layoutItem = -3
const [s:if, s:then, s:else, s:let, s:in, s:where,
			\ s:lbrace, s:semicolon,
			\ s:operator, s:value]
			\ = range(1, 10)
const s:syn2Token = {
			\ "VarId": s:value,
			\ "hsNumber": s:value,
			\ }

" Shiftwidth
const s:ind = 2

let s:search_pat = '\%#\%('
" Keywords
let s:search_pat ..= '\%(\(if\)\|\(then\)\|\(else\)\|\(let\)\|\(in\)\|\(where\)\)[[:alnum:]''_]\@!'
" Braces and semicolons
let s:search_pat ..= '\|\({\)\|\(;\)'
" Special symbols
" let s:search_pat ..= '\|\%(\(=\)\)[-:!#$%&*+./<=>?@\\\\^|~]\@!'
" Operators
let s:search_pat ..= '\|\([-:!#$%&*+./<=>?@\\\\^|~`]\+\)'
let s:search_pat ..= '\)'

" Skips forward to next non-blank and returns whether one was found.
function s:SkipWs(stopline) abort
	return search('\S', 'cWz', a:stopline) != 0
endfunction

" Returns true if hit EOF.
function s:SkipChar(p) abort
	let [lnum, col] = [line('.'), col('.')]
	" Move from end to next char
	execute "normal 1\<Space>"
	" If cursor didn't move => EOF
	if line('.') == lnum && col('.') == col
		let a:p.eof = 1
		return 0
	endif
	return 1
endfunction

" Lexes the token under the cursor and moves to the character after.
function s:LexToken(p) abort
	let match = search(s:search_pat, 'cepWz')
	if match > 0
		call s:SkipChar(a:p)
		return match - 1
	endif

	let id = synID(line('.'), col('.'), 1)
	let token = s:syn2Token->get(id->synIDattr('name'), v:null)
	if token is v:null
		throw printf('bad match `%s` (%s) %s, %d:%d', getline(line('.'))[col('.') - 1:], id, id->synIDattr('name'), line('.'), col('.'))
	endif
	" Skip while same synID
	" Note: Requires that it cannot immediately follow another with same ID
	while s:SkipChar(a:p) && synID(line('.'), col('.'), 1) ==# id | endwhile
	return token
endfunction

function Parse() abort
	let parser = #{token: v:null, eof: 0,
				\ currentLine: 1, currentCol: 1,
				\ initial_line: line('.'),
				\ layoutCtx: 0,
				\ indentations: [0],
				\ following: s:endtoken,
				\ }

	function parser.next() abort
		" Skip whitespace
		if self.token is s:endtoken || self.eof
					\ || !s:SkipWs(self.initial_line)
			let self.token = s:endtoken
		elseif line('.') >= self.initial_line
			let self.token = s:endtoken
			if line('.') == self.initial_line | let self.following = self->s:LexToken() | endif
		else
			let [prevLine, prevCol] = [self.currentLine, self.currentCol]
			let [self.currentLine, self.currentCol] = [line('.'), col('.')]

			let implicitLayoutActive = self.layoutCtx > 0
			if prevLine < self.currentLine && implicitLayoutActive
				let layoutIndent = self.layoutCtx

				if self.currentCol < layoutIndent
					let self.token = s:layoutEnd
				elseif self.currentCol == layoutIndent
					let self.token = s:layoutItem
				else
					let self.token = self->s:LexToken()
				endif
			else
				let self.token = self->s:LexToken()
			endif
		endif

		call Log('parserd: ' .. self.token)
		echom 'parsed:' self.token
		return self.token
	endfunction

	function parser.peek() abort
		return self.token is v:null ? self.next() : self.token
	endfunction

	let save_cursor = getcurpos()
	try
		call cursor(1, 1) " TODO Only move cursor to first line with zero indent

		let result = s:TopLevel(parser)
	finally
		call setpos('.', save_cursor)
	endtry

	return parser.indentations
endfunction

" s:retNone is same as s:retError except not even the first token matched.
" TODO Remove s:retError and just skip forward instead
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
		if a:p.peek() is s:lbrace
			throw 'Not yet implemented'
		else
			let prevLayoutCtx = a:p.layoutCtx
			" Store indentation column of the enclosing layout context
			let a:p.layoutCtx = a:p.currentCol
			eval a:p.indentations->add(a:p.layoutCtx - 1)

			while 1
				let result = a:Item(a:p)
				let status = result.status
				if status == s:retNone | break | endif " parse-error clause

				if status == s:retFinished || status == s:retError
					return result
				endif

				let following = a:p.peek()
				call a:p.next()
				if following ==# s:layoutEnd
					break
				elseif following ==# s:layoutItem || following ==# s:semicolon
				else
					return #{status: s:retError}
				endif
			endwhile

			eval a:p.indentations->remove(-1)
			let a:p.layoutCtx = prevLayoutCtx
		endif

		return #{status: s:retOk}
	endfunction
	return funcref('s:LayoutRet')
endfunction

function s:AddIndent(Parser) abort
	function s:AddIndentRet(p) abort closure
		eval a:p.indentations->add(a:p.indentations[-1] + shiftwidth())
		let result = a:Parser(a:p)
		if result.status != s:retFinished | eval a:p.indentations->remove(-1) | endif
		return result
	endfunction
	return funcref('s:AddIndentRet')
endfunction

function s:WithStarter(p, parser) abort
	call a:p.next()
	return a:p->a:parser()
endfunction

let s:DeclarationLayout = s:Layout(s:Lazy({-> s:Declaration}))

let s:expression_list = {
			\ s:value: s:Token(s:value),
			\ s:operator: s:Token(s:operator),
			\ s:let: s:Token(s:let)->s:Seq(s:DeclarationLayout, s:Token(s:in), s:Lazy({-> s:Expression})),
			\ s:where: s:Token(s:where)->s:Seq(s:DeclarationLayout),
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

" Haskell indenting is ambiguous
nnoremap <buffer> = <Nop>

setlocal indentexpr=GetHaskellIndent()

function GetHaskellIndent() abort
	let indentations = Parse()
	return indentations[-1]
endfunction
