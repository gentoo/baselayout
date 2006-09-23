DIR = $(DESTDIR)/etc/conf.d
FILES = consolefont keymaps 

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done
