PANDOC ?= pandoc -f gfm  -H _head.html -A _foot.html -T "nREPL Protocol"

index.html: spec.md _head.html _foot.html
	$(PANDOC) -i spec.md > $@
