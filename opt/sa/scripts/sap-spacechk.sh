#!/bin/bash


# Calculates disk usage on common SAP volumes to suggest sizing of disks on replacement servers
# Also calculates resizing needed to switch to standardized partition layout.

# The script assumes that newly built SAP server will initially be created with 3 "Physical" disks
# Disk 1 = OS
# Disk 2 = SAP App (and CI)
# Disk 3 = SAP Database

f_isThisAMount(){

   M=$1

   if [[ -n `cat /etc/mtab | grep -v "[[:space:]]nfs[[:space:]]" | awk '{print $2}' | grep "^${M}$"` ]]; then
      echo "TRUE"
   else
      echo "FALSE"
   fi
}


# Zero out the totals for Disk 2
TOTALDISK2=0
USEDDISK2=0
echo "# For disk 2:"
echo "########################"

# Enumerate known SAP volumes
for f in /sapmnt /usr/sap /usr/sap/interfaces /usr/sap/trans /opt/hvr; do
   # Only report on a volume if it is actually mounted - if it's simply a subdirectory of another filesystem it will be ignored.
   if [[ -n `cat /etc/mtab | grep -v "[[:space:]]nfs[[:space:]]" | awk '{print $2}' | grep "^${f}$"` ]]; then

      # Get sizes and disk usage in both K and user-friendly values
      SIZE=`df -h $f | tail -1 | awk '{print $1}'`
      USED=`df -h $f | tail -1 | awk '{print $2}'`
      SIZEK=`df -k $f | tail -1 | awk '{print $1}'`
      USEDK=`df -k $f | tail -1 | awk '{print $2}'`
      
      # Print the size and usage for the file system
      echo "$f,$SIZE,$USED"
      let TOTALDISK2=$TOTALDISK2+$SIZEK
      let USEDDISK2=$USEDDISK2+$USEDK
   fi
done
echo "########################"

# Print totals for Disk 2
TOTALGB=`echo "scale=1; $TOTALDISK2 / 1024 / 1024" | bc`
USEDGB=`echo "scale=1; $USEDDISK2 / 1024 / 1024" | bc`
echo "TOTAL Size for Disk 2: $TOTALGB"
echo "Actual Used Space for Disk 2: $USEDGB"
echo ""

# Zero out totals for disk 3
TOTALDISK3=0
USEDDISK3=0
echo "# For disk 3:"
echo "########################"

# Get the volume name for ORAARCH
ORAARCH=`awk '{print $2}' /etc/mtab | grep "oraarch$"`

# If ORAARCH exists then use it to determine the "ORASID" volume
if [[ -n $ORAARCH ]]; then ORASID=$(echo $ORAARCH | sed "s/\/`basename $ORAARCH`$//"); fi

# Get the volume name for ORIGLOGS
ORIGLOGS=`awk '{print $2}' /etc/mtab | grep "origlog"`

# Get the volume name for ORAFLASH
ORAFLASH=`awk '{print $2}' /etc/mtab | grep "oraflash"`

# Unqualified hostname
MHN=`hostname | awk -F'.' '{print $1}' | tr '[:upper:]' '[:lower:]'`

# Location of system definitions
SYSLIST=/basis/gold_profiles/GOLD_APPS_CONFIG

if [[ ! -s $SYSLIST ]]; then
   echo "Error: system list is unavailable at [$SYSLIST], aborting." | tee -a $LOGFILE 1>&2
   exit 250
fi


# Get SID
export SID=`egrep -e "[|,]${MHN}[|,]" $SYSLIST | awk -F'|' '{print $1}'`


# Figure out what's going on with SAPDATA

SAPDATA=`find /oracle/${SID} -maxdepth 1 | grep -i sapdata | sort`

# MAKE sure there's a SAPDATA Volume before we check it
#SAPDATA=`awk '{print $2}' /etc/mtab | grep "/sapdata"`

# Enumerate the volumes for Disk 3
for f in /oracle $ORASID $ORAARCH $ORIGLOGS $SAPDATA ; do
   if [[ -n `cat /etc/mtab | grep -v "[[:space:]]nfs[[:space:]]" | awk '{print $2}' | grep "^${f}$"` ]]; then
      SIZE=`df -h $f | tail -1 | awk '{print $1}'`
      USED=`df -h $f | tail -1 | awk '{print $2}'`
      SIZEK=`df -k $f | tail -1 | awk '{print $1}'`
      USEDK=`df -k $f | tail -1 | awk '{print $2}'`
      
      # Print the size and usage for the volume
      echo "$f,$SIZE,$USED"
      let TOTALDISK3=$TOTALDISK3+$SIZEK
      let USEDDISK3=$USEDDISK3+$USEDK

   else
      # This means what should be a mount point is actually defined as a directory
    
      USED=`du -sh $f | awk '{print $1}'`
      USEDK=`du -sk $f | awk '{print $1}'`
      echo "$f,$USED,$USED"


   fi
   
