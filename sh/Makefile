DIR = $(DESTDIR)/$(LIB)/rcscripts/sh
FILES = functions.sh init-common-post.sh init-common-pre.sh init-functions.sh \
	net.sh \
	rc-daemon.sh rc-services.sh
EXES = rc-help.sh

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done
	for x in $(EXES) ; do install -m 0755 $$x $(DIR) ; done

.PHONY: clean
