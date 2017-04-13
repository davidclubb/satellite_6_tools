#!/bin/bash

# Converts all files owned by a numeric UID or GID to be owned by another numeric UID or GID


if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   exit 200
fi


f_Usage() {

echo "Switch numeric ID for objects on local file systems"
echo ""
echo "Usage: $0 <Mode> <OldNID> <NewNID>"
echo ""
echo "WHERE:"
echo ""
echo "   <Mode>      Is either U for 'user' or G for 'group'"
echo "   <OldNID>    Is the numeric UID or GID we're changing FROM."
echo "   <NewNID>    Is the numeric UID or GID that 'OldNID' should be changed to."
echo ""


}

LOGTEMP=/tmp/flist
LOGFILE=/var/log/switchnid.log
CHGTEMP=/tmp/changelist
TS=`date +%Y%m%d%H%M%S`

if [[ -f $CHGTEMP ]]; then
   /bin/rm $CHGTEMP
fi

if [[ ! -f $LOGFILE ]]; then
   touch $LOGFILE
fi

echo "Script started at [`date`] by [$USER] with arguments [$@]" >> $LOGFILE

GMODE=$1

GOLDID=$2

GNEWID=$3

# Verify correct argument count
if [[ $# -lt 3 ]]; then
   echo "Invalid argument count." | tee -a $LOGFILE
   f_Usage
   exit 1
fi

# Verify mode is valid
case $GMODE in

   U ) MODE=U
       MODESTRING1="UID"
       MODESTRING2="user"
       MAPNAME="passwd"
       FINDSTRING="-user"
       NIDCHANGE="/usr/sbin/usermod -u"
       CHANGEBIN=chown
       ;;
   G ) MODE=G
       MODESTRING1="GID"
       MODESTRING2="group"
       MAPNAME="group"
       FINDSTRING="-group"
       NIDCHANGE="/usr/sbin/groupmod -g"
       CHANGEBIN=chgrp
       ;;
   * ) echo "Error: [$GMODE] is not a valid mode." | tee -a $LOGFILE
       f_Usage
       exit 2
       ;;
esac

# Verify OldNID 
if [[ -z `echo $GOLDID | egrep "^[0-9]+$"` ]] || [[ -z `echo $GNEWID | egrep "^[0-9]+$"` ]]; then
   echo "${MODESTRING1}s must be numeric" | tee -a $LOGFILE
   f_Usage
   exit 3
fi

# Check to see if the old  numeric ID maps to something the system can see
IDMAPPED=NO

ONIDNAME=`getent $MAPNAME $GOLDID | awk -F':' '{print $1}'`

if [[ -n $ONIDNAME ]]; then
   IDMAPPED=YES
else
   echo "Warning: the $MODESTRING1 [$GOLDID] does not map to a $MODESTRING2 name." | tee -a $LOGFILE
   read -p "Enter Y to continue anyway, anything else to quit: " WARN1
   if [[ -z `echo $WARN1 | egrep -i '^Y|^y'` ]]; then
      echo "Quitting.  No changes have been made." | tee -a $LOGFILE
      exit
   fi
fi

# Check to see if the new numeric ID maps to something
NNIDNAME=`getent $MAPNAME $GNEWID | awk -F':' '{print $1}'`
if [[ -n $NNIDNAME ]]; then
   echo "Warning: the 'new' $MODESTRING1 is already mapped to a $MODESTRING2 name." | tee -a $LOGFILE
   echo "If you proceed with moving ownership it will be impossible to distinguish"
   echo "between files owned by [$NNIDNAME] prior to the ownership change."
   read -p "Enter Y to continue anyway, anything else to quit: " WARN2
   if [[ -z `echo $WARN2 | egrep -i '^Y|^y'` ]]; then
      echo "Quitting.  No changes have been made." | tee -a $LOGFILE
      exit
   fi
fi

# Check to see if the user we're trying to change is logged in
if [[ "$MODE" == "U" ]]; then
   if [[ -n `pgrep -u $GOLDID` ]]; then
      echo "The UID $GOLDID is currently active.  All processes under this UID"
      echo "should be stopped before continuing?  Do you want the script to "
      echo "attempt to kill off anything using this UID?"
      read -p "Enter Y to attempt to kill off running processes, anything else to quit: " WARN3
      if [[ -z `echo $WARN3 | egrep -i '^Y|^y'` ]]; then
         echo "Quitting.  No processes have been killed, no changes have been made." | tee -a $LOGFILE
      else
         pkill -9 -u $GOLDID
         sleep 3
         if [[ -n `pgrep -u $GOLDID` ]]; then
            echo "Attempts to shut down processes running as UID [$GOLDID] were unsuccessful."
            echo "Please close these processes down manually and try again."
            exit 10
         fi
      fi
   fi
      
fi

# Get a list of filesystems by type
# Surround filesystem types with a space
TYPEFILTER=" ext2 | ext3 | ext4 "

# Blacklisted filesystems [value cannot be empty, so always leave a placeholder]
#BL="blacklist"
BL="/oracle|/usr/sap|/sapmnt"

# Enumerate all filesystems which match type

FSLIST=`egrep "$TYPEFILTER" /etc/mtab | egrep -v "$BL" | awk '{print $2}'`

