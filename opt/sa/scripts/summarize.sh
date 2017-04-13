#!/bin/bash

#################FUNCTION DEFINITIONS########################

#-----------------
# Function: f_PathOfScript
#-----------------
# Returns the location of the script, irrespective of where it
# was launched.  This is useful for scripts that look for files
# in their current directory, or in relative paths from it
#
#-----------------
# Usage: f_PathOfScript
#-----------------
# Returns: <PATH>

f_PathOfScript () {

   unset RESULT

   # if $0 begins with a / then it is an absolute path
   # which we can get by removing the scipt name from the end of $0
   if [[ -n `echo $0 | grep "^/"` ]]; then
      BASENAME=`basename $0`
      RESULT=`echo $0 | sed 's/'"$BASENAME"'$//g'`

   # if this isn't an absolute path, see if removing the ./ from the
   # beginning of $0 results in just the basename - if so
   # the script is being executed from the present working directory
   elif [[ `echo $0 | sed 's/^.\///g'` == `basename $0` ]]; then
      RESULT=`pwd`

   # If we're not dealing with an absolute path, we're dealing with
   # a relative path, which we can get with pwd + $0 - basename
   else
      BASENAME=`basename $0`
      RESULT="`pwd`/`echo $0 | sed 's/'"$BASENAME"'$//g'`"
   fi

   echo $RESULT

}

cd `f_PathOfScript`

# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

#### SETTINGS ####

# If VERBOSE is 0, output is suppressed, if it is non-zero output is displayed
VERBOSE=0


# Set the variable timestamp
if [[ -z $VTS ]]; then
   export VTS="date +%Y%m%d%H%M%S"
fi

# Define the output file
OS_HOSTNAME=`hostname`

###########NON-INTERACTIVE DETAILS##############

# System ID
OS_NAME=`hostname | awk -F'.' '{print $1}'`
if [[ -z `host $OS_HOSTNAME 2>&1 | grep -i "not found"` ]]; then
   NET_FQDN=`host $OS_HOSTNAME | awk '{print $1}'`
else
   NET_FQDN=`hostname --fqdn`
fi

if [[ -n `echo $NET_FQDN | grep '\.'` ]]; then
   NET_DOMAIN=`echo ${NET_FQDN#*.}`
else
   NET_DOMAIN=
fi

OS_TYPE=`uname -s`
OS_RELEASE=`f_GetRelease`
DISTRO=`f_GetRelease | awk '{print $1}'`
RELEASE=`f_GetRelease | awk '{print $2}'`

NET_PUBIF=`f_FindPubIF`
if [[ "$NET_PUBIF" != "FAILURE" ]]; then
   if [[ -f "/sys/class/net/${NET_PUBIF}/address" ]]; then
      NET_MAC_ADDR=`cat /sys/class/net/${NET_PUBIF}/address`
   else
      NET_MAC_ADDR=UNKNOWN
   fi
fi

NET_PUBIP=`f_IPforIF $NET_PUBIF`

# Memory Information
TOTALKB=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
let HW_MEM_MB=$TOTALKB/1024
#let TOTALGB=$HW_MEM_MB/1024

TOTALGB=$( echo "scale=3;$HW_MEM_MB / 1024" | bc | awk '{printf "%3.0f\n", $0}' | awk '{print $1}' )
# Disk Count

# Grab the CPU type
#HW_CPU_NAME=`/usr/sbin/dmidecode | awk /"Processor Information"/,/"Core Enabled"/ | grep "Version:" | head -1 | sed 's/Version://' | awk -F'@' '{print $1}' | sed 's/\t/ /g' | sed 's/ \+ / /g'`
#HW_CPU_NAME=`echo $HW_CPU_NAME| sed 's/^ //' | sed 's/ $//'`
HW_CPU_NAME=$( cat /proc/cpuinfo | grep -m1 "^model name" | awk -F':' '{print $2}' | sed 's/^ //g;s/  */ /g' )

# Logical Disk Info
TOTALK=0
TOTALF=0
FSCOUNT=0
for MP in `df -P -x nfs4 -x nfs -x cifs -x tmpfs | grep -v "^Filesystem" | awk '{print $NF}'`; do


   MP_TSIZE_K=`df -kP $MP | grep -v "^Filesystem" | awk '{print $2}'`
   MP_TSIZE_G=`echo "scale=2; $MP_TSIZE_K / 1024 / 1024 " | bc`

   MP_USIZE_K=`df -kP $MP | grep -v "^Filesystem" | awk '{print $3}'`
   MP_USIZE_G=`echo "scale=2; $MP_USIZE_K / 1024 / 1024 " | bc`

   MP_FSIZE_K=`df -kP $MP | grep -v "^Filesystem" | awk '{print $4}'`
   MP_FSIZE_G=`echo "scale=2; $MP_FSIZE_K / 1024 / 1024 " | bc`

   PFREE=$( echo "100 - $(df -P $MP | grep -v "^Filesystem" | awk '{print $5}' | tr -d '%')" | bc )

   #echo $MP,$MP_TSIZE_G,$MP_FSIZE_G,${PFREE}%
   if [[ $FSCOUNT == 0 ]]; then

      echo "$OS_HOSTNAME,$OS_TYPE $DISTRO $RELEASE,$NET_PUBIP,,$MP,LVM,,$MP_TSIZE_G,$MP_FSIZE_G,${PFREE}%,$MP_USIZE_G,$TOTALGB,$HW_CPU_NAME"

   else
      echo ",,,,$MP,LVM,,$MP_TSIZE_G,$MP_FSIZE_G,${PFREE}%,$MP_USIZE_G,,"

   fi

   

   let FSCOUNT=$FSCOUNT+1



done

# Enumerate ASM disks if any

#for ASMD in `/sbin/blkid | grep oracleasm | awk -F':' '{print $1}' | sed 's/[0-9]$//g' | sort -u`
for ASMD in `/sbin/blkid | grep oracleasm | awk -F':' '{print $1}'`; do

   PTNAME=`echo $ASMD | sed 's/\/dev\///'`
   BDNAME=`echo $ASMD | sed 's/[0-9]$//g;s/\/dev\///'`
   ASMN=`/sbin/blkid $ASMD | awk -F'"' '{print $2}'`

   ASMD_SIZE=$( echo "$( cat /sys/block/${BDNAME}/${PTNAME}/size ) * 512 / 1024 / 1024 / 1024 " | bc )

   echo ",,,,,ASM,$ASMN,$ASMD_SIZE,,,,,"
done

   

exit


