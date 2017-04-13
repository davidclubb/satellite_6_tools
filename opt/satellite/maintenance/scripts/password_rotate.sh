#!/bin/bash

# Environment
. /opt/satellite/maintenance/scripts/.sat.env

CHANGEROOTPASS=/opt/satellite/maintenance/scripts/change_remote_root_password.sh
VAULTDIR=/root/pv
HIST=${VAULTDIR}/history


# Commands and arguments
HAMMER="/bin/hammer -u $USER -p $PASS"


# Generate a list of managed systems
# Format: <hostname>,<IP>
MSYSTEM_LIST=`$HAMMER host list | egrep -v '^-|^ID' | awk -F'|' '{print $2","$5}' | sed 's/ //g'`


# Look at each name/IP pair
for MSYSTEM in $MSYSTEM_LIST; do

   # Separate the name and IP
   OS_HOSTNAME=`echo $MSYSTEM | awk -F',' '{print $1}'`
   NET_PUBIP=`echo $MSYSTEM | awk -F',' '{print $2}'`

   # Perform the password change - use the IP address to avoid problems with DNS
   $CHANGEROOTPASS $OS_HOSTNAME $NET_PUBIP

done
