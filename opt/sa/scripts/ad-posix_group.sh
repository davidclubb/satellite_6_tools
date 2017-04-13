#!/bin/bash

# Script for manipulating POSIX attributes for an AD group

source /opt/sa/scripts/.adposix.env

LDAPSEARCH="/bin/ldapsearch -H ldap://${DOMAIN} -Y GSSAPI"
LDAPMODIFY="/bin/ldapmodify -H ldap://${DOMAIN} -Y GSSAPI"

f_Usage() {
   echo "USAGE:"
   echo ""
   echo "$0"
   echo ""
   echo "   OR"
   echo ""
   echo "$0 -a|-r <TARGETGROUP>"
   echo ""
   echo "   WHERE"
   echo ""
   echo "     -a   Add POSIX attributes to AD group"
   echo "     -r   Remove POSIX attributes from AD group"
   echo "     -h   Print this usage message"
   echo ""
   echo "<TARGETGROUP> is the Active Director group upon which the operation"
   echo "              will be performed."
   echo ""
   echo "Executing the script without arguments or omitting required arguments"
   echo "will cause it to prompt interactively for the required arguments."
}

# Get command line arguments
OPERATION=$1
GTARGETGROUP=$2

if [[ -n $3 ]]; then
   echo "Error: invalid argument detected.  Please note, group names with spaces are"
   echo "       not supported."
   f_Usage
   exit
fi

# Validate operation argument

if [[ -z $OPERATION ]]; then
   read -p "Specify the operation to be performed (-a|-r): " OPERATION
   #echo "Debug: got [$OPERATION]"
fi

case $OPERATION in

   -a ) MODE=ADD
        ;;

   -r ) MODE=REMOVE
        ;;

   -h ) f_Usage
        exit
        ;;
    * ) echo "Error: [$OPERATION] is not a valid operation."
        echo ""
        f_Usage
        exit
        ;;
esac



# Verify we can authenticate:

# If the script is being run by a non-admin account, ask for an admin account
if [[ -z `echo $USER | egrep -ie '^[a-z0-9]{2,3}.admin$'` ]]; then

   echo ""
   echo "This script is not being run with an Admin ID"
   echo ""
   echo "To make changes to AD, you must connect to the directory"
   echo "with a user ID with sufficient authority. (This account does"
   echo "not need to be a POSIX account)"
   echo ""
   read -p "Provide an AD ID with rights to modify user attributes: " AID
   echo ""

else

   AID=$USER

fi

# Check to see if we already have a kerberos ticket
if [[ -n `/bin/klist 2>&1 | grep "$SPN"` ]]; then
   #echo "Debug: found an existing kerberos ticket"  
   # If we have a ticket, make sure it's still valid
   
   NOW=$( date +%s )
   EXP=$(date -d "$(klist | grep $SPN | awk '{print $3,$4}')" +%s)

   if [[ $NOW -ge $EXP ]]; then
      echo "Existing Kerberos ticket is expired, requesting a new one."
      # if the expiration is in the past, then request a new ticket
      /bin/kinit ${AID}@${REALM}
      KRESULT=$?
      if [[ $KRESULT -ne 0 ]]; then
         echo "Error authenticating with Kerberos."
         exit
      fi

   #else
      #echo "Debug: existing ticket is still valid"

   fi

else

   # Request a ticket
   /bin/kinit ${AID}@${REALM}
   KRESULT=$?
   if [[ $KRESULT -ne 0 ]]; then
      echo "Error authenticating with Kerberos."
      exit
   fi


fi

# Prompt for the TARGETGROUP if not already provided

if [[ -z $GTARGETGROUP ]]; then
   read -p "Please provide the name of the target group: " GTARGETGROUP
fi

# Set the targetgroup to lower-case
TARGETGROUP=$(echo $GTARGETGROUP | tr '[:upper:]' '[:lower:]')

# Validate the TARGETGROUP
if [[ -z $($LDAPSEARCH -Q "(&(cn=$TARGETGROUP)(objectclass=group))" | grep ^cn: ) ]]; then
   echo "Error: Unable to find the group [$TARGETGROUP] in Active Directory."
   exit
fi


