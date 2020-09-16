VIM := vim
unexport VIM
VIMFLAGS := $(if $(filter nvim,$(VIM)),--headless,--not-a-term)

all: test

TESTS := $(wildcard test/test_*.vim)

$(TESTS):
	$(VIM) --clean $(VIMFLAGS) -u runtest.vim "$@" || { cat testlog; false; }

test: $(TESTS)

.PHONY: all test $(TESTS)
