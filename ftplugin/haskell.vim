" Vim equivalent to haskell-mode

const s:endtoken = -1
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

function s:NextToken(p) abort
	" Skip whitespace
	if search('\S', 'cWz') == 0
		let a:p.eof = 1
	endif

	if a:p.eof || line('.') > a:p.initial_line | return s:endtoken | endif
	" Only parse first token on indent line
	if line('.') == a:p.initial_line | let a:p.eof = 1 | endif

	" TODO
	let current_indent = col('.')

	let match = search(s:search_pat, 'cepWz')
	if match > 0
		let [lnum, col] = [line('.'), col('.')]
		" Move from end to next char
		execute "normal 1\<Space>"
		" If cursor didn't move => EOF
		if line('.') == lnum && col('.') == col | let a:p.eof = 1 | endif
		return match - 1
	endif

	let id = synID(line('.'), col('.'), 1)
	" Skip while same synID
	" Note: Requires that it cannot immediately follow another with same ID
	while 1
		let [lnum, col] = [line('.'), col('.')]
		execute "normal 1\<Space>"
		" If cursor didn't move => EOF
		if line('.') == lnum && col('.') == col
			let a:p.eof = 1
			break
		endif

		if synID(line('.'), col('.'), 1) !=# id | break | endif
	endwhile
	let token = s:syn2Token->get(id->synIDattr('name'), v:null)
	if token is v:null
		throw printf('bad match %s, %d:%d', id->synIDattr('name'), line('.'), col('.'))
	endif
	return token
endfunction

function Parse() abort
	let ctxs = [] " Stack of layout contexts
	let parser = #{token: v:null, eof: 0, ctxs: ctxs,
				\ initial_line: line('.'),
				\ }

	function parser.next() abort
		let self.token = self->s:NextToken()
		return self.token
	endfunction
	function parser.peek() abort
		return self.token is v:null ? self.next() : self.token
	endfunction

	call cursor(1, 1) " TODO Only move cursor to first line with zero indent

	return s:TopLevel(parser)
endfunction

function s:Layout(p) abort
	if a:p.peek() is s:lbrace
	else
		eval a:p.ctxs->add(#{indent: col('.')})
	endif
endfunction

" Parse topdecls.
function s:TopLevel(p) abort
	call a:p.peek()
	return s:Declaration(a:p)
endfunction

" Parse a declaration.
"
" This is used for both let expressions and top-level declarations, therefore
" it needs to be able to parse multiple ones.
function s:Declaration(p) abort
	return s:Expression(a:p)
	" TODO Guards
endfunction

function s:WithStarter(p, parser) abort
	call a:p.next()
	return a:p->a:parser()
endfunction

let s:expression_list = {
			\ s:where: funcref('s:WithStarter'),
			\ }

function s:Expression(p) abort
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
