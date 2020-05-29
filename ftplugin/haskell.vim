" Vim equivalent to haskell-mode

" TODO
setlocal expandtab tabstop=8 shiftwidth=2

const s:endtoken = -1
" End of a layout list
const s:layoutEnd = -2
" A new item in a layout list
const s:layoutItem = -3
const [s:if, s:then, s:where,
			\ s:lbrace,
			\ s:operator, s:value]
			\ = range(1, 6)
const s:syn2Token = {
			\ "VarId": s:value,
			\ "hsNumber": s:value,
			\ }

" Shiftwidth
const s:ind = 2

let s:search_pat = '\%#\%('
" Keywords
let s:search_pat ..= '\%(\(if\)\|\(then\)\|\(where\)\)[[:alnum:]''_]\@!'
" Braces and semicolons
let s:search_pat ..= '\|\({\)'
" Operators
let s:search_pat ..= '\|\([-:!#$%&*+./<=>?@\\\\^|~`]\+\)'
let s:search_pat ..= '\)'

" Skips forward to next non-blank and returns whether one was found.
function SkipWs() abort
	return search('\S', 'cWz') != 0
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
		throw printf('bad match %s (%s) %s, %d:%d', g:syntax_on, id, id->synIDattr('name'), line('.'), col('.'))
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
				\ }

	function parser.next() abort
		" Skip whitespace
		" Only parse first token on indent line
		if self.token is s:endtoken || self.eof
			|| !s:SkipWs()
			|| line('.') > self.initial_line
			|| line('.') == self.initial_line && col('.') > indent(line('.'))
			let self.token = s:endtoken
		else
			let [prevLine, prevCol] = [self.currentLine, self.currentCol]
			let [self.currentLine, self.currentCol] = [line('.'), col('.')]

			let implicitLayoutActive = self.layoutCtx > 0
			if implicitLayoutActive && prevline < self.currentLine
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

		return self.token
	endfunction

	function parser.peek() abort
		return self.token is v:null ? self.next() : self.token
	endfunction

	call cursor(1, 1) " TODO Only move cursor to first line with zero indent

	return s:TopLevel(parser)
endfunction

" s:retNone is same as s:retError except not even the first token matched.
const [s:retOk, s:retNone, s:retError, s:retFinished] = [1, 2, 3, 4]

function s:Token(token) abort
	let token = a:token
	function! s:TokenRet(p) closure
		if a:p.peek() is s:endtoken | return #{status: s:retFinished} | endif
		if a:p.peek() is token
			call a:p.next()
			return #{status: s:retOk}
		endif
		return #{status: s:retNone}
	endfunction
	return funcref('s:TokenRet')
endfunction

function s:Or(...) abort
	let alts = a:000
	function! s:OrRet(p) closure
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

function s:Seq(...) abort
	let alts = a:000
	function! s:SeqRet(p) closure
		for Alt in alts
			let result = Alt(a:p)
			let status = result.status
			if status == s:retFinished || status == s:retError
				return result
			endif
		endfor
		return #{status: s:retOk}
	endfunction
	return funcref('s:SeqRet')
endfunction

function s:Many(Parser) abort
	function! s:ManyRet(p) closure
		while 1
			let result = a:Parser(a:p)
			let status = result.status
			if status == s:retNone | return #{status: s:retOk} | endif
			if status == s:retFinished || status == s:retError
				return result
			endif
		endwhile
	endfunction
	return funcref('s:ManyRet')
endfunction

let s:Empty = {-> s:retOk}

function s:Layout(p, item) abort
	if a:p.peek() is s:lbrace
	else
		let prevLayoutCtx = a:p.layoutCtx
		" Store indentation column of the enclosing layout context
		let a:p.layoutCtx = a:p.currentCol

		let a:p.layoutCtx = prevLayoutCtx
	endif
endfunction

function s:WithStarter(p, parser) abort
	call a:p.next()
	return a:p->a:parser()
endfunction

let s:expression_list = {
			\ s:where: funcref('s:WithStarter'),
			\ }

let s:Expression = s:Token(s:value)
" let s:Expression = s:Many(s:Token(s:value)->s:Or(s:Token(s:operator)))
			" -> s:Seq(s:Or(s:Token(s:where), s:Empty))

function s:Expression2(p) abort
	" TODO get current indent and add to return val

	while 1
		let token = a:p.peek()
		if token ==# s:value || token ==# s:operator
			call a:p.next()
			continue
		endif

		" TODO handle keywords or stuffs
		break
	endwhile

	if a:p.peek() ==# s:where
		" TODO Handle 'where' here?
		call a:p.next()
	else
		" Still inside the expression
		return [0, s:ind]
	endif
endfunction

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
