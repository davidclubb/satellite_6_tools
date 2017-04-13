#!/bin/bash

# Converts automounts into permanent mounts 

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   exit 200
fi

#LOGFILE
LOGFILE="/var/log/`basename $0 | awk -F'.' '{print $1}'`.log"
echo "Log start for [$0] with arguments [$@]" >> $LOGFILE

MODE=READONLY

if [[ "$1" == "-X" ]]; then
   MODE=EXECUTE
   echo "Execute mode specified - mounts will be converted where possible." | tee -a $LOGFILE
fi


AUTOMASTER=/etc/auto.master

if [[ ! -s $AUTOMASTER ]]; then
   echo "Unable to locate [$AUTOMASTER]." | tee -a $LOGFILE
   echo "System probably doesn't use automount." | tee -a $LOGFILE
   exit 0
fi

TS=`date +%Y%m%d%H%M%S`

BACKOUT_SCRIPT="/root/mountconv_backout_${TS}.sh"

echo "Backout script being created as [$BACKOUT_SCRIPT]." | tee -a $LOGFILE

# Get a list of filesystems by type
# Surround filesystem types with a space
TYPEFILTER=" ext2 | ext3 | ext4 "

# Blacklisted filesystems [value cannot be empty, so always leave a placeholder]
BL="blacklist"

# Enumerate all filesystems which match type

FSSEARCHLIST=`egrep "$TYPEFILTER" /etc/mtab | egrep -v "$BL" | awk '{print $2}'`

#FSSEARCHLIST='/sapmnt /usr/sap /oracle'

# Place to store the list of links
LINKLIST=/tmp/linklist
NOCONVLIST=/tmp/noconvlist
MULTILINKLIST=/tmp/multilinks

if [[ -s $NOCONVLIST ]]; then
   /bin/rm $NOCONVLIST
fi

if [[ -s $MULTILINKLIST ]]; then
   /bin/rm $MULTILINKLIST
fi


if [[ -s $LINKLIST ]]; then 
   echo "Found existing [$LINKLIST] - using that to save time" | tee -a $LOGFILE
   echo "If you want to regenerate the list delete [$LINKLIST]" | tee -a $LOGFILE
   echo "and run the script again." | tee -a $LOGFILE
   echo ""
else

   # Generate a list of symlinks for each filesystem in the search list
   echo "Generating a list of symbolic links, this may take some time." | tee -a $LOGFILE

   for FS in $FSSEARCHLIST; do
      echo "   Scanning [$FS] for symbolic links" | tee -a $LOGFILE
      find $FS -xdev -type l -exec file {} \; >> $LINKLIST
   done
fi

## Generate a list of all possible auto mounts

# Get a list of automount directoires
AUTOMPARENTS=`egrep '^/' $AUTOMASTER | egrep -v '\-hosts' | awk '{print $1}'`

