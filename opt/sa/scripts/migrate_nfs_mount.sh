#!/bin/bash

# Read argument

f_Usage () {

   echo "Usage: "
   echo "      `basename $0` <mount point> <from share> <to share>"

   


}
if [[ $# -lt 3 ]]; then
   echo "Please provide the mount point to be migrated"
   exit 1
fi

MOUNTPOINT=$1
   
if [[ ! -d $MOUNTPOINT ]]; then
   echo "Error: [$MOUNTPOINT] is not a valid mount point"
   exit 2
fi

# Migrate NFS mount
FROM_NFS_SERVER=khonesdcfsv02
TO_NFS_SERVER=knenfsmdc001
FROM_SHARE=$2
TO_SHARE=$3
SHARE_TMP=/tmp/sharetmp
TS=`date +%Y%m%d%H%M%S`

# Checking to make sure there are no hung file handles
echo "Checking system health"
lsof 2>&1 | >> /dev/null &

TIMEOUT=60
CHECK=0
while [[ -n `jobs` ]]; do
   #For some reason jobs will not update during the test unless it is evoked each time through the loop
   jobs &>/dev/null
   let CHECK=$CHECK+1

   if [[ $CHECK -ge $TIMEOUT ]]; then
      kill -9 `jobs -l | awk '{print $2}'` 2>&1 | >> /dev/null
      echo "Error: server appears to be in an unhealthy state"
      echo "       open files check timed out after [$TIMEOUT] seconds."
      exit 6
   fi
   
   sleep 1

done

echo "Confirming that $MOUNTPOINT is a valid NFS share"
if [[ -z `egrep 'nfs' /etc/mtab | grep "[[:space:]]${MOUNTPOINT}[[:space:]]"` ]]; then
   echo "Error: $MOUNTPOINT is not an NFS share "
   exit 0
fi


echo "Checking to see if this system already uses the new share"
if [[ -n `grep "[[:space:]]${MOUNTPOINT}[[:space:]]" /etc/mtab | egrep "^${TO_SHARE}"` ]]; then
   echo "It looks like this system is already using a the correct share for $MOUNTPOINT"
   grep "[[:space:]]${MOUNTPOINT}[[:space:]]" /etc/mtab
   exit 0
fi


# Update fstab with the new settings and shuffle mounts
if [[ ! -s /etc/fstab.${TS} ]]; then
   echo "Creating a backup of /etc/fstab as /etc/fstab.${TS}"
   /bin/cp -p /etc/fstab /etc/fstab.${TS}
fi

if [[ ! -s /etc/fstab.${TS} ]]; then
   echo "Error: unable to create backup of /etc/fstab"
   echo "       please address the problem and try again."
   exit 4
fi

# Count the number of lines in /etc/fstab
LCB=`cat /etc/fstab | wc -l`

# Escape all of the slashes in the share names
EFROM_SHARE=`echo $FROM_SHARE | sed 's/\\//\\\\\//g'`
ETO_SHARE=`echo $TO_SHARE | sed 's/\\//\\\\\//g'`

# Replace the FROM share with the TO share in fstab
sed -i "/^$EFROM_SHARE/s/^$EFROM_SHARE/$ETO_SHARE/" /etc/fstab

# Verify that fstab has the expect number of lines
let ELC=$LCB

# Check the number of lines it has now
LCA=`cat /etc/fstab | wc -l`

# If we're missing lines, abort
if [[ $LCA -lt $ELC ]]; then
   echo "Failure: /etc/fstab is supposed to be [$ELC] lines long, but is only [$LCA]."
   echo "         restoring the backup.  The invalid file will be saved as /etc/fstab.failed"

   /bin/cp /etc/fstab /etc/fstab.failed
   /bin/cp -p /etc/fstab.${TS} /etc/fstab

   exit 5
fi


# Now that /etc/fstab has the new definitions, umount and remount the volume
# We're going to re-mount it to make sure fstab looks right
if [[ -n `grep "[[:space:]]$MOUNTPOINT[[:space:]]" /etc/mtab` ]]; then
   umount -l $MOUNTPOINT
fi
mount $MOUNTPOINT
if [[ -z `grep "[[:space:]]$MOUNTPOINT[[:space:]]" /etc/mtab` ]]; then
   echo "Error: unable to mount $MOUNTPOINT from /etc/fstab, please check it."
fi

echo "Migration of NFS mount [$MOUNTPOINT] from [$FROM_SHARE] to [$TO_SHARE]" is complete.




