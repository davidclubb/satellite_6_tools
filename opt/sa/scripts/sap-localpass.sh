#!/bin/bash

# 20150824 SDW

# Sets or unsets the local password for local SAP users

# If not running with an effective UID of 0, then silently restart with SUDO
if [[ $EUID -ne 0 ]]; then
   /usr/bin/sudo $0 $@
   exit
fi

# Locations:

ULIST=/opt/sa/lists/SAP/user-uidlist.csv

SET_HASH='$5$efMM1exs$05aRxg/4S8iAxNniDLU7Bo08vf5M6kIMtkrDAr/FqZB'

TS=`date +%Y%m%d%H%M%S`

f_Usage() {

   echo "Usage:"
   echo "`basename $0` -s"
   echo "   OR"
   echo "`basename $0` -u"
   echo ""
   echo "Description: This script will set or unset the password for"
   echo "             SAP service accounts.  The passwords need to be"
   echo "             usable during upgrades and support packs, but"
   echo "             should otherwise be disabled."
   echo ""
   echo "Modes:"
   echo "-s  Will set the password to the standard value"
   echo "-u  Will unset the password"
   


}

if [[ $# -ne 1 ]]; then
   echo "Invalid argument(s): [$@]"
   f_Usage
   exit

fi

case $1 in 

   -s ) MODE=SET
        ;;
   -u ) MODE=UNSET
        ;;
    * ) echo "Invalid mode: [$1]"
        f_Usage
        exit
        ;;
esac

echo "Mode is [$MODE]"

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
      if [[ -n `grep "^${LOCUSER}," $ULIST` ]] && [[ -n `echo $LOCUSER | egrep -v 'sapadm'` ]]; then
      #if [[ -n `grep "^${LOCUSER}," $ULIST` ]]; then
         SAPSAS="$SAPSAS $LOCUSER"
      fi
 
   done
   

else

   # Make a guess about which local users are SAP service accounts

   unset SAPSAS
   for LOCUSER in $LOCUSERS; do
      if [[ -n `echo $LOCUSER | egrep "^ora|adm$"` ]] && [[ -n `echo $LOCUSER | egrep -v 'sapadm'` ]]; then
      #if [[ -n `echo $LOCUSER | egrep "^ora|adm$"` ]]; then
         SAPSAS="$SAPSAS $LOCUSER"
      fi
   done

   # If we're not using the explicit list, make the user validate the list before making any changes.

   echo "Passwords for the following accounts will be modified, please review and confirm."
   for SAPSA in $SAPSAS; do
      echo $SAPSA
   done
   read -p "Do you wish to continue with this list? ['Y' to continue, anything else to cancel]: " CONTINUE

   if [[ -z `echo $CONTINUE | egrep '^Y$|^y$'` ]]; then
      echo "Action cancelled."
      exit
   fi

fi

if [[ -z $SAPSAS ]]; then
   echo "No SAP service accounts identified, nothing to do."
   exit
fi

# Create a backup of the shadow file
/bin/cp -rp /etc/shadow /etc/shadow.${TS}

if [[ -s /etc/shadow.${TS} ]]; then
   echo "The shadow file has been backed up to [/etc/shadow.${TS}]"
else
   echo "Failed to back up the shadow file, aborting."
   exit 2
fi

# Change the password for each user according to mode
for SAPSA in $SAPSAS; do
   if [[ $MODE == SET ]]; then
      echo "Setting password for [$SAPSA]"
      /usr/sbin/usermod -p $SET_HASH $SAPSA
   elif [[ $MODE == UNSET ]]; then
      echo "Unsetting the password for [$SAPSA]"
      /usr/sbin/usermod -p x $SAPSA
   else
      echo "Unrecognized mode [$MODE]. The script is broken."
      exit 1
   fi
done


