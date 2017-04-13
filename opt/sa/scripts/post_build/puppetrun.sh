#!/bin/bash


# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

RELEASE=`f_GetRelease | awk '{print $2}'`

if [[ $RELEASE -le 6 ]]; then
    /etc/init.d/puppet stop 2>&1 | > /dev/null
else
    systemctl stop puppet.service 2>&1 | > /dev/null
fi

/usr/bin/puppet agent --test

exit 0
