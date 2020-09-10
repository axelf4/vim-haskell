VIM = vim
REDIR_TEST_TO_NULL = > /dev/null

ifeq ($(VIM),vim)
	args = --not-a-term
else ifeq ($(VIM),nvim)
	args = --headless
endif

all: test

TESTS = $(wildcard test/test_*.vim)

$(TESTS):
	$(VIM) --clean $(args) -u runtest.vim "$@" $(REDIR_TEST_TO_NULL) || { cat testlog; false; }

test: $(TESTS)

.PHONY: all test $(TESTS)
