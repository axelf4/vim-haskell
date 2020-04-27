function s:Test(text, lines) abort
	%bwipeout!
	set filetype=haskell
	call setline(1, a:text + [''])

	for assertion in a:lines
		call cursor(assertion.lnum, 1)
		call assert_equal(assertion.points, Parse())
	endfor
endfunction

function Test_Basic() abort
	let text =<< trim END
	foo = 1
	END
	call s:Test(text, [#{lnum: 2, points: [0, 2]}])
endfunction

function Test_BasicWhere() abort
	let text =<< trim END
	foo = 1
	  where
	END
	call s:Test(text,
				\ [#{lnum: 2, points: [0, 2]}])
endfunction
