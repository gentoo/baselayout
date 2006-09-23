DIR = $(DESTDIR)/etc
FILES = filesystems inputrc issue issue.devfix issue.logo protocols services \
	shadow sysctl.conf

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done
