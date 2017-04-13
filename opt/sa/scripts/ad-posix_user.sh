#!/bin/bash

# Script for adding POSIX attributes to an AD user account

source /opt/sa/scripts/.adposix.env

LDAPSEARCH="/bin/ldapsearch -H ldap://${DOMAIN} -Y GSSAPI"
LDAPMODIFY="/bin/ldapmodify -H ldap://${DOMAIN} -Y GSSAPI"

f_Usage() {
   echo "Adds, Removes or Modifies POSIX attributes for AD users."
   echo "USAGE:"
   echo ""
   echo "$0"
   echo ""
   echo "   OR"
   echo ""
   echo "$0 -a|-m <TARGETUSER> <PRIMARYGID> [<SHELL> <HOME>]"
   echo ""
   echo "   OR"
   echo ""
   echo "$0 -r <TARGETUSER>"
   echo ""
   echo "   WHERE"
   echo ""
   echo "     -a   Add POSIX attributes to AD user"
   echo "     -r   Remove POSIX attributes from AD user"
   echo "     -m   Modify POSIX attributes for AD user"
   echo "     -h   Print this usage message"
   echo ""
   echo "<TARGETUSER> is the Active Director Admin ID upon which the operation"
   echo "             will be performed."
   echo ""
   echo "<PRIMARYGID> is the numeric primary GID to be used for <TARGETUSER>."
   echo ""
   echo "<SHELL>      is an optional argument to set the user's login shell."
   echo "             The default is /bin/bash."
   echo ""
   echo "<HOME>       is the home directory to be used. By default the home"
   echo "             directory will be set to /home/<TARGETUSER>"
   echo ""
   echo "The script will also attempt to change relevant AD attributes to lower-"
   echo "case to simplify logins for the user."
   echo ""
   echo "Executing the script without arguments or omitting required arguments"
   echo "will cause it to prompt interactively for the required arguments."
}

# Get command line arguments
OPERATION=$1
GTARGETUSER=$2
PRIMARYGID=$3
GSHELL=$4
GHOME=$5

# Validate operation argument

if [[ -z $OPERATION ]]; then
   read -p "Specify the operation to be performed (-a|-r|-m): " OPERATION
   #echo "Debug: got [$OPERATION]"
fi

case $OPERATION in

   -a ) MODE=ADD
        ;;

   -r ) MODE=REMOVE
        ;;

   -m ) MODE=MODIFY
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
      echo "Existing ticket is expired, requesting a new one"
      # if the expiration is in the past, then request a new ticket
      kinit ${AID}@${REALM}
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
   kinit ${AID}@${REALM}
   KRESULT=$?
   if [[ $KRESULT -ne 0 ]]; then
      echo "Error authenticating with Kerberos."
      exit
   fi


fi

# Prompt for the TARGETUSER if not already provided

if [[ -z $GTARGETUSER ]]; then
   read -p "Please provide the login name of the target user: " GTARGETUSER
fi

# Set the targetuser to lower-case
TARGETUSER=$(echo $GTARGETUSER | tr '[:upper:]' '[:lower:]')

# Validate the TARGETUSER
if [[ -z $($LDAPSEARCH -Q "(samAccountName=$TARGETUSER)" | grep -i '^samAccountName:') ]]; then
   echo "Error: Unable to find the login name [$TARGETUSER] in Active Directory."
   exit
fi


