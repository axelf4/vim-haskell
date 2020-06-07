function s:Test(text, lines) abort
	%bwipeout!
	set filetype=haskell
	call setline(1, a:text + [''])

	for assertion in a:lines
		call cursor(assertion.lnum, 1)
		call assert_equal(assertion.points, HaskellParse())
	endfor
endfunction

function Test_Basic() abort
	let text =<< trim END
	foo =
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]}])
endfunction

function Test_BasicWhere2() abort
	let text =<< trim END
	foo = bar
	  where bar = 4
	END
	call s:Test(text,
				\ [#{lnum: 3, points: [0, 8, 10]}])
endfunction

function Test_BasicWhere() abort
	let text =<< trim END
	foo = 1
	  where
	       x = 1; z = 3
	       y = 4
	       z foo
	END
	call s:Test(text,
				\ [#{lnum: 6, points: [0, 7, 9]}])
endfunction

function Test_MultipleDefs() abort
	let text =<< trim END
	foo = 4

	bar = 4
	test
	END
	call s:Test(text, [#{lnum: 1, points: [0]},
				\ #{lnum: 2, points: [0, 2]},
				\ #{lnum: 4, points: [0, 2]}])
endfunction

function Test_AWhereAndLet() abort
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
