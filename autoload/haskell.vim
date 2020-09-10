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

" Regex for matching tokens.
" Note: Vim regexes only supports nine sub-Patterns...
"
" Keywords
let s:search_pat = '\C\(if\|then\|else\|let\|in\|do\|case\|of\|where\)[[:alnum:]''_]\@!'
" Values
let s:search_pat ..= '\|\(''\%(\\.\|[^'']\)\+''\|[[:alnum:]''_]\+\|"\%(\\\_s\+\\\?\|\\\S\|[^"]\)*\%("\|\_$\)\)'
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
	let at_cursor = a:at_cursor
	while 1
		let match = search(s:search_pat, (at_cursor ? 'c' : '') .. 'pWz', a:stopline, 0)
		if match && synIDattr(synID(line('.'), col('.'), 1), 'name') =~# 'Comment$'
			let at_cursor = 0
			continue
		endif
		return match == 2 ? s:str2Tok[expand('<cword>')]
					\ : match == 3 ? s:value
					\ : match == 4 ? s:str2Tok[getline('.')[col('.') - 1]]
					\ : match == 5 ? s:operator
					\ : s:endtoken
	endwhile
endfunction

" Parse around the cursor and return possible indentation points.
"
" May move the cursor.
function haskell#Parse() abort
	let parser = {'token': v:null, 'nextToken': v:null,
				\ 'currentLine': 1, 'currentCol': 1,
				\ 'initial_line': line('.'),
				\ 'layoutCtx': 0,
				\ 'indentations': [0],
				\ }

	" Move to first line with zero indentation
	normal! 0
	while search('^\S\|\%^', 'bW', 0, 0)
				\ && synIDattr(synID(line('.'), 1, 1), 'name') =~# 'Comment$\|String$'
	endwhile

	function parser.next() abort
		if line('.') >= self.initial_line | let self.token = s:endtoken | endif
		if self.token is s:endtoken | return s:endtoken | endif

		" If has pending token: Return it
		if self.nextToken isnot v:null
			let self.token = self.nextToken
			let self.nextToken = v:null
			return self.token
		endif

		let prevLine = self.currentLine
		" Lex the next token and jump to its start
		let self.token = s:LexToken(self.initial_line, self.token is v:null)

		if line('.') < self.initial_line
			let [self.currentLine, self.currentCol] = [line('.'), col('.')]

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
		endif

		return self.token
	endfunction

	let parser.token = parser.next()

	let result = s:TopLevel(parser)
	return sort(parser.indentations, 'n')
endfunction

" Parser return statuses.
"
" - "s:retNone" means no token got parsed
" - "s:retOk" means parser consumed (maybe partially) at least one token
const [s:retNone, s:retOk, s:retFinished] = range(3)

function s:Token(token) abort
	let dict = {}
	function dict.fn(p) abort closure
		if a:p.token is a:token
			call a:p.next()
			return s:retOk
		endif
		return s:retNone
	endfunction
	return dict.fn
endfunction

function s:FromDict(dict) abort
	let dict = {}
	function dict.fn(p) abort closure
		let Parser = get(a:dict, a:p.token, v:null)
		return Parser is v:null ? s:retNone : Parser(a:p)
	endfunction
	return dict.fn
endfunction

function s:Seq(...) abort
	let alts = a:000
	let dict = {}
	function dict.fn(p) abort closure
		let first = 1
		for Alt in alts
			let result = Alt(a:p)
			if result != s:retOk | return first ? s:retNone : s:retOk | endif
			let first = 0
		endfor
		return s:retOk
	endfunction
	return dict.fn
endfunction

function s:Many(Parser) abort
	let dict = {}
	function dict.fn(p) closure
		let first = 1
		while 1
			let result = a:Parser(a:p)
			if result == s:retNone | return first ? s:retNone : s:retOk | endif
			let first = 0
		endwhile
	endfunction
	return dict.fn
endfunction

function s:Lazy(Cb) abort
	let Parser = v:null
	let dict = {}
	function dict.fn(p) abort closure
		if Parser is v:null | let Parser = a:Cb() | endif
		return Parser(a:p)
	endfunction
	return dict.fn
