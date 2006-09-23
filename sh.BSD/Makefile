DIR = $(DESTDIR)/$(LIB)/rcscripts/sh
FILES = init.sh rc-functions.sh 

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done

.PHONY: clean
