DIR = $(DESTDIR)/etc
FILES = hosts networks profile rc.conf shells

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done

.PHONY: clean
