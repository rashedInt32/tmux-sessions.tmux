.PHONY: test lint

test:
	./tests/run.sh $(FILTER)

lint:
	shellcheck -x -s sh tmux-sessions.tmux scripts/*.sh tests/run.sh tests/specs/*.sh
