NAME     := github-pr-richlinks
PREFIX   ?= $(HOME)/.local
BINDIR   := $(PREFIX)/bin
LABEL    := com.dansimau.$(NAME)
AGENT    := $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOGDIR   := $(HOME)/Library/Logs/$(NAME)

.PHONY: build release install uninstall start stop restart log clean

build:
	swift build

release:
	swift build -c release

install: release
	mkdir -p $(BINDIR) $(LOGDIR) $(dir $(AGENT))
	install -m 755 .build/release/$(NAME) $(BINDIR)/$(NAME)
	sed -e 's|@BIN@|$(BINDIR)/$(NAME)|g' -e 's|@LOGDIR@|$(LOGDIR)|g' -e 's|@LABEL@|$(LABEL)|g' \
	    launchagent.plist.template > $(AGENT)
	@echo "Installed $(BINDIR)/$(NAME) and $(AGENT). Run 'make start' to launch it."

uninstall: stop
	rm -f $(BINDIR)/$(NAME) $(AGENT)

start:
	launchctl bootstrap gui/$$(id -u) $(AGENT)

stop:
	-launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null

restart: stop start

log:
	tail -f $(LOGDIR)/$(NAME).log

clean:
	rm -rf .build