case $MODE in

      ADD ) # Don't allow adding POSIX attributes to non-Admin IDs
            if [[ -z `echo $TARGETUSER | egrep -ie '^[a-z0-9]{2,3}.[a,z,x]dmin$'` ]]; then
               echo "Error: [$TARGETUSER] does not appear to be an Admin ID"
               if [[ "$OVERRIDE_NAME" == "TRUE" ]]; then
                  echo "Name override envoked. Do not add this user to LinuxLoginUsers!"
               else
                  exit
               fi
            fi
            # Check to see if this account already has POSIX attributes
            if [[ -n `$LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | egrep '^msSFU30NisDomain:|^msSFU30Name:|^uid:|^uidNumber:|^gidNumber:|^unixHomeDirectory:|^loginShell:'` ]]; then
               echo "Error: [$TARGETUSER] already has POSIX attributes. Please use -m if you wish to modify them."
               exit
            fi

            # Set the distingushed name for the user object
            TU_DN=$($LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | sed ':a;N;$!ba;s/\n //g' | grep ^dn: | sed 's/^dn: //g') 

            # Find the next free UID - this is a very simple +1 to the highest number found, it will not fill in gaps
            let NEXTFREEUID=$($LDAPSEARCH -Q '(&(objectClass=user)(uidnumber=*))' uidNumber | egrep "^uidNumber:" | awk '{print $2}' | sort -un | tail -1 )+1

            # Get a list of POSIX gidNumbers
            GIDLIST=$($LDAPSEARCH -Q '(&(objectClass=group)(gidnumber=*))' gidNumber | egrep "^gidNumber:" | egrep -v '10000|10004' | awk '{print $2}' | sort -un )


            if [[ -n $PRIMARYGID ]]; then
               SETGIDNUMBER=$PRIMARYGID
            else
               echo "This is a list of available primary groups: "
               $LDAPSEARCH -Q '(&(objectClass=group)(gidnumber=*))' cn gidNumber | egrep '^cn:|^gidNumber:' | sed ':a;N;$!ba;s/\n//g;s/cn:/\n/g;s/gidNumber: / /g' | egrep -v 'Domain Admins|LinuxLoginUsers' | awk '{print $2,$1}' | sed 's/^/   /g'
               echo ""
               read -p "Primary numeric GID [$eGIDNUMBER]: " GPGID

               if [[ -z $GPGID ]]; then
                  SETGIDNUMBER=$eGIDNUMBER
               else
                  SETGIDNUMBER=$GPGID
               fi

            fi

            VALIDGID=NO
            for GID in $GIDLIST; do
               if [[ "$GID" == "$SETGIDNUMBER" ]]; then
                  VALIDGID=YES
               fi
            done
            
            if [[ "$VALIDGID" != "YES" ]]; then
               echo "Error: Invalid GID [$SETGIDNUMBER] selected for $TARGETUSER."
               exit
            fi
            
            # Check for overrides for home and shell
            SETSHELL=/bin/bash
            SETHOME="/home/${TARGETUSER}"
            if [[ -n $GSHELL ]]; then
               if [[ -n `echo $GSHELL | egrep '^/bin/bash$|^/bin/ksh$|^/bin/csh$|^/bin/sh$|^/bin/false$|^/sbin/nologin$'` ]]; then
                  SETSHELL=$GSHELL
               fi
            fi
            if [[ -n $GHOME ]]; then
               SETHOME=$GHOME
            fi

            # Build the LDIF
            LDIF_TMP=/tmp/$$.ldt

            echo "dn: $TU_DN" > $LDIF_TMP
            echo "changetype: modify" >> $LDIF_TMP
            echo "replace: msSFU30NisDomain" >> $LDIF_TMP
            echo "msSFU30NisDomain: KIEWITPLAZA" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: msSFU30Name" >> $LDIF_TMP
            echo "msSFU30Name: $TARGETUSER" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: uid" >> $LDIF_TMP
            echo "uid: $TARGETUSER" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: uidNumber" >> $LDIF_TMP
            echo "uidNumber: $NEXTFREEUID" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: gidNumber" >> $LDIF_TMP
            echo "gidNumber: $SETGIDNUMBER" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: unixHomeDirectory" >> $LDIF_TMP
            echo "unixHomeDirectory: $SETHOME" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: loginShell" >> $LDIF_TMP
            echo "loginShell: $SETSHELL" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: sAMAccountName" >> $LDIF_TMP
            echo "sAMAccountName: $TARGETUSER" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: displayName" >> $LDIF_TMP
            echo "displayName: $TARGETUSER" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP

            # Modify the user
            $LDAPMODIFY -Q -a -f $LDIF_TMP
            ERROR=$?

            if [[ $ERROR -ne 0 ]]; then
               echo "Error: user [$TARGETUSER] not updated successfully."
               echo "The LDIF is located at [$LDIF_TMP]"
               exit
            else
               echo "[$TARGETUSER] has been updated."
               echo ""
               $LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | sed ':a;N;$!ba;s/\n //g' | egrep -i '^description:|^displayname:|^mssfu30nisdomain:|^mssfu30name:|^uid:|^uidnumber:|^gidnumber:|^unixhomedirectory:|^loginshell:' | sed 's/^/   /g' | sort -k1
               echo ""
               if [[ -f $LDIF_TMP ]]; then /bin/rm $LDIF_TMP; fi
               exit 0
            fi

            
            ;;
   MODIFY ) # Check to see if this account already has POSIX attributes
            if [[ -z `$LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | egrep '^msSFU30NisDomain:|^msSFU30Name:|^uid:|^uidNumber:|^gidNumber:|^unixHomeDirectory:|^loginShell:'` ]]; then
               echo "Error: [$TARGETUSER] does not have POSIX attributes. Please use -a if you wish to add them."
               exit
            fi

            OUT_TMP=/tmp/$$.otmp

            # Dump the user's LDAP object into a temp file
            $LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | sed ':a;N;$!ba;s/\n //g' > $OUT_TMP

            # Set the distingushed name for the user object
            #TU_DN=$($LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | sed ':a;N;$!ba;s/\n //g' | grep ^dn: | sed 's/^dn: //g') 
            TU_DN=$(grep ^dn: $OUT_TMP | sed 's/^dn: //g') 

            # Get existing attributes for user (it would be more efficient to 
            eUIDNUMBER=$(grep -i ^uidNumber: $OUT_TMP | sed 's/^uidNumber: //gi') 
            eGIDNUMBER=$(grep -i ^gidNumber: $OUT_TMP | sed 's/^gidNumber: //gi') 
            ePGROUPNAME=$($LDAPSEARCH -Q "(&(objectclass=group)(gidnumber=$eGIDNUMBER))" msSFU30Name | sed ':a;N;$!ba;s/\n //g' | grep '^msSFU30Name:' | sed 's/^msSFU30Name: //gi')
            eHOME=$(grep -i ^unixHomeDirectory: $OUT_TMP | sed 's/^unixHomeDirectory: //gi') 
            eSHELL=$(grep -i ^loginShell: $OUT_TMP | sed 's/^loginShell: //gi') 
            eDESC=$(grep -i ^description: $OUT_TMP | sed 's/^description: //gi') 

            if [[ -f $OUT_TMP ]]; then /bin/rm $OUT_TMP; fi
            
            # Display the current user attributes
            echo "The current attributes for user [$TARGETUSER]: "
            echo ""
            echo " Description (not changable): $eDESC"
            echo "Numeric UID (not changeable): $eUIDNUMBER"
            echo "         Numeric primary GID: $eGIDNUMBER ($ePGROUPNAME)"
            echo "              Home Directory: $eHOME"
            echo "                       Shell: $eSHELL"
            echo ""

            ## PRIMARY GROUP

            # Get a list of valid POSIX gidNumbers
            GIDLIST=$($LDAPSEARCH -Q '(&(objectClass=group)(gidnumber=*))' gidNumber | egrep "^gidNumber:" | egrep -v '10000|10004' | awk '{print $2}' | sort -un )

            if [[ -n $PRIMARYGID ]]; then
               SETGIDNUMBER=$PRIMARYGID
            else
               echo "This is a list of available primary groups: "
               $LDAPSEARCH -Q '(&(objectClass=group)(gidnumber=*))' cn gidNumber | egrep '^cn:|^gidNumber:' | sed ':a;N;$!ba;s/\n//g;s/cn:/\n/g;s/gidNumber: / /g' | egrep -v 'Domain Admins|LinuxLoginUsers' | awk '{print $2,$1}' | sed 's/^/   /g'
               echo ""
               read -p "Primary numeric GID [$eGIDNUMBER]: " GPGID

               if [[ -z $GPGID ]]; then
                  SETGIDNUMBER=$eGIDNUMBER
               else
                  SETGIDNUMBER=$GPGID
               fi
               
            fi

            VALIDGID=NO
            for GID in $GIDLIST; do
               if [[ "$GID" == "$SETGIDNUMBER" ]]; then
                  VALIDGID=YES
               fi
            done

            if [[ "$VALIDGID" != "YES" ]]; then
               echo "Error: Invalid GID [$SETGIDNUMBER]."
               exit
            fi

            ## HOME

            if [[ -n $GHOME ]]; then
               SETHOME=$GHOME
            else
               read -p "Home Directory [$eHOME]: " GHOME
               if [[ -z $GHOME ]]; then
                  SETHOME=$eHOME
               else
                  SETHOME=$GHOME
               fi
            fi

            ## SHELL
            
            if [[ -n $GSHELL ]]; then
               SETSHELL=$GSHELL
            else
               read -p "Shell [$eSHELL]: " GSHELL
               if [[ -z $GSHELL ]]; then
                  SETSHELL=$eSHELL
               else
                  if [[ -n `echo $GSHELL | egrep '^/bin/bash$|^/bin/ksh$|^/bin/csh$|^/bin/sh$|^/bin/false$|^/sbin/nologin$'` ]]; then
                     SETSHELL=$GSHELL
                  else
                     echo "Provided home directory [$GSHELL] is not valid, defaulting to /bin/bash."
                     SETSHELL=/bin/bash
                  fi
               fi
            fi
            

            # Build the LDIF
            LDIF_TMP=/tmp/$$.ldt

            echo "dn: $TU_DN" > $LDIF_TMP
            echo "changetype: modify" >> $LDIF_TMP
            echo "replace: gidNumber" >> $LDIF_TMP
            echo "gidNumber: $SETGIDNUMBER" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: unixHomeDirectory" >> $LDIF_TMP
            echo "unixHomeDirectory: $SETHOME" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP
            echo "replace: loginShell" >> $LDIF_TMP
            echo "loginShell: $SETSHELL" >> $LDIF_TMP
            echo "-" >> $LDIF_TMP

            # Modify the user
            $LDAPMODIFY -Q -a -f $LDIF_TMP
            ERROR=$?

            if [[ $ERROR -ne 0 ]]; then
               echo "Error: user [$TARGETUSER] not updated successfully."
               echo "The LDIF file is at [$LDIF_TMP]."
               exit
            else
               echo "[$TARGETUSER] has been updated."
               echo ""
               $LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | sed ':a;N;$!ba;s/\n //g' | egrep -i '^description:|^displayname:|^mssfu30nisdomain:|^mssfu30name:|^uid:|^uidnumber:|^gidnumber:|^unixhomedirectory:|^loginshell:' | sed 's/^/   /g'
               echo ""
               if [[ -f $LDIF_TMP ]]; then /bin/rm $LDIF_TMP; fi

               exit 0
            fi

            
            ;;
   REMOVE ) # Check to see if this account has POSIX attributes
            if [[ -z `$LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | egrep '^msSFU30NisDomain:|^msSFU30Name:|^uid:|^uidNumber:|^gidNumber:|^unixHomeDirectory:|^loginShell:'` ]]; then
               echo "[$TARGETUSER] does not have POSIX attributes. Nothing to do."
               exit 0
            fi

            OUT_TMP=/tmp/$$.otmp

            # Dump the user's LDAP object into a temp file
            $LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | sed ':a;N;$!ba;s/\n //g' > $OUT_TMP

            # Set the distingushed name for the user object
            #TU_DN=$($LDAPSEARCH -Q "(samaccountname=$TARGETUSER)" | sed ':a;N;$!ba;s/\n //g' | grep ^dn: | sed 's/^dn: //g')
            TU_DN=$(grep ^dn: $OUT_TMP | sed 's/^dn: //g')

            # Get existing attributes for user (it would be more efficient to
            eUIDNUMBER=$(grep -i ^uidNumber: $OUT_TMP | sed 's/^uidNumber: //gi')
            eGIDNUMBER=$(grep -i ^gidNumber: $OUT_TMP | sed 's/^gidNumber: //gi')
            ePGROUPNAME=$($LDAPSEARCH -Q "(&(objectclass=group)(gidnumber=$eGIDNUMBER))" msSFU30Name | sed ':a;N;$!ba;s/\n //g' | grep '^msSFU30Name:' | sed 's/^msSFU30Name: //gi')
            eHOME=$(grep -i ^unixHomeDirectory: $OUT_TMP | sed 's/^unixHomeDirectory: //gi')
            eSHELL=$(grep -i ^loginShell: $OUT_TMP | sed 's/^loginShell: //gi')
            eDESC=$(grep -i ^description: $OUT_TMP | sed 's/^description: //gi')

            if [[ -f $OUT_TMP ]]; then /bin/rm $OUT_TMP; fi

            # Display the current user attributes
            echo "The current attributes for user [$TARGETUSER]: "
            echo ""
            echo "        Description: $eDESC"
            echo "        Numeric UID: $eUIDNUMBER"
            echo "Numeric primary GID: $eGIDNUMBER ($ePGROUPNAME)"
            echo "     Home Directory: $eHOME"
            echo "              Shell: $eSHELL"
            echo ""
            
            echo "Warning: Removal of POSIX attributes cannot be undone."
            read -p "Type 'C' to continue removing POSIX attributes: " CONFIRMREMOVE
            
            if [[ "$CONFIRMREMOVE" != "C" ]]; then
               echo "Action cancelled by user."
               exit 0
            else

               # Build the LDIF
               LDIF_TMP=/tmp/$$.ldt
   
               echo "dn: $TU_DN" > $LDIF_TMP
               echo "changetype: modify" >> $LDIF_TMP
               echo "delete: msSFU30NisDomain" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: msSFU30Name" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: uid" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: uidNumber" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: gidNumber" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: unixHomeDirectory" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
               echo "delete: loginShell" >> $LDIF_TMP
               echo "-" >> $LDIF_TMP
   
               # Modify the user
               $LDAPMODIFY -Q -a -f $LDIF_TMP
               ERROR=$?
   
               if [[ $ERROR -ne 0 ]]; then
                  echo "Error: user [$TARGETUSER] not updated successfully."
                  echo "The LDIF is located at [$LDIF_TMP]"
                  exit
               else
                  echo "[$TARGETUSER] has been updated."
                  if [[ -f $LDIF_TMP ]]; then /bin/rm $LDIF_TMP; fi
                  exit 0
               fi

               
            fi

            ;;
        * )
            ;;
esac


