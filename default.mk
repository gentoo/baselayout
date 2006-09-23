# Common makefile settings
# Copyright (c) 2006 Gentoo Foundation

DESTDIR =
ROOT = /
LIB = lib


#
# Recursive rules
#

SUBDIRS_ALL     = $(patsubst %,%_all,$(SUBDIRS))
SUBDIRS_CLEAN   = $(patsubst %,%_clean,$(SUBDIRS))
SUBDIRS_INSTALL = $(patsubst %,%_install,$(SUBDIRS))

all::     $(SUBDIRS_ALL)
clean::   $(SUBDIRS_CLEAN)
install:: $(SUBDIRS_INSTALL)

# Hmm ... possible to combine these three and not be ugly ?
%_all:
	$(MAKE) -C $(patsubst %_all,%,$@) all
	if test -d $(patsubst %_all,%,$@).$(OS) ; then $(MAKE) -C $(patsubst %_all,%,$@).$(OS) all ; fi
%_clean:
	$(MAKE) -C $(patsubst %_clean,%,$@) clean
	if test -d $(patsubst %_clean,%,$@).$(OS) ; then $(MAKE) -C $(patsubst %_clean,%,$@).$(OS) clean ; fi
%_install:
	$(MAKE) -C $(patsubst %_install,%,$@) install
	if test -d $(patsubst %_install,%,$@).$(OS) ; then $(MAKE) -C $(patsubst %_install,%,$@).$(OS) install ; fi


#
# Install rules
#

INSTALL_DIR  = install -m 0755 -d
INSTALL_EXE  = install -m 0755
INSTALL_FILE = install -m 0644

install:: $(EXES) $(FILES)
	$(INSTALL_DIR) $(DESTDIR)$(DIR)
	for x in $(EXES)  ; do $(INSTALL_EXE)  $$x $(DESTDIR)/$(DIR) || exit $$? ; done
	for x in $(FILES) ; do $(INSTALL_FILE) $$x $(DESTDIR)/$(DIR) || exit $$? ; done


.PHONY: all clean install
