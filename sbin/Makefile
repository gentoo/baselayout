DIR = $(DESTDIR)/sbin 
EXES = depscan.sh env-update.sh rc rc-update runscript.sh

install:
	install -m 0755 -d $(DIR)
	for x in $(EXES) ; do install -m 0755 $$x $(DIR) ; done

.PHONY: clean
