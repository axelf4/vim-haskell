" Vim equivalent to haskell-mode

const s:endtoken = -1
const [s:if, s:then, s:where, s:operator, s:value]
			\ = range(1, 5)
const s:syn2Token = {
			\ "VarId": s:value,
			\ "hsNumber": s:value,
			\ }

const s:ind = 2

function s:NextToken() abort
	" Skip whitespace
	call search('\S', 'cWz')

	if b:eof || line('.') > s:initial_line || col('.') > getline(line('.'))->len()
		return s:endtoken
	endif

	" TODO
	let current_indent = col('.')

	" TODO Some keywords are missing
	let match = search('\%#\%(\%(\(if\)\|\(then\)\|\(where\)\)[[:alnum:]''_]\@!\|\([-:!#$%&*+./<=>?@\\\\^|~`]\+\)\)', 'cepWz')

	if match > 0
		let [lnum, col] = [line('.'), col('.')]
		" Move from end to next char
		execute "normal 1\<Space>"
		if line('.') == lnum && col('.') == col
			" If cursor didn't move => EOF
			let b:eof = 1
		endif
		return match - 1
	endif

	" Assumes all syntax items here wont follow another syntax item of the
	" same type
	let id = synID(line('.'), col('.'), 1)
	" Skip while same synID
	while 1
		let [lnum, col] = [line('.'), col('.')]
		execute "normal 1\<Space>"
		if line('.') == lnum && col('.') == col
			" If cursor didn't move => EOF
			let b:eof = 1
			break
		endif

		if synID(line('.'), col('.'), 1) !=# id
			break
		endif
	endwhile
	let token = s:syn2Token->get(id->synIDattr('name'), v:null)
	if token is v:null
		throw 'bad match ' .. id->synIDattr('name') .. ' : ' .. line('.') .. ' ' .. col('.')
	endif
	return token
endfunction

function Parse() abort
	let b:eof = 0
	let s:initial_line = line('.')
	call cursor(1, 1) " TODO Only move cursor to first line with zero indent
	let parser = #{token: v:null}

	function parser.next() abort
		let self.token = s:NextToken()
		return self.token
	endfunction
	function parser.peek() abort
		return self.token is v:null ? self.next() : self.token
	endfunction

	return s:TopLevel(parser)
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