#Confirm
echo "About to change all files and directories owned by $MODESTRING1 $GOLDID [$ONIDNAME] to $MODESTRING1 $GNEWID" | tee -a $LOGFILE
echo "on the following filesystems:" | tee -a $LOGFILE
for FS in $FSLIST; do
   echo "   $FS" | tee -a $LOGFILE
done
echo ""
read -p "Press Enter to confirm: " JUNK


for FS in $FSLIST; do

   echo "Enumerating directories owned by $GOLDID [$ONIDNAME] on [$FS]" | tee -a $LOGFILE
   find $FS -xdev -type d $FINDSTRING $GOLDID > $LOGTEMP
   ELEMCOUNT=`cat $LOGTEMP | wc -l`
   if [[ "$ELEMCOUNT" != "0" ]]; then
      echo "   Found $ELEMCOUNT directories."
      cat $LOGTEMP | sed 's/^/\t/g' >> $LOGFILE
      cat $LOGTEMP >> $CHGTEMP
      
   fi


   echo "Enumerating files owned by $GOLDID [$ONIDNAME] on [$FS]" | tee -a $LOGFILE
   find $FS -xdev -type f $FINDSTRING $GOLDID > $LOGTEMP
   ELEMCOUNT=`cat $LOGTEMP | wc -l`
   if [[ "$ELEMCOUNT" != "0" ]]; then
      echo "   Found $ELEMCOUNT files."
      cat $LOGTEMP | sed 's/^/\t/g' >> $LOGFILE
      cat $LOGTEMP >> $CHGTEMP
   fi
   echo ""

done

echo "Constructing backout script..." | tee -a $LOGFILE
BACKOUTSCRIPT=/root/switchnid_undo_$TS.sh
TOUCHCOUNT=`cat $CHGTEMP | wc -l`
echo "#!/bin/bash" > $BACKOUTSCRIPT
echo "# Backout script generated by $0 `date`" >> $BACKOUTSCRIPT
echo "# Backout of the job created by [$0 $@]" >> $BACKOUTSCRIPT
sed "s/^/$CHANGEBIN $GOLDID '/g;s/$/'/g" $CHGTEMP >> $BACKOUTSCRIPT
echo ""
let BLINECOUNT=$TOUCHCOUNT+3
if [[ `cat $BACKOUTSCRIPT | wc -l` -lt $BLINECOUNT ]]; then
   echo "Error, the backup script should have $BLINECOUNT lines, but has `cat $BACKOUTSCRIPT | wc -l`" | tee -a $LOGFILE
   exit 9
fi

echo "Backout script created as [$BACKOUTSCRIPT]" | tee -a $LOGFILE


echo "Modifying $TOUCHCOUNT files and directories, please wait..."
COUNT=0

while read line; do
   f=$line
   let COUNT=$COUNT+1
   echo "[${COUNT}/${TOUCHCOUNT}] $f"
   $CHANGEBIN $GNEWID "$f" 2>&1 | tee -a $LOGFILE
   tput cuu1;tput el

done < $CHGTEMP

#for f in `cat $CHGTEMP`; do
#   let COUNT=$COUNT+1
#   echo "[${COUNT}/${TOUCHCOUNT}] $f"
#   $CHANGEBIN $GNEWID "$f" 2>&1 | tee -a $LOGFILE
#   tput cuu1;tput el
#done

# Finally attempt to change the local user or group's numeric ID
if [[ -n $ONIDNAME ]] && [[ -z $NNIDNAME ]]; then
   echo "Changing the $MODESTRING2 account ${ONIDNAME}'s $MODESTRING1 from [$GOLDID] to [$GNEWID]" | tee -a $LOGFILE
   #echo "$NIDCHANGE $GNEWNID $ONIDNAME"
   cp -rp /etc/${MAPNAME} /etc/${MAPNAME}.${TS}
   $NIDCHANGE $GNEWID $ONIDNAME 2>&1 | tee -a $LOGFILE

   # If this is a group change, make sure we update the primary ID of any users with this group as primary GID
   if [[ "$MODE" == "G" ]]; then
      IDPRIMS=`getent passwd | awk -v OGID=$GOLDID -F':' '( $4 == OGID ) {print $1}'`
      if [[ -n $IDPRIMS ]]; then
         echo "Changing GID for user accounts with this group as primary"
         for IDPRIM in $IDPRIMS; do
            echo "Chaging ${IDPRIM}'s primary GID to [$GNEWID]" | tee -a $LOGFILE
            usermod -g $GNEWID $IDPRIM 2>&1 | tee -a $LOGFILE
         done
      fi
   fi
   
else
   if [[ -z $ONIDNAME ]]; then
      echo "Notice: unable to switch the $MODESTRING1 for a $MODESTRING2 because $GOLDID does not map to one."
      echo "   Consider creating a $MODESTRING2 with $MODESTING1 $GNEWID"
   fi
   if [[ -n $NNIDNAME ]]; then
      echo "Notice: $MODESTRING2 [$NNIDNAME] is now the owner of everthing that used to be $MODESTRING1 [$GOLDID]"
      if [[ -n $ONIDNAME ]]; then
         echo "   You may want to consider removing or disabling [$ONIDNAME] as it no longer owns any files."
      fi
   fi

fi
 


