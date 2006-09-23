DIR = $(DESTDIR)/$(LIB)/rcscripts/net 
FILES = apipa.sh dhclient.sh essidnet.sh macnet.sh rename.sh system.sh \
	wpa_supplicant.sh

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done

.PHONY: clean