done
echo "########################"

# Print totals
TOTALGB=`echo "scale=1; $TOTALDISK3 / 1024 / 1024" | bc`
USEDGB=`echo "scale=1; $USEDDISK3 / 1024 / 1024" | bc`
if [[ "$TOTALGB" != "0" ]]; then
   echo "TOTAL Size for Disk 3: $TOTALGB"
   echo "Actual Used Space for Disk 3: $USEDGB"
else
   echo "Disk 3 not necessary."
fi
echo ""

# Generate a volume resizing plan based on the usage on this system and the 
# Standard volume layout and sizes


echo "Copy and paste these commands on the target machine to resize volumes:"

# Generate a list of all of the mounts on a "standard" SAP server and their default sizes in K


DIRLIST="
/usr/sap:20961280
/sapmnt:10475520
/usr/sap/interfaces:5232640
/usr/sap/trans:10475520
/oracle:10475520
/oracle/$SID:20961280
/oracle/$SID/oraarch:41922560
/oracle/$SID/oraflash:52403200
/oracle/$SID/origlogA:2086912
/oracle/$SID/origlogB:2086912
/oracle/$SID/mirrlogA:1038336
/oracle/$SID/mirrlogB:1038336
/oracle/$SID/sapdata1:10475520
/oracle/$SID/sapdata2:10475520
/oracle/$SID/sapdata3:10475520
/oracle/$SID/sapdata4:10475520
"

# Figure out what to do about /oracle 
ORASIDDIR=/oracle/${SID}
SAPDATA=`find /oracle/${SID} -maxdepth 1 | grep -i sapdata | sort`

# If oracle isn't it's own mount, all of the data is probably in ORASID
# We need to subtract everything in /oracle from ORASID
if [[ "`f_isThisAMount /oracle`" == "FALSE" ]]; then 


   TOTALK=`df -kP /oracle | grep /oracle | awk '{print $2}'`
   ORASIDK=`du -sk $ORASIDDIR | grep $ORASIDDIR awk '{print $1}'`

fi

# Are /oracle and /oracle/SID separate mounts?

`cat /etc/mtab | grep -v "[[:space:]]nfs[[:space:]]" | awk '{print $2}' | grep "^${f}$"`


# Add any SAPDATA that doesn't exist
DIRLIST="$DIRLIST `find /oracle/${SID} -maxdepth 1 | grep -i sapdata | sort | egrep -v "sapdata[1-4]"`"


# Process all of the disks
for D in $DIRLIST; do

   # Separate the line into the directory name and it's default size
   DIR=`echo $D | awk -F':' '{print $1}'`
   DEFSPACE=`echo $D | awk -F':' '{print $2}'`

   if [[ -z $DEFSPACE ]]; then DEFSPACE=0; fi

   # If the directory exists then process it - not all systems have all mounts/directories
   if [[ -d $DIR ]]; then

      # Clear the exclusion list
      unset EXCLIST

      # Look at every other volume in the list
      for D2 in $DIRLIST; do

         # Separate the volume name from the line
         DIR2=`echo $D2 | awk -F':' '{print $1}'`

         # If the mount name is not the same as the one we're presently looking at
         # AND it contains the name of the one we're presently looking at, it should
         # be excluded from the size calculation because it will be a separate mount
         # on the target system
         if [[ "$DIR" != "$DIR2" ]] && [[ -n `echo "$DIR2" | grep $DIR` ]]; then
            EXCLIST="$EXCLIST --exclude='${DIR2}/*'"
         fi
      done

      # Calculate actual space used (minus any space consumed by what will be a different filesystem)
      SPACEUSED=`echo "du -s $DIR $EXCLIST" | /bin/bash | awk '{print $1}'`
      #echo "Space used by [$DIR]: $SPACEUSED" 

      # If the space used by this mount is greater than the default space, the target volume will need to be resized
      if [[ $SPACEUSED -gt $DEFSPACE ]]; then

         # Calculate what it would take to ensure 20% Free space on the file system
         TWENTYP=`echo "$SPACEUSED * .25" | bc | awk -F'.' '{print $1}'`
         
         # If the 20% free space is more than 50GB, then go with 50 GB.
         if [[ $TWENTYP -le 52428800 ]]; then
            PADDING=$TWENTYP
         else
            PADDING=52428800
         fi

         PLUSPAD=`echo "$SPACEUSED + $PADDING" | bc`
     
         # Echo a line to the screen that can be copied and pasted to the target system
         echo "lvresize -r -f -L ${PLUSPAD}K \`grep '[[:space:]]$DIR[[:space:]]' /etc/mtab | awk '{print \$1}'\`"
      fi
      
   fi

done



