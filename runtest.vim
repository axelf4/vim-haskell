set nocompatible
syntax enable
filetype plugin indent on
let s:test_file = expand('%')
let s:messages = []

function s:CheckErrors() abort
	if empty(v:errors) | return | endif
	call add(s:messages, s:test_file .. ':1:Error')
	for s:error in v:errors
		call add(s:messages, s:error)
	endfor
	call writefile(s:messages, 'testlog')
	cquit!
endfunction

try
	execute 'cd' fnamemodify(resolve(expand('<sfile>:p')), ':h')
	set runtimepath^=.

	source %
	" Query list of functions matching ^Test_
	let s:tests = map(split(execute('function /^Test_'), "\n"), 'matchstr(v:val, ''^function \zs\k\+\ze()'')')

	for s:test_function in s:tests
		%bwipeout!
		call add(s:messages, 'Test ' .. s:test_function)
		echo 'Test' s:test_function
		execute 'call' s:test_function '()'
		call s:CheckErrors()
	endfor
catch
	call add(v:errors, "Uncaught exception: " .. v:exception .. " at " .. v:throwpoint)
	call s:CheckErrors()
endtry

call writefile(s:messages, 'testlog')
quit!
