DIR = $(DESTDIR)/bin
EXE = rc-status

install:
	install -m 0755 -d $(DIR)
	for x in $(EXE) ; do install -m 0644 $$x $(DIR) ; done

.PHONY: clean
