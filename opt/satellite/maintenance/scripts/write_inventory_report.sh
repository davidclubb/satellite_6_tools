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

source /opt/satellite/maintenance/scripts/.inv.env

PULL_INVENTORY='pull_inventory.sh'
INVENTORY_FILENAME='satellite_inventory_report.csv'

#### STATE CONFIGURATION ####
# Check to see if the target mount point is already mounted
if [[ -n `grep "$T_CIFS_MP" /etc/mtab` ]]; then
   umount $T_CIFS_MP
   # Make sure it's no longer mounted before proceeding
   if [[ -n `grep "$T_CIFS_MP" /etc/mtab` ]]; then
      echo "Error: unable to unmount previously mounted target directory."
      exit 1
   fi
fi

mkdir -p $T_CIFS_MP

# Attempt to mount the cifs target
/bin/mount -t cifs //${T_CIFS_SERVER}/${T_CIFS_PATH} ${T_CIFS_MP} -o "user=${CIFS_USER},pass=${CIFS_PASS},${CIFS_OPTIONS}"

# Check to see if the target mount point was succesfully mounted
if [[ -z `grep "$T_CIFS_MP" /etc/mtab` ]]; then
   echo "Error: unable to mount directory on target server"
   exit 2
fi

# Write inventory file to cifs share
./${PULL_INVENTORY} > "${T_CIFS_MP}/${INVENTORY_FILENAME}"
#./${PULL_INVENTORY} >> "${T_CIFS_MP}/${INVENTORY_FILENAME}"

# Unmount cifs share
umount $T_CIFS_MP

# Verify it was unmounted
if [[ -n `grep "$T_CIFS_MP" /etc/mtab` ]]; then
   echo "Error: unable to unmount previously mounted target directory."
   exit 3
fi

# Remove the mountpoint
/bin/rmdir $T_CIFS_MP



exit


