# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

CC ?= gcc

CFLAGS ?= -Wall -O2
DESTDIR =
LIB = lib

BIN_TARGETS =
SBIN_TARGETS = consoletype rc-depend runscript start-stop-daemon
SYS_WHITELIST = env_whitelist

TARGET = $(BIN_TARGETS) $(SBIN_TARGETS)

OS = Linux
ifeq ($(OS),Linux)
LDLIBS_RS  = -ldl
endif
ifeq ($(OS),BSD)
LDLIBS_SSD = -lkvm
endif

HAVE_PAM = 
ifdef HAVE_PAM
CFLAGS_SSD = -DHAVE_PAM -lpam
endif

override CFLAGS += -DLIBDIR=\"$(LIB)\"

all: $(TARGET)

runscript: LDLIBS += $(LDLIBS_RS)
runscript: rc-debug.o  rc-dynbuf.o  rc-misc.o runscript.o

start-stop-daemon: CFLAGS += $(CFLAGS_SSD)
start-stop-daemon: LDLIBS += $(LDLIBS_SSD)
start-stop-daemon: start-stop-daemon.c

install: $(TARGET)
	install -m 0755 -d $(DESTDIR)/sbin
	install -m 0755 $(SBIN_TARGETS) $(DESTDIR)/sbin
	install -m 0755 -d $(DESTDIR)/$(LIB)/rcscripts/conf.d
	install -m 0644 $(SYS_WHITELIST) $(DESTDIR)/$(LIB)/rcscripts/conf.d
	if test "$(HAVE_PAM)" != "" ; then \
		install -m 0755 -d $(DESTDIR)/etc/pam.d ; \
		install -m 0644 start-stop-daemon.pam $(DESTDIR)/etc/pam.d/start-stop-daemon ; \
	fi

clean:
	rm -f $(TARGET)
	rm -f *.o *~
