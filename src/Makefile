# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

CC = gcc
LD = gcc

CFLAGS ?= -Wall -O2
DESTDIR =
LIB = lib

BIN_TARGETS =
SBIN_TARGETS = consoletype runscript start-stop-daemon
SYS_WHITELIST = env_whitelist

TARGET = $(BIN_TARGETS) $(SBIN_TARGETS)

OS = Linux
ifeq ($(OS),Linux)
LDFLAGS_RS  = -ldl
endif
ifeq ($(OS),BSD)
LDFLAGS_SSD = -lkvm
endif

override CFLAGS += -DLIBDIR=\"$(LIB)\"

all: $(TARGET)

runscript: rc-debug.o  rc-dynbuf.o  rc-misc.o runscript.o
	$(LD) $(LDFLAGS) -o $@ $^ $(LDFLAGS_RS)

start-stop-daemon: start-stop-daemon.c
	$(CC) $(CFLAGS) ${PAMFLAGS} $(LDFLAGS) -o $@ $^ $(LDFLAGS_SSD)

install: $(TARGET)
	install -m 0755 -d $(DESTDIR)/sbin
	install -m 0755 $(SBIN_TARGETS) $(DESTDIR)/sbin
	install -m 0755 -d $(DESTDIR)/$(LIB)/rcscripts/conf.d
	install -m 0644 $(SYS_WHITELIST) $(DESTDIR)/$(LIB)/rcscripts/conf.d
	if test "$(PAMFLAGS)" != "" ; then \
		install -m 0755 -d $(DESTDIR)/etc/pam.d ; \
		install -m 0644 start-stop-daemon.pam $(DESTDIR)/etc/pam.d/start-stop-daemon ; \
	fi

clean:
	rm -f $(TARGET)
	rm -f *.o *~
