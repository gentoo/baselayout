DIR = $(DESTDIR)/sbin 
EXES = MAKEDEV modules-update

install:
	install -m 0755 -d $(DIR)
	for x in $(EXES) ; do install -m 0755 $$x $(DIR) ; done

.PHONY: clean
