#/bin/bash

# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         Setup has not been completed on this system."
   exit 2
fi


RELEASE=`f_GetRelease | awk '{print $2}'`

if [[ $RELEASE -gt 6 ]]; then
   echo "This script has not been adapted for RHEL 7 yet"
   exit
fi

GRUBCONF=/boot/grub/grub.conf
KDUMPCONF=/etc/kdump.conf
KDUMPARG=128M@16M
KDUMPPATH=/var/crash
KDUMPINST='core_collector makedumpfile -c --message-level 7 -d 14'

# Remove any existing config from kdump.conf
/bin/sed -i '/^path/d;/^core_collector/d' $KDUMPCONF

# Add the clean config to kdump.conf
echo -e "path ${KDUMPPATH}\n${KDUMPINST}" >> $KDUMPCONF

# Add the crashkernel option to grub
let GRUBDKERN=`grep "^default=" $GRUBCONF | awk -F'=' '{print $2}'`+1
DEFAULTKLINE=`/bin/cat $GRUBCONF | egrep -v "^#" | grep -m $GRUBDKERN kernel`

if [[ -z `echo $DEFAULTKLINE | grep "crashkernel="` ]]; then
   /sbin/grubby --update-kernel=`/sbin/grubby --default-kernel` --args="crashkernel=$KDUMPARG"
fi

# Enable kdump for the next boot
/sbin/chkconfig kdump on
