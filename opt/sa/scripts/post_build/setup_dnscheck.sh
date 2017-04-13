#!/bin/bash

# Workaround in case of buggy DNS


cat << EOF > /etc/init.d/dnscheck

#!/bin/bash

# the following is the LSB init header
#
### BEGIN INIT INFO
# Provides: dnscheck
# Required-Start: network
# Required-Stop: network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: secure Windows DNS update for Linux DHCP clients
# Description: This is a script checks for the server's DNS record on startup and updates it as needed
### END INIT INFO

# the following is chkconfig init header
#
# dnscheck:  check/update DNS
#
# chkconfig: 345 99 01
# description:  This is a script for checking and updating "Secure" Windows DNS
#

CHECKSCRIPT=/opt/sa/scripts/check_my_dns.sh

f_Usage() {

   echo "Usage: \$0 [start|stop|status|restart]"
   echo ""
   echo "Note: stop is ignored"

}

case "\$1" in

    --help) f_Usage
            RETVAL=0
            ;;
     start|restart|status) \$CHECKSCRIPT
            RETVAL=\$?
            ;;
      stop) echo "Nothing to stop"
            RETVAL=0
            ;;
         *) f_Usage
            RETVAL=0
            ;;
esac
exit \$RETVAL

EOF

chmod +x /etc/init.d/dnscheck 2>&1 | tee -a /var/log/install/dnscheck.log

/sbin/chkconfig dnscheck on 2>&1 | tee -a /var/log/install/dnscheck.log

/sbin/chkconfig --list dnscheck 2>&1 | tee -a /var/log/install/dnscheck.log
find /etc/rc.d | grep dnscheck 2>&1 | tee -a /var/log/install/dnscheck.log
