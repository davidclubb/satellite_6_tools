#!/bin/bash

# 2017 SDW
# This script changes the root password on remote Linux servers and records the password for retrieval by admins.


#### BEGIN VARIABLE AND FUNCTION DEFS ####

# SSH variables for connecting to the remote host
SSHUSER=unixpa
SSHKEY=/root/.upak
SSHCOMM="/usr/bin/ssh -q -o stricthostkeychecking=no -o userknownhostsfile=/dev/null -o batchmode=true -i $SSHKEY"

# Locations
VAULTDIR=/root/pv
HIST=${VAULTDIR}/history
ERRORLOG=$VAULTDIR/error.log
CHANGELOG=$VAULTDIR/change.log

# Expect script to check the password after it's written
CHECKPASS=/opt/satellite/maintenance/scripts/checkpass.exp

BLACKLIST="
knerhsilp001
knerhsilp002
kneslxild001
"

f_Usage() {

   echo "$0 USAGE"
   echo ""
   echo "$0 <fqdn> [<IPv4>]"
   echo ""
   echo "WHERE"
   echo ""
   echo "  <fqdn>   Is the fully qualified domain name of the remote server on which to"
   echo "           change the root password."
   echo ""
   echo "  <IPv4>   Optionally provide an explicit IPv4 address for when DNS is unreliable"
   echo "           or ambiguous."
   echo ""
}
#### END VARIABLE AND FUNCTION DEFS ####

#### BEGIN PRE CHECK ####

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege." 1>&2
   echo "         Setup has not been completed on this system." 1>&2
   exit 20
fi

if [[ $# -gt 2 ]]; then
   echo "FAILURE: Invalid argument count." 1>&2
   exit 21
fi

if [[ -z $1 ]]; then
   echo "FAILURE: A valid hostname must be provided as an argument." 1>&2
   exit 22
fi

#### END PRE CHECK ####

#### BEGIN USER INPUT AND VALIDATION ####

# Check to see if an IP was passed in

if [[ -n $2 ]]; then

   unset VALIDIP

   # Verify we have a valid IPv4 address
   if [[ -n `echo $2 | egrep -e "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"` ]]; then
      VALIDIP=$2
   fi

fi


gRHOST=$1

## Check hostname
# Santitize user input
RHOST=`echo $gRHOST | tr '[:upper:]' '[:lower:]' | tr -d '[;!@#$%^&*()+=|{}[] ]'`

# Validate the hostname of the remote host
# - Verify host is in DNS - or that we have a valid IP.
if [[ -z `getent hosts $RHOST` ]]; then
   if [[ -n $VALIDIP ]]; then
      echo "Warning: $RHOST is not in DNS, will continue with recorded IP."
   else
      echo "Error: hostname $RHOST cannot be resolved." 1>&2
      exit 1
   fi
fi

# - Sloppy way to enforce FQDN by looking for 2 dots in the string
if [[ $(echo $RHOST | grep -o '\.' | wc -l) -ne 2 ]]; then
   echo "Error: $RHOST is not a fully qualified hostname." 1>&2
   exit 2
fi
# - Make sure the hostname is not in the blacklist
for H in $BLACKLIST; do
   if [[ -n `echo $RHOST | grep -i $H` ]]; then
      echo "Warning: the host [$H] is blacklisted."
      exit 3
   fi
done

# Default the SSH target to the hostname

SSHTARGET=$RHOST

# Override the SSH target if we have a valid IP address
if [[ -n $VALIDIP ]]; then

   SSHTARGET=$VALIDIP

fi

# See if we can connect via SSH
$SSHCOMM ${SSHUSER}@${SSHTARGET} /bin/true
RETCODE=$?
if [[ "$RETCODE" != "0" ]]; then
   echo "Error connecting to $RHOST via SSH.  Please make sure $SSHUSER exists on that system and that its public key is in the authorized keys file." 1>&2
   exit $RETCODE
else
   # See if we can sudo via SSH
   ANSWER=$($SSHCOMM ${SSHUSER}@${SSHTARGET} sudo -n whoami)
   if [[ "$ANSWER" != "root" ]]; then
      echo "Unable to issue commands via SUDO on $RHOST" 1>&2
      exit 4
   fi
fi


#### END USER INPUT AND VALIDATION ####

### Change Password
## Generate New Random Password ####

RANDOMPASS_PT=$(/bin/openssl rand -base64 9)
RANDOMPASS_HS=$(/bin/python -c "import crypt; print crypt.crypt(\"$RANDOMPASS_PT\",crypt.mksalt(crypt.METHOD_SHA512))" | sed 's/\$/\\\$/g')
#echo $RANDOMPASS_HS

# double check our variables just before we run the command << Paranoia
if [[ -z $SSHCOMM ]] || [[ -z $SSHUSER ]] || [[ -z $SSHTARGET ]]; then
   echo "Failure"
   exit 99
fi

# Attempt to update the password
$SSHCOMM ${SSHUSER}@${SSHTARGET} "sudo /usr/sbin/usermod -p $RANDOMPASS_HS root"

# Prepare the vault directories if they don't exist
if [[ ! -d $VAULTDIR ]]; then mkdir -p $VAULTDIR; fi
if [[ ! -d $HIST ]]; then mkdir -p $HIST; fi

# Archive existing history files for this host
for HFILE in `ls ${HIST} | grep "^${RHOST}" | grep -v "tar$"`; do

   # Define the history tar file for this host
   HISTAR=${HIST}/${RHOST}.tar

   # If the tar file doesn't exist, create it, if it does, append it
   if [[ ! -s $HISTAR ]]; then
      tar -C ${HIST} -cf $HISTAR $HFILE
   else
      tar -C ${HIST} -rf $HISTAR $HFILE
   fi

   # Delete the the history file if it was correctly archived
   if [[ -n `tar -tf $HISTAR | grep $HFILE` ]]; then
      /bin/rm ${HIST}/${HFILE}
   fi
done


# Set the value of the vault and history files
TS=`date +%Y%m%d%H%M%S`
CURRENTFILE=$VAULTDIR/$RHOST
HISTFILE=$HIST/${RHOST}.${TS}

# Write the history file
echo $RANDOMPASS_PT > $HIST/$RHOST.`date +%Y%m%d%H%M%S`

# Write the current password file
echo $RANDOMPASS_PT > $VAULTDIR/$RHOST

# Verify the new password works
$CHECKPASS root $SSHTARGET $HISTFILE
CHECK=$?

if [[ $CHECK -eq 0 ]]; then
   
   echo "$TS: root password successfully updated for $RHOST" | tee -a $CHANGELOG

else

   echo "$TS: root password change for $RHOST was performed but failed validation. Previous password may still be active." >> $ERRORLOG
   echo "$TS: root password change for $RHOST was performed but failed validation." 1>&2
   exit 255

fi
exit 0

