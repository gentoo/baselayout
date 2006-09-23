DIR = $(DESTDIR)/etc/init.d
FILES= consolefont keymaps modules numlock rmnologin
EXES = shutdown.sh reboot.sh

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done
	for x in $(EXE) ; do install -m 0755 $$x $(DIR) ; done

.PHONY: clean
