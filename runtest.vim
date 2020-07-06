set nocompatible
syntax enable
filetype plugin indent on
let s:test_file = expand('%')
let s:messages = []

function s:CheckErrors() abort
	if v:errors->empty() | return | endif
	eval s:messages->add(s:test_file .. ':1:Error')
	for s:error in v:errors
		eval s:messages->add(s:error)
	endfor
	call writefile(s:messages, 'testlog')
	cquit!
endfunction

try
	execute 'cd' fnamemodify(resolve(expand('<sfile>:p')), ':h')
	set runtimepath^=.

	source %
	" Query list of functions matching ^Test_
	let s:tests = execute('function /^Test_')->split("\n")->map('matchstr(v:val, ''^function \zs\k\+\ze()'')')

	for s:test_function in s:tests
		%bwipeout!
		eval s:messages->add('Test ' .. s:test_function)
		echo 'Test' s:test_function
		execute 'call' s:test_function '()'
		call s:CheckErrors()
	endfor
catch
	eval v:errors->add("Uncaught exception: " .. v:exception .. " at " .. v:throwpoint)
	call s:CheckErrors()
endtry

call writefile(s:messages, 'testlog')
quit!
