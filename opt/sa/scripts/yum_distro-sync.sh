#!/bin/bash

SCRIPTDIR1=/opt/sa/scripts

# Locate and source common_functions.sh
if [[ -s "${SCRIPTDIR1}/common_functions.sh" ]]; then
   source "${SCRIPTDIR1}/common_functions.sh"
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 255
fi

# Get the major relase number to determine the exact yum command
RN=`f_GetRelease | awk '{print $2}'`

case $RN in

   6) /usr/bin/yum -y distribution-synchronization
      ;;

   7) /usr/bin/yum -y upgrade --exclude=WALinuxAgent
      #/usr/bin/yum -y distro-sync 
      if [[ -n `/bin/rpm -qa WALinuxAgent` ]]; then
         /usr/bin/systemctl enable rc-local 2>&1 | > /dev/null
         RCLOCAL=/etc/rc.d/rc.local
         echo "/usr/bin/yum -y upgrade WALinuxAgent" >> $RCLOCAL
         echo "sed -i '/WALinuxAgent/d' $RCLOCAL" >> $RCLOCAL
      fi
      ;;
      

   *) /usr/bin/yum -y upgrade
      ;;

esac

exit 0
