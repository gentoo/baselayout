DIR = $(DESTDIR)/etc/init.d
FILES = bootmisc checkfs checkroot clock hostname local localmount \
	netmount urandom \
	halt.sh

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0755 $$x $(DIR) ; done

.PHONY: clean
