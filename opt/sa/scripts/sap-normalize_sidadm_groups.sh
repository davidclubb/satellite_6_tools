#!/bin/bash

# 20160304 SDW

# Adds "<SID>adm" user to specified groups

# If not running with an effective UID of 0, then silently restart with SUDO
if [[ $EUID -ne 0 ]]; then
   /usr/bin/sudo $0 $@
   exit
fi

# Locations:

ULIST=/opt/sa/lists/SAP/user-uidlist.csv

GROUPLIST="dba sapinst oper oinstall asmoper asmdba"


TS=`date +%Y%m%d%H%M%S`

f_Usage() {

   echo "Usage:"
   echo "`basename $0`"
   echo "OR"
   echo "`basename $0` E"
   echo ""
   echo "Description: This script will identify <SID>adm users and add"
   echo "             them to the correct secondary groups"
   echo ""
   echo "E causes the script to commit changes, otherwise it will just test"
   echo ""
   


}

MODE=RO
if [[ "$1" == "E" ]]; then
   MODE=EXEC
fi

# Validate that the user list is readable
USELIST=TRUE
if [[ ! -s $ULIST ]]; then
   USELIST=FALSE
   echo "Warning: user list [$ULIST] is not visible."
fi

# Get a list of all local users

LOCUSERS=`awk -F':' '{print $1}' /etc/passwd`

# Get a list of SAP users to be updated from the system
if [[ $USELIST == TRUE ]]; then

   unset SAPSAS
   for LOCUSER in $LOCUSERS; do
      # If the local user is in the SAP users list and doesn't match one of the filtered names, add it to the list
      if [[ -n `grep "^${LOCUSER}," $ULIST | egrep "adm,"` ]] && [[ -n `echo $LOCUSER | egrep -v 'sapadm|daaadm'` ]]; then
         SAPSAS="$SAPSAS $LOCUSER"
      fi
 
   done
   

else

   # Make a guess about which local users are SAP service accounts

   unset SAPSAS
   for LOCUSER in $LOCUSERS; do
      if [[ -n `echo $LOCUSER | egrep "adm$"` ]] && [[ -n `echo $LOCUSER | egrep -v 'sapadm|daaadm'` ]]; then
         SAPSAS="$SAPSAS $LOCUSER"
      fi
   done

fi

if [[ -z $SAPSAS ]]; then
   echo "No SAP service accounts identified, nothing to do."
   exit
fi

if [[ "$MODE" == "EXEC" ]]; then
   # Create a backup of the group file
   /bin/cp -rp /etc/group /etc/group.${TS}
   
   if [[ -s /etc/group.${TS} ]]; then
      echo "The group file has been backed up to [/etc/group.${TS}]"
   else
      echo "Failed to back up the group file, aborting."
      exit 2
   fi
fi

# For each SAP service account, check to see if it's in the specified group, add it if not
for SAPSA in $SAPSAS; do
   for SG in $GROUPLIST; do

      # If the group exists on the server and SAPSA is not in it, then add it
      if [[ -n `/usr/bin/getent group $SG` ]] && [[ -z `/usr/bin/id $SAPSA | awk 'NR > 1 {print $1}' RS='(' FS=')' | egrep "^${SG}$"` ]]; then
         if [[ "$MODE" == "EXEC" ]]; then
            echo "Adding $SAPSA to $SG"
            /usr/sbin/usermod -a -G $SG $SAPSA
         else
            echo "I would add $SAPSA to $SG"
         fi
      fi

   done
done


