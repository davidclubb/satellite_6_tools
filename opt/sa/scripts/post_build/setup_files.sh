#!/bin/bash

# Author: SDW
# Incept: 20150121
# Purpose: Copy files that are easier to provide without RPMs

# Include common_functions.h
SCRIPTDIR=/opt/sa/scripts/post_build

# Locate and source common_functions.h
if [[ -s "/opt/sa/scripts/common_functions.sh" ]]; then
   source "/opt/sa/scripts/common_functions.sh"
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.sh"
   exit
fi


### ACME Signage

# Boot splash
/bin/cp "${SCRIPTDIR}/binary_files/splash.xpm.gz_acme_plain" "/boot/grub/splash.xpm.gz"
RETCODE=$?
if [[ $RETCODE != 0 ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Error copying new boot splash to GRUB" | $LOG1
   else
      echo "Error copying new boot splash to GRUB"
   fi
fi



