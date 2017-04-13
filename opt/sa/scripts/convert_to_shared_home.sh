#!/bin/bash

# Implement a shared home drive

#NFS_SERVER=khonesdcfsv02
NFS_SERVER=knenfsmdc001
NFS_SHARE_PATH=/home
SHARED_HOME="${NFS_SERVER}:${NFS_SHARE_PATH}"
LOCAL_HOME_PATH=/usr/local/home
SHARED_HOME_TMP=/tmp/sharedhome
MOUNT_OPTS=soft,intr,defaults
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


# Check to see if shared home has already been implemented.
echo "Checking to see if this system already uses shared home"
if [[ -n `egrep 'nfs|cifs' /etc/mtab | grep "[[:space:]]/home[[:space:]]"` ]]; then
   echo "It looks like this system is already using a shared home"
   grep "/home" /etc/mtab
   exit 0
fi

# Check to make sure /home is defined as a seperate file system
echo "Checking to see if /home is its own file system"
if [[ -z `awk '{print $2}' /etc/mtab | grep "^/home$"` ]]; then
   echo "This system does not use a separate filesystem for /home"
   echo "Please manually migrate /home"
   exit 0
else
   # Get the name of the local home disk from fstab
   LHD=`egrep -v "^$|^#" /etc/fstab | grep "[[:space:]]/home[[:space:]]" | awk '{print $1}'`
   echo "Identified [$LHD] as the local home device"
fi

# Mount shared home to a temporary location  (if it isn't already mounted)
echo "Atempting to temporarily mount [$SHARED_HOME] to [$SHARED_HOME_TMP]"
if [[ -z `grep "[[:space:]]${SHARED_HOME_TMP}[[:space:]]" /etc/mtab` ]]; then
   if [[ ! -d $SHARED_HOME_TMP ]]; then
      mkdir -p $SHARED_HOME_TMP
   fi
   mount -o $MOUNT_OPTS $SHARED_HOME $SHARED_HOME_TMP
else
   echo "Already mounted."
fi

# Make sure it mounted successfully before proceeding
if [[ -z `grep "[[:space:]]${SHARED_HOME_TMP}[[:space:]]" /etc/mtab` ]]; then
   echo "Failure: $SHARED_HOME_TMP not mounted to $SHARED_HOME"
   echo "         please investigate the cause and try again."
   exit 1
fi

# Create mount for new home path if it doesn't exist
if [[ ! -d $LOCAL_HOME_PATH ]]; then
   echo "Creating [$LOCAL_HOME_PATH]"
   mkdir -p $LOCAL_HOME_PATH
fi

# Mount local home device to new home path if it's not already mounted
echo "Mounting [$LHD] to [$LOCAL_HOME_PATH]"
if [[ -z `grep "[[:space:]]${LOCAL_HOME_PATH}[[:space:]]" /etc/mtab` ]]; then
   mount $LHD ${LOCAL_HOME_PATH}
fi

# Ensure the local home device was successfully mounted to its new mount point
if [[ -z `grep "[[:space:]]${LOCAL_HOME_PATH}[[:space:]]" /etc/mtab` ]]; then
   echo "Error: unable to mount [$LHD] to [$LOCAL_HOME_PATH]"
   exit 2
fi



# Get a list of home directories defined on the local /home
echo "Getting a list of home directories on the local device"
LOC_HDIRS=`find /home -maxdepth 1 -type d -exec basename {} \; | egrep -v "^$|home|lost\+found"`