endfunction

function s:Opt(Parser) abort
	let dict = {}
	function dict.fn(p) abort closure
		call a:Parser(a:p)
		return s:retOk
	endfunction
	return dict.fn
endfunction

function s:Layout(Item) abort
	let dict = {}
	function dict.fn(p) abort closure
		let prevLayoutCtx = a:p.layoutCtx

		if a:p.token == s:endtoken || a:p.initial_line == line('.')
			call add(a:p.indentations, indent(a:p.currentLine) + shiftwidth())
			return s:retOk
		elseif a:p.token is s:lbrace
			let [a:p.layoutCtx, startIndent] = [0, col('.') - 1]
			let res = s:AddIndent(s:Seq(s:Token(s:lbrace), s:Sep(a:Item, s:semicolon)))(a:p)
			if res == s:retOk && a:p.token == s:rbrace && line('.') == a:p.initial_line
				call add(a:p.indentations, startIndent)
			endif
		else
			" Store indentation column of the enclosing layout context
			let layoutCtx = a:p.currentCol " FIXME: Handle tabs
			let a:p.layoutCtx = layoutCtx

			while a:Item(a:p) == s:retOk
				let current = a:p.token
				if current == s:endtoken
					call add(a:p.indentations, layoutCtx - 1)
					return s:retOk
				endif
				if current == s:layoutEnd || current == s:layoutItem || current == s:semicolon
					call a:p.next()
				endif
				if !(current == s:layoutItem || current == s:semicolon)
					break
				endif
			endwhile
		endif

		let a:p.layoutCtx = prevLayoutCtx
		return s:retOk
	endfunction
	return dict.fn
endfunction

function s:Sep(Parser, sep) abort
	let dict = {}
	function dict.fn(p) abort closure
		let result = a:Parser(a:p)
		if result == s:retNone | return s:retNone | endif

		while a:p.token == a:sep
			call a:p.next()

			let result = a:Parser(a:p)
			if result == s:retNone | break | endif
		endwhile

		return s:retOk
	endfunction
	return dict.fn
endfunction

function s:AddIndent(Parser) abort
	let dict = {}
	function dict.fn(p) abort closure
		let startIndent = max([indent(a:p.currentLine), a:p.layoutCtx - 1])
		let result = a:Parser(a:p)
		if result == s:retOk && a:p.token == s:endtoken
			call add(a:p.indentations, startIndent + shiftwidth())
		endif
		return result
	endfunction
	return dict.fn
endfunction

const [s:Expr, s:Decl] = [s:Lazy({-> s:Expression}), s:Lazy({-> s:Declaration})]

const s:expression_list = {
			\ s:value: s:Token(s:value),
			\ s:operator: s:Token(s:operator),
			\ s:let: s:Seq(s:Token(s:let), s:Layout(s:Decl), s:Token(s:in), s:Expr),
			\ s:if: s:Seq(s:Token(s:if), s:Expr, s:Token(s:then), s:Expr, s:Token(s:else), s:Expr),
			\ s:do: s:Seq(s:Token(s:do), s:Layout(s:Expr)),
			\ s:case: s:Seq(s:Token(s:case), s:Expr, s:Token(s:of), s:Layout(s:Expr)),
			\ s:lparen: s:Seq(s:Token(s:lparen), s:Opt(s:Sep(s:Expr, s:comma)), s:Token(s:rparen)),
			\ s:lbracket: s:Seq(s:Token(s:lbracket), s:Opt(s:Sep(s:Expr, s:comma)), s:Token(s:rbracket)),
			\ s:lbrace: s:Seq(s:Token(s:lbrace), s:Opt(s:Sep(s:Expr, s:comma)), s:Token(s:rbrace)),
			\ }

const s:Expression = s:AddIndent(s:Many(s:FromDict(s:expression_list)))
const s:Declaration = s:Seq(s:Opt(s:AddIndent(s:Sep(s:Token(s:value), s:comma))),
			\ s:Expression, s:Opt(s:Seq(s:Token(s:where), s:Layout(s:Decl))))

" Parse topdecls.
const s:TopLevel = s:Declaration
