DIR = $(DESTDIR)/etc
FILES = issue issue.logo 

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done

.PHONY: clean