case $MODE in

      ADD ) # Check to see if this group already has POSIX attributes
            if [[ -n `$LDAPSEARCH -Q "(&(cn=$TARGETGROUP)(objectclass=group))" | egrep '^msSFU30NisDomain:|^msSFU30Name:|^gidNumber'` ]]; then
               echo "Error: [$TARGEGROUP] already has POSIX attributes. Please use -r if you wish to remove them."
               exit
            fi

            # Set the distingushed name for the group object
            TG_DN=$($LDAPSEARCH -Q "(&(cn=$TARGETGROUP)(objectclass=group))" | sed ':a;N;$!ba;s/\n //g' | grep ^dn: | sed 's/^dn: //g') 

            # Find the next free UID - this is a very simple +1 to the highest number found, it will not fill in gaps
            let HIGHESTGID=$($LDAPSEARCH -Q '(&(objectClass=group)(gidnumber=*))' gidNumber | egrep "^gidNumber:" | awk '{print $2}' | sort -un | tail -1 )
            if [[ -n $HIGHESTGID ]]; then
               let NEXTFREEGID=$HIGHESTGID+1
            else
               echo "Error: unable to read GIDs from AD"
               exit
            fi
            #let NEXTFREEGID=$($LDAPSEARCH -Q '(&(objectClass=group)(gidnumber=*))' gidNumber | egrep "^gidNumber:" | awk '{print $2}' | sort -un | tail -1 )+1


            # Build the LDIF
            LDIF_TMP=/tmp/$$.ldt

            echo "dn: $TG_DN" > $LDIF_TMP
            echo "changetype: modify" >> $LDIF_TMP
            echo "replace: msSFU30NisDomain" >> $LDIF_TMP
            echo "msSFU30NisDomain: ACMEPLAZA" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: msSFU30Name" >> $LDIF_TMP
            echo "msSFU30Name: $TARGETGROUP" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: gidNumber" >> $LDIF_TMP
            echo "gidNumber: $NEXTFREEGID" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP

            # Modify the user
            $LDAPMODIFY -Q -a -f $LDIF_TMP
            ERROR=$?

            if [[ $ERROR -ne 0 ]]; then
               echo "Error: group [$TARGETGROUP] not updated successfully."
               echo "The LDIF is located at [$LDIF_TMP]"
               exit
            else
               echo "[$TARGETGROUP] has been updated."
               echo ""
               $LDAPSEARCH -Q "(&(cn=$TARGETGROUP)(objectclass=group))" | sed ':a;N;$!ba;s/\n //g' | egrep -i '^description:|^mssfu30nisdomain:|^mssfu30name:|^gidnumber:' | sed 's/^/   /g' | sort -k1
               echo ""
               if [[ -f $LDIF_TMP ]]; then /bin/rm $LDIF_TMP; fi
               exit 0
            fi

            
            ;;

   REMOVE ) # Check to see if this group has POSIX attributes

            BLACKLIST="linuxloginusers IMSvrAdminL3Admins"

            for GN in $BLACKLIST; do
               if [[ -n `echo $TARGETGROUP | egrep -i "^${GN}$"` ]]; then
                  echo "Error: the group [$TARGETGROUP] is blacklisted. You may not modify it."
                  exit
               fi
            done

            if [[ -z `$LDAPSEARCH -Q "(&(cn=$TARGETGROUP)(objectclass=group))" | egrep '^msSFU30NisDomain:|^msSFU30Name:|^gidNumber:'` ]]; then
               echo "[$TARGETGROUP] does not have POSIX attributes. Nothing to do."
               exit 0
            fi

            OUT_TMP=/tmp/$$.otmp

            # Dump the group's LDAP object into a temp file
            $LDAPSEARCH -Q "(&(cn=$TARGETGROUP)(objectclass=group))" | sed ':a;N;$!ba;s/\n //g' > $OUT_TMP

            # Set the distingushed name for the group object
            TG_DN=$(grep ^dn: $OUT_TMP | sed 's/^dn: //g')

            # Get existing attributes for user (it would be more efficient to
            eGIDNUMBER=$(grep -i ^gidNumber: $OUT_TMP | sed 's/^gidNumber: //gi')
            eDESC=$(grep -i ^description: $OUT_TMP | sed 's/^description: //gi')

            # Get a list of users with this as primary group
            PMLIST=$($LDAPSEARCH -Q "(&(objectclass=user)(gidNumber=$eGIDNUMBER))" msSFU30Name | grep -i ^msSFU30Name: | sed 's/^msSFU30Name: //gi')
            
            if [[ -n $PMLIST ]]; then
               echo "ACTION ABORTED - no changes have been made."
               echo ""
               echo "The following users still have this group defined as primary group:"
               echo ""
               for PM in $PMLIST; do
                  echo "   $PM"
               done
               echo ""
               echo "Change primary GID on these users before attempting to remove "
               echo "POSIX attributes from [$TARGETGROUP]."
               echo ""
               exit
               
            fi

            # Get a list of users with this as a secondary group
            $LDAPSEARCH -Q "(&(objectclass=group)(gidNumber=$eGIDNUMBER))" member |  sed ':a;N;$!ba;s/\n //g' | grep ^member: | sed 's/^member: //gi' > $OUT_TMP

            
            
            if [[ -s $OUT_TMP ]]; then
               echo ""
               echo "The following users are (secondary) members of this group."
               echo "They will still appear as members in AD, but the group will"
               echo "not be accessible to POSIX systems."
               echo ""
               while read line; do
                  $LDAPSEARCH -Q -b "$line" samaccountname | grep -i ^samaccountname: | sed 's/^samaccountname: //gi' | sed 's/^/   /g'
               done < $OUT_TMP
               echo ""
               
            fi
            

            if [[ -f $OUT_TMP ]]; then /bin/rm $OUT_TMP; fi

            # Display the current user attributes
            echo "The current attributes for group [$TARGETGROUP]: "
            echo ""
            echo "        Description: $eDESC"
            echo "Numeric primary GID: $eGIDNUMBER" 
            echo ""
            
            echo "Warning: Removal of POSIX attributes cannot be undone."
            read -p "Type 'C' to continue removing POSIX attributes: " CONFIRMREMOVE
            
            if [[ "$CONFIRMREMOVE" != "C" ]]; then
               echo "Action cancelled by user."
               exit 0
            else

               # Build the LDIF
               LDIF_TMP=/tmp/$$.ldt
   
               echo "dn: $TG_DN" > $LDIF_TMP
               echo "changetype: modify" >> $LDIF_TMP
               echo "delete: msSFU30NisDomain" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: msSFU30Name" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: gidNumber" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
   
               # Modify the user
               $LDAPMODIFY -Q -a -f $LDIF_TMP
               ERROR=$?
   
               if [[ $ERROR -ne 0 ]]; then
                  echo "Error: group [$TARGETGROUP] not updated successfully."
                  echo "The LDIF is located at [$LDIF_TMP]"
                  exit
               else
                  echo "[$TARGETGROUP] has been updated."
                  if [[ -f $LDIF_TMP ]]; then /bin/rm $LDIF_TMP; fi
                  exit 0
               fi

               
            fi

            ;;
        * )
            ;;
esac


