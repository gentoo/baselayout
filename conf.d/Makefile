DIR = $(DESTDIR)/etc/conf.d
FILES = bootmisc clock env_whitelist hostname local.start local.stop \
	net net.example wireless.example rc

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done

.PHONY: clean