# Generate a list of automount mount points
for AMP in $AUTOMPARENTS; do
   
   # Get the config file for each parent directory
   AMPC=`grep "^$AMP" $AUTOMASTER | awk '{print $2}'`
   echo "Configuration for [$AMP] is [$AMPC]" | tee -a $LOGFILE

   # Get all of the mount points described in the configuration file for this directory
   for AMS in `egrep -v '^$|^#' $AMPC | sort -u | awk '{print $1}'`; do

      # Generate the full mount path for this share
      FMP="${AMP}/${AMS}"
      echo "   Constructed share [$FMP]" | tee -a $LOGFILE

      # Get mount name/address
      SHARE=`grep "^${AMS}[[:space:]]" $AMPC | awk '{print $3}' | sed 's/^://'`
      echo "      Share: [$SHARE]" | tee -a $LOGFILE

      # Get share details
      STYPE=`grep "^${AMS}[[:space:]]" $AMPC | awk '{print $2}' | awk -F',' '{print $1}' | awk -F'=' '{print $2}'`
      if [[ -z $STYPE ]] && [[ -n `echo $SHARE | grep ':'` ]]; then
         STYPE=nfs
      fi
      echo "      Type: [$STYPE]" | tee -a $LOGFILE

      if [[ -n `echo $STYPE | grep "nfs"` ]]; then
         SERVER=`echo $SHARE | awk -F':' '{print $1}'`
      elif [[ $STYPE == cifs ]]; then
         SERVER=`echo $SHARE | awk -F'/' '{print $3}'`
      fi

      echo "      Server: [$SERVER]" | tee -a $LOGFILE
      
      # Get mount options
      MOPTS=`grep "^${AMS}[[:space:]]" $AMPC | awk '{print $2}' | cut -d',' -f 2- | sed 's/auto//g;s/^,//;s/,,/,/g'`
      if [[ -z $MOPTS ]]; then
         MOPTS=defaults
      fi
      echo "      Options: [$MOPTS]" | tee -a $LOGFILE
      

      # Check to see if this mount point is linked anywhere
      SCRIPTCONV=TRUE
      LINKCOUNT=`grep "\\\`${FMP}'$" $LINKLIST | wc -l`
      case $LINKCOUNT in
         0 ) echo "      NO LINKS FOUND FOR MOUNT" | tee -a $LOGFILE
             echo "$FMP" >> $NOCONVLIST
             SCRIPTCONV=FALSE
             ;;
         1 ) LINK=`grep "\\\`${FMP}'$" $LINKLIST | awk -F':' '{print $1}'`
             echo "      Symlink: [$LINK]" | tee -a $LOGFILE
             ;;
         * ) echo "      MULTIPLE LINKS FOUND, DECIDE MANUALLY" | tee -a $LOGFILE
             echo "      $FMP" >> $LOGFILE
             echo "$FMP" >> $MULTILINKLIST
             grep "\\\`${FMP}'$" $LINKLIST | sed 's/^         //g' >> $MULTILINKLIST
             SCRIPTCONV=FALSE
             ;;
      esac

      # If we found a symlink for the mount then it can safely be converted
      if [[ $SCRIPTCONV == TRUE ]] && [[ $MODE == EXECUTE ]]; then
     
         # Start writing the backout script if it doesn't already exist
         if [[ ! -s $BACKOUT_SCRIPT ]]; then
            echo '#!/bin/bash ' > $BACKOUT_SCRIPT
            echo "# Backout script generaged by `$0` `date`" >> $BACKOUT_SCRIPT
            echo "TS=\`date +%Y%m%d%H%M%S\`" >> $BACKOUT_SCRIPT
         fi
         
         # Create a backup of the automount profile for this session if it doesn't already exist 
         if [[ ! -s ${AMPC}.backup.${TS} ]]; then

            # Create backup 
            /bin/cp -rp $AMPC ${AMPC}.backup.${TS}

            # Create separate backups for undo action
            echo "/bin/cp -rp $AMPC ${AMPC}.backup.\${TS}" >> $BACKOUT_SCRIPT

            # Validate backup
            if [[ ! -s ${AMPC}.backup.${TS} ]]; then
               echo "ERROR: unable to create backup file [${AMPC}.backup.${TS}], aborting." | tee -a $LOGFILE
               exit 1
            fi
         fi
         # Create a backup of the fstab for this session if it doesn't already exist
         if [[ ! -s /etc/fstab.backup.${TS} ]]; then
            echo "/bin/cp -rp /etc/fstab /etc/fstab.backup.\${TS}" >> $BACKOUT_SCRIPT
            /bin/cp -rp /etc/fstab /etc/fstab.backup.${TS}
            if [[ ! -s /etc/fstab.backup.${TS} ]]; then
               echo "ERROR: unable to create backup file [/etc/fstab.backup.${TS}], aborting." | tee -a $LOGFILE
               exit 2
            fi
            echo "" >> /etc/fstab
            echo "# The mounts below were migrated from automounts" >> /etc/fstab
            echo "# Added by $0 at $TS" >> /etc/fstab
         fi
         
         echo "   Beginning conversion of [$FMP]" | tee -a $LOGFILE

         # Create an undo action
         echo "fuser -km $LINK; umount -f $LINK" >> $BACKOUT_SCRIPT
         echo "RCODE=\$?; if [[ \"\$RCODE\" != \"0\" ]]; then echo \"Failure: $LINK appears to be busy.\"; exit \$RCODE; fi" >> $BACKOUT_SCRIPT

         #set -x
         # Attempt to unmount the automount share if it's mounted
         WAIT=3
         MAXTRIES=20
         TRIES=0
         while [[ -n `mount | grep "[[:space:]]${FMP}[[:space:]]"` ]] && [[ $TRIES -le $MAXTRIES ]]; do
            let TRIES=$TRIES+1
            echo "      Attempting to unmount [$FMP]..." | tee -a $LOGFILE
            echo "      Attempt #$TRIES" >> $LOGFILE
            umount $FMP
            if [[ -n `mount | grep "[[:space:]]${FMP}[[:space:]]"` ]]; then
               if [[ $TRIES -le $MAXTRIES ]]; then
                  echo "      [$FMP] is still mounted, waiting $WAIT seconds to try again..."  | tee -a $LOGFILE
               else
                  echo "      Error, maximum retries [$MAXTRIES] to unmount [$FMP]." | tee -a $LOGFILE
                  echo "      Please address this manually and re-run the script." | tee -a $LOGFILE
                  exit 4
               fi
               sleep $WAIT
            fi    
        
         done

         # Comment the share out of the automount map
         echo "      Removing [$AMS] from [$AMPC]" | tee -a $LOGFILE
         sed -i "/^${AMS}[[:space:]]/s/^/#/g" $AMPC

         # Create an undo action
         echo "sed -i \"/^#${AMS}[[:space:]]/s/^#//g\" $AMPC" >> $BACKOUT_SCRIPT

         # Remove the symbolic link
         if [[ -L $LINK ]]; then
            echo "      Removing symbolic link [$LINK]" | tee -a $LOGFILE
            
            # Create an undo action
            echo "if [[ ! -L $LINK ]] && [[ -d $LINK ]]; then" >> $BACKOUT_SCRIPT
            echo "rmdir $LINK" >> $BACKOUT_SCRIPT
            echo "fi" >> $BACKOUT_SCRIPT
            echo "ln -s $FMP $LINK" >> $BACKOUT_SCRIPT
            stat -c "chown -h %U:%G" $LINK >> $BACKOUT_SCRIPT

            # Remove the link
            /bin/rm $LINK

            # Make sure the link was removed
            if [[ -L $LINK ]]; then
               echo "      Error removing symbolic link [$LINK]" | tee -a $LOGFILE
               exit 3
            fi
         fi

         # Create a mount point in place of the symlink
         echo "      Creating mount point [$LINK]" | tee -a $LOGFILE
         mkdir -p $LINK

         if [[ ! -d $LINK ]]; then
            echo "      Error creating directory [$LINK]" | tee -a $LOGFILE
            exit 5
         fi

         # Check the server to see if it's still valid and responding
         SERVERSTATUS=GOOD
         if [[ -z `getent hosts $SERVER` ]]; then
            echo "      Warning: Server [$SERVER] can't be resolved to an IP address" | tee -a $LOGFILE
            SERVERSTATUS=BAD
         else
            if [[ $STYPE == cifs ]] && [[ -z `nmap -P0 $SERVER -p 445 | grep "^445" | grep open` ]]; then
               echo "      Warning: Server [$SERVER] doesn't appear to be listening for cifs connections." | tee -a $LOGFILE
               SERVERSTATUS=BAD
            fi
            if [[ -n `echo $STYPE | grep "nfs"` ]] && [[ -z `nmap -P0 $SERVER -p 2049 | grep "^2049" | grep open` ]]; then
               echo "      Warning: Server [$SERVER] doesn't appear to be listening for nfs connections." | tee -a $LOGFILE
               SERVERSTATUS=BAD
            fi
         fi

         # Create the appropriate entry in fstab
         if [[ $SERVERSTATUS == GOOD ]]; then
            echo "      Creating fstab entry for [$LINK]" | tee -a $LOGFILE
            echo "$SHARE $LINK $STYPE $MOPTS 0 0" >> /etc/fstab

            # create an undo action
            echo "sed -i \"/^${SHARE}[[:space:]]/s/^/#/g\" /etc/fstab" >> $BACKOUT_SCRIPT
            echo "" >> $BACKOUT_SCRIPT
         
            # Attempt to mount the newly converted share
            echo "      Attempting to mount [$LINK]" | tee -a $LOGFILE
            mount $LINK

            if [[ -z `mount | grep "[[:space:]]${LINK}[[:space:]]"` ]]; then
               echo "      Error mounting [$LINK]." | tee -a $LOGFILE
               exit 6
            else
               echo "      Successfully mounted [$LINK].  Conversion Complete." | tee -a $LOGFILE
            fi
         else
            echo "      Since the server [$SERVER] isn't available" | tee -a $LOGFILE
            echo "      an fstab entry for [$LINK]" | tee -a $LOGFILE
            echo "      will be created but it will be commented" | tee -a $LOGFILE
            echo "      out and no attempt will be made to mount it" | tee -a $LOGFILE
            echo "#$SHARE $LINK $STYPE $MOPTS 0 0" >> /etc/fstab
            echo "      Conversion of [$LINK] complete." | tee -a $LOGFILE
         fi

      else
         echo "Running in Read-Only mode, use -X to actually convert mounts."  | tee -a $LOGFILE   
      fi

      echo ""
      echo ""

   done


done

if [[ -s $NOCONVLIST ]]; then
   echo ""
   echo ""
   echo "The Following Automounts could not be converted:" | tee -a $LOGFILE
   echo ""
   cat $NOCONVLIST | sed 's/^/   /g' | tee -a $LOGFILE
   echo ""
   echo "The script could not find any symlinks for them on local filesystems." | tee -a $LOGFILE
fi

if [[ -s $MULTILINKLIST ]]; then
   echo "The following were not converted because they're" | tee -a $LOGFILE
   echo "directly symlinked from multiple locations:" | tee -a $LOGFILE
   echo ""
   cat $MULTILINKLIST | sed 's/^/   /g' | tee -a $LOGFILE
   echo ""
   echo "Please convert manually." | tee -a $LOGFILE

fi

