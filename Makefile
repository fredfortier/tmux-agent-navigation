.PHONY: test test-thumbs lint

test:
	./tests/run

test-thumbs:
	@test -n "$(TMUX_AGENT_TEST_THUMBS)" || (echo 'Set TMUX_AGENT_TEST_THUMBS to a built upstream checkout'; exit 1)
	./tests/run thumbs

lint:
	shellcheck agent-navigation.tmux bin/* tests/run examples/*
	stylua --check lua tests
