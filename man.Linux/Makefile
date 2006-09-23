DIR = $(DESTDIR)/usr/share/man
FILES = modules-update.8 modules.autoload.5

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do \
	    install -m 0755 -d $(DIR)/man"$${x##*.}" ;\
	    install -m 0644 $$x $(DIR)/man"$${x##*.}" ;\
	done

.PHONY: clean