# Process each local home directory
for LOC_HDIR in $LOC_HDIRS; do

   echo "Checking [$LOC_HDIR]"

   # Verify that the directory is owned by an active user
   if [[ -n `getent passwd | egrep -vi "disabled|Secure-24|S24" | grep ":/home/${LOC_HDIR}:"` ]]; then
      echo "   Info: the home directory is owned by an active user"
      
      echo "   Info: checking to see if the directory is in use"
      if [[ -n `lsof /home/${LOC_HDIR}` ]]; then
         echo "   Warning: The home directory is currently in use."
      fi

      # Determine whether the user is local
      if [[ -n `grep ":/home/${LOC_HDIR}:" /etc/passwd` ]]; then

         echo "   Info: belongs to a locally defined user"

         # Create a backup of /etc/passwd if one has not already been created for this
         # Iteration of the script
         if [[ ! -s /etc/passwd.${TS} ]]; then
            echo "   Info: creating a backup of /etc/passwd at /etc/passwd.${TS}"
            /bin/cp -p /etc/passwd /etc/passwd.${TS}
         fi
        
         if [[ ! -s /etc/passwd.${TS} ]]; then
            echo "   Error: unable to create a backup of /etc/passwd, aborting."
            exit 3
         fi


         # Local users will have their home directory values re-pointed to /usr/local/home
         # Get local username 
         U=`grep ":/home/${LOC_HDIR}:" /etc/passwd | awk -F':' '{print $1}'`
         echo "   Info: this home directory is owned by [$U]"

         echo "   Info: Setting new home directory for [$U] to [${LOCAL_HOME_PATH}/${LOC_HDIR}]"

         #usermod -d "${LOCAL_HOME_PATH}/${LOC_HDIR}" $U
         # Usermod will not change a user's home path while the user is logged in, we're 
         # willing to risk it.
       
         # Escape slashes in the user's old home directory
         EUOH=`grep "^${U}:" /etc/passwd | awk -F':' '{print $6}' | sed 's/\\//\\\\\//g'`

         # Escape slashes in the user's new home directory
         EUNH=`echo "${LOCAL_HOME_PATH}/${LOC_HDIR}" | sed 's/\\//\\\\\//g'`

         # Update /etc/passwd with the user's new home directory
         sed -i "/^$U:/s/:$EUOH:/:$EUNH:/" /etc/passwd

         
      else

         echo "   Info: belongs to a remotely defined user"
         # Non-local users will have their home directory copied to the shared home path if it doesn't already exist there
         echo "   Info: checking to see if [${SHARED_HOME_TMP}/${LOC_HDIR}] already exists."
         if [[ ! -d "${SHARED_HOME_TMP}/${LOC_HDIR}" ]]; then
            echo "   Info: this user does not yet exist in shared home, copying the home drive to shared home"
            /bin/cp -rp "/home/${LOC_HDIR}" "${SHARED_HOME_TMP}/${LOC_HDIR}"

         else
            echo "   Info: this user already has a home directory on shared home, skipping"
         fi
         

      fi   # End local user check

   else
      echo "   Info: this home directory does not belong to an active user, skipping"

   fi # End active user check

done

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

# Escape all of the slashes in the local home device path
ELHD=`echo $LHD | sed 's/\\//\\\\\//g'`

# Escspe all of the slashes in the new local home mount point path
ELHP=`echo $LOCAL_HOME_PATH | sed 's/\\//\\\\\//g'`

# Replace the mount point for the local home device
sed -i "/^$ELHD/s/\/home/$ELHP/" /etc/fstab

# Escape all of the slashes in the shared home device
ESH=`echo $SHARED_HOME | sed 's/\\//\\\\\//g'`

# Remove any current reference to the shared home
sed -i "/^$ESH/d" /etc/fstab

# Add the definition to mount shared home to /home
echo "${SHARED_HOME}  /home  nfs  ${MOUNT_OPTS}  0 0" >> /etc/fstab 

# Verify that fstab has the expect number of lines
let ELC=$LCB+1

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

# At this point, LOCAL_HOME_PATH (/usr/local/home) should already be mounted.
# We're going to re-mount it to make sure fstab looks right
if [[ -n `grep "[[:space:]]$LOCAL_HOME_PATH[[:space:]]" /etc/mtab` ]]; then
   umount -l $LOCAL_HOME_PATH
fi
mount $LOCAL_HOME_PATH
if [[ -z `grep "[[:space:]]$LOCAL_HOME_PATH[[:space:]]" /etc/mtab` ]]; then
   echo "Error: unable to mount $LOCAL_HOME_PATH from /etc/fstab, please check it."
fi

# Unmount the temporary shared home
if [[ -n `grep "[[:space:]]$SHARED_HOME_TMP[[:space:]]" /etc/mtab` ]]; then
   umount -l $SHARED_HOME_TMP
fi

# Unmount /home and re-mount it
if [[ -n `grep "[[:space:]]/home[[:space:]]" /etc/mtab` ]]; then
   umount -l /home
fi
mount /home

service nscd reload

# Completion message
echo "Move to a shared home is now complete.  If there were warnings above about"
echo "home directories being in use or users currently logged in, it's best"
echo "to log them out and back in."





