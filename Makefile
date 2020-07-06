VIM = vim
REDIR_TEST_TO_NULL = > /dev/null 2>&1

all: test

TESTS = $(wildcard test/test_*.vim)

$(TESTS):
	$(VIM) --clean --not-a-term -u runtest.vim "$@" $(REDIR_TEST_TO_NULL) || { cat testlog; false; }

test: $(TESTS)

.PHONY: all test $(TESTS)
