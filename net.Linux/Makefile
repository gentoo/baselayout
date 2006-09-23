DIR = $(DESTDIR)/$(LIB)/rcscripts/net 
FILES = adsl.sh arping.sh bonding.sh br2684ctl.sh bridge.sh clip.sh \
	ccwgroup.sh dhcpcd.sh ifconfig.sh ifplugd.sh ip6to4.sh \
	ipppd.sh iproute2.sh iptunnel.sh iwconfig.sh macchangher.sh \
	netplug.sh pppd.sh pump.sh tuntap.sh udhcpc.sh vlan.sh

install:
	install -m 0755 -d $(DIR)
	for x in $(FILES) ; do install -m 0644 $$x $(DIR) ; done

.PHONY: clean
