all: check

REDIR_TEST_TO_NULL = >/dev/null 2>&1

TESTS = $(wildcard test/test_*.vim)

$(TESTS):
		vim --clean --not-a-term -u runtest.vim "$@" $(REDIR_TEST_TO_NULL) || { cat testlog; false; }

check: $(TESTS)

.PHONY: all check $(TESTS)
