function s:Test(text, lines) abort
	%bwipeout!
	set filetype=haskell
	call setline(1, a:text + [''])

	for assertion in a:lines
		call cursor(assertion.lnum, 1)
		call assert_equal(assertion.points, HaskellParse()->uniq())
	endfor
endfunction

function Test_BasicExpr() abort
	let text =<< trim END
	foo =
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]}])
endfunction

function Test_Where() abort
	let text =<< trim END
	foo = bar
	  where bar = 4
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]},
				\ #{lnum: 3, points: [0, 8, 10]}])

	let text =<< trim END
	foo = 1
	  where
	       x = 1; z = 3
	       y = 4
	       z foo
	END
	call s:Test(text, [#{lnum: 3, points: [0, 4]},
				\ #{lnum: 6, points: [0, 7, 9]}])
endfunction

function Test_MultipleDecls() abort
	let text =<< trim END
	foo = 4

	bar = 4
	test
	END
	call s:Test(text, [#{lnum: 1, points: [0]},
				\ #{lnum: 2, points: [0, 2]},
				\ #{lnum: 4, points: [0, 2]}])
endfunction

function Test_WhereAndLet() abort
	let text =<< trim END
	foo = 1
	  where
	       y = let
	                  baz = 6
	                  in bar * baz
	       z foo
	END
	call s:Test(text,
				\ [#{lnum: 7, points: [0, 7, 9]}])
endfunction

function Test_String() abort
	let text =<< trim END
	foo = let
	  "bar \
	END
	call s:Test(text, [#{lnum: 3, points: [0, 2, 4]}])
endfunction

function Test_LocalDeclaration() abort
	let text =<< trim END
	foo = [x | let a, b :: Int; a = 1; b = 2

	  , x <- [a..b]]
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2, 15, 17]},
				\ #{lnum: 3, points: [0, 2]},
				\ #{lnum: 4, points: [0, 2]}])
endfunction

function Test_PatternMatch() abort
	let text =<< trim END
	foo = let
	  (x, y) =
	END
	call s:Test(text, [#{lnum: 3, points: [0, 2, 4]}])
endfunction

function Test_NestedLayoutCtxs() abort
	let text =<< trim END
	foo =
	  case 3 of
	    _ -> let x = 1
	END
	call s:Test(text, [#{lnum: 4, points: [0, 2, 4, 6, 13, 15]}])
endfunction

function Test_CharLiteral() abort
	let text =<< trim END
	foo = ','
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]}])
endfunction

function Test_Comment() abort
	let text =<< trim END
	foo = -- let x = 42
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]}])
endfunction

function Test_ExplicitLayoutCtx() abort
	let text =<< trim END
	foo = x where {
	  x = y
	  ; y = z }
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]},
				\ #{lnum: 3, points: [0, 2]},
				\ #{lnum: 4, points: [0]}])

	let text =<< trim END
	foo = x where
	  {
	  }
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]},
				\ #{lnum: 3, points: [0, 2]},
				\ #{lnum: 4, points: [0]}])
endfunction
