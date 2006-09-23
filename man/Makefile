DIR = $(DESTDIR)/usr/share/man
FILES = consoletype.1 rc-status.8 rc-update.8 start-stop-daemon.8

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do \
	    install -m 0755 -d $(DIR)/man"$${x##*.}" ;\
	    install -m 0644 $$x $(DIR)/man"$${x##*.}" ;\
	done

.PHONY: clean
