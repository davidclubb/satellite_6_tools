#!/bin/bash

SID=$1

echo "SID received is $SID"
if [[ -z $SID ]]; then
   echo "Error: SID is required"
   exit 4
fi

# Make sure the post_scripts directory is mounted

if [[ ! -d /opt/sa ]]; then
   echo "Directory /opt/sa not present - creating it"
   /bin/mkdir -p /opt/sa
fi

if [[ -z `/bin/grep '/opt/sa' /etc/mtab` ]]; then
   echo "Mounting /opt/sa"
   mount -o ro,nolock 10.251.14.36:/opt_sa /opt/sa
fi

UIDMAP=/opt/sa/lists/SAP/user-uidlist.csv
GIDMAP=/opt/sa/lists/SAP/group-gidlist.csv

if [[ ! -s $UIDMAP ]]; then
   echo "FAILURE: Unable to read UIDMAP [$UIDMAP]"
fi

if [[ ! -s $GIDMAP ]]; then
   echo "FAILURE: Unable to read GIDMAP [$GIDMAP]"
fi

# Local Group List
GROUPADDLIST="dba sapinst sapsys oper oinstall"


if [[ -n $SID ]]; then
   # Local User List
   SIDADM=`echo $SID | /bin/awk '{print tolower($0)"adm"}'`
   ORASID=`echo $SID | /bin/awk '{print "ora"tolower($0)}'`
   USERADDLIST="sapadm daaadm $SIDADM $ORASID"
fi

# Add groups
for G in $GROUPADDLIST; do
   GIDNUMBER=`/bin/grep "^${G}," $GIDMAP | /bin/awk -F',' '{print $2}'`
   if [[ -z $GIDNUMBER ]]; then
      echo "FAILURE: Unable to determine GID for $G"
   else
      
      # Check to see if another group is squatting on the GID we want to use
      CAMPER=`getent group $GIDNUMBER | awk -F':' '{print $1}'`
      if [[ -n $CAMPER ]] && [[ "$CAMPER" != "$G" ]]; then
         CAMPER=`getent group $GIDNUMBER | awk -F':' '{print $1}'`
         echo "[$CAMPER] appears to be squatting on GID [$GIDNUMBER] moving it to GID [5${GIDNUMBER}]"
         groupmod -g "5${GIDNUMBER}" $CAMPER
      fi
      if [[ -z `grep "^${G}:" /etc/group` ]]; then
         echo "Adding group $G with GID $GIDNUMBER"
         /usr/sbin/groupadd -g $GIDNUMBER $G
      else
         echo "Group $G already exists."
         EGIDNUMBER=`getent group $G | awk -F':' '{print $3}'`
         if [[ "$EGIDNUMBER" != "$GIDNUMBER" ]]; then
            echo "$G is [$EGIDNUMBER]"
            echo "$G should be [$GIDNUMBER]"
            # If the numbers don't match, fix it and all of the files
            echo "Resetting $G to use GID [$GIDNUMBER]"
            for d in `df -l | grep "^[[:space:]]" | awk '{print $NF}'`; do
               find $d -xdev -type f -group $EGIDNUMBER -exec chgrp $GIDNUMBER {} \;
               find $d -xdev -type d -group $EGIDNUMBER -exec chgrp $GIDNUMBER {} \;
               find $d -xdev -type l -group $EGIDNUMBER -exec chgrp $GIDNUMBER {} \;
            done
            groupmod -g $GIDNUMBER $G
         fi
      fi
   fi
done


# Add users
for U in $USERADDLIST; do

   # Set Attributes for the Oracle account
   if [[ -n `echo $U | grep "ora"` ]]; then

      U=oracle
      UIDNUMBER=500
      DESC="SAP Oracle Service Account"
      PG=oinstall
      SG=oper,sapinst,dba
      HD=/usr/local/home/${U}
      SHELL=/bin/bash


   # Set Attributes for the SAP App accounts
   else

      # Get the pre-set UID from the UIDMAP
      UIDNUMBER=`/bin/grep "^${U}," $UIDMAP | /bin/awk -F',' '{print $2}'`

      if [[ -z $UIDNUMBER ]]; then
         echo "FAILURE: Unable to determine UID for $U"
      else
         DESC="SAP Application Service Account"
         PG=sapsys
         SG=oper,sapinst,dba,oinstall
         HD=/usr/local/home/$U
         SHELL=/bin/ksh
      fi
   fi

   # Check to see if any other usernames are squatting on the UID we want to use 
   CAMPER=`getent passwd $UIDNUMBER | awk -F':' '{print $1}'`
   if [[ -n $CAMPER ]] && [[ "$CAMPER" != "$U" ]]; then
      CAMPER=`getent passwd $UIDNUMBER | awk -F':' '{print $1}'`
      echo "[$CAMPER] appears to be squatting on UID [$UIDNUMBER] moving it to UID [5${UIDNUMBER}]"
      pkill -9 -u $UIDNUMBER 
      usermod -u "5${UIDNUMBER}" $CAMPER
   fi


   if [[ -z `grep "^${U}:" /etc/passwd` ]]; then
      echo "Adding user $U with UID $UIDNUMBER"
      /usr/sbin/useradd -u $UIDNUMBER -g $PG -G $SG -c "$DESC" -d $HD -s $SHELL $U
   else
      echo "User $U already exists."
      EUIDNUMBER=`getent passwd $U | awk -F':' '{print $3}'`
      if [[ "$EUIDNUMBER" != "$UIDNUMBER" ]]; then
         echo "$U is $EUIDNUMBER"
         echo "$U should be $UIDNUMBER"
         # If the numbers don't match, fix it and all of the files
         echo "Resetting $U to use UID [$UIDNUMBER]"
         for d in `df -l | grep "^[[:space:]]" | awk '{print $NF}'`; do
            find $d -xdev -type f -user $EUIDNUMBER -exec chown $UIDNUMBER {} \;
            find $d -xdev -type d -user $EUIDNUMBER -exec chown $UIDNUMBER {} \;
            find $d -xdev -type l -user $EUIDNUMBER -exec chown $UIDNUMBER {} \;
         done
         pkill -9 -u $UIDNUMBER
         pkill -9 -u $U
         usermod -u $UIDNUMBER -g $PG $U
      fi
   fi

done

# Set the password for sapadm
SET_HASH='redacted'
/usr/sbin/usermod -p $SET_HASH sapadm

