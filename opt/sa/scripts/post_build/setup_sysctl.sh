#!/bin/bash

# Incept 20150112
# Author SDW
# Configure a RHEL system's sysctl.conf

# USAGE:
#
# Provide key words as arguments - multiples are allowed
#
# example: setup_sysctl.sh SAP
#
# Running without arguments will result in a basic standard configuration

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         Setup has not been completed on this system."
   exit 2
fi


TS=`date +%Y%m%d%H%M%S`

LOGFILENAME=setup_sysctl.log
LOGDIR=/var/log/install
LOGFILE=${LOGDIR}/${LOGFILENAME}

### EVALUATE ARGUMENTS
SAP=FALSE
ORACLEDB=FALSE

# Start logging
if [[ ! -d "$LOGDIR" ]]; then mkdir -p "$LOGDIR"; fi
echo "[$0] started [`date`] with arguments [$@]" >> $LOGFILE

# Check for SAP
if [[ -n `echo $@ | /bin/egrep -i "^SAP$|^SAP | SAP$"` ]]; then
   echo "Setting \"SAP\" flag to TRUE based on arguments" >> $LOGFILE
   SAP=TRUE
   
   # Check to see if this SAP server is also a DB server and add oracle tunings
   # If the system has a third disk at build time then assume it's a database
   DLIST=`/usr/bin/lsscsi | /bin/awk '{if($2=="disk") print $NF}'`

   if [[ -n `echo $DLIST | /bin/awk '{print $3}'` ]]; then
      echo "Detected that this is an SAP database - setting \"ORACLEDB\" flag to true." >> $LOGFILE
      ORACLEDB=TRUE
   fi
fi

# Check for ORACLEDB
if [[ -n `echo $@ | /bin/egrep -i "^ORACLEDB$|^ORACLEDB | ORACLEDB$"` ]]; then
   echo "Setting \"ORACLEDB\" flag to TRUE based on arguments" >> $LOGFILE
   ORACLEDB=TRUE
fi

echo "Setting kernel parameters for..."
if [[ "$SAP" == "TRUE" ]]; then
   echo "   SAP"
fi
if [[ "$ORACLEDB" == "TRUE" ]]; then
   echo "   ORACLEDB"
fi
echo ""

### OS VERSION 
echo "Checking OS version..."
unset ELV
if [[ -n `uname -r | grep -i el6` ]] || [[ -s /etc/nslcd.conf ]]; then
   echo "   Setting version to RHEL 6/7"
   ELV=6
elif [[ -n `uname -r | grep -i el5` ]]; then
   echo "   Setting version to RHEL or OEL 5"
   ELV=5
fi

# Create a backup of the sysctl.conf file before making any changes
/bin/cp /etc/sysctl.conf /etc/sysctl.conf.backup.$TS

if [[ $ELV == 6 ]] && [[ $SAP == TRUE ]]; then

   PARAMLIST="kernel.msgmni kernel.sem vm.max_map_count"

   # clear any existing instances of the settings
   for PARAM in $PARAMLIST; do
      sed -i "/^${PARAM}*.=/d" /etc/sysctl.conf
   done
   #sed -i '/^kernel.msgmni*.=/d;/kernel.sem*.=/d;/vm.max_map_count*.=/d;/# SAP settings/d' /etc/sysctl.conf
   sed -i '/^# SAP settings/d' /etc/sysctl.conf
   
   # write new settings
   echo "" >> /etc/sysctl.conf
   echo "# SAP settings" >> /etc/sysctl.conf
   echo "kernel.msgmni=1024" >> /etc/sysctl.conf
   echo "kernel.sem=1250 256000 100 1024" >> /etc/sysctl.conf
   echo "vm.max_map_count=2000000" >> /etc/sysctl.conf
   echo "" >> /etc/sysctl.conf

fi

if [[ $ELV == 6 ]] && [[ $ORACLEDB == TRUE ]]; then

   PARAMLIST="kernel.shmall
              kernel.shmmax
              kernel.shmmni
              kernel.sem
              net.core.rmem_default
              net.core.rmem_max
              net.core.wmem_default
              net.ipv4.ip_local_port_range
              fs.file-max
              net.core.wmem_max
              fs.aio-max-nr
             "

   # Conflict parameters
   if [[ $SAP == TRUE ]]; then
      K_SEM="1250 256000 100 1024"
   else
      K_SEM="250 32000 100 128"
   fi

   # Default for SHMALL
   #SHMALL=4194304
   SHMALL=5242880
      
   # Check for large memory footprint
   if [[ "`grep '^MemTotal:' /proc/meminfo | awk '{print $2}'`" -ge 75497472 ]]; then
      echo "Detected system with large memory footprint"
      K_SEM="1250 256000 100 8192"
      SHMALL=4294967296
   fi
  
 
   # clear any existing instances of the settings
   for PARAM in $PARAMLIST; do
      sed -i "/^${PARAM}*.=/d" /etc/sysctl.conf
   done
   sed -i "/^# Oracle DB Settings/d" /etc/sysctl.conf

   # Calculate shmmax 
   SHMMAX=$(echo "(`grep '^MemTotal:' /proc/meminfo | awk '{print $2}'` * 1024) - 1" | bc)
   if [[ -z $SHMMAX ]]; then 
      echo "Unable to dynamically determine SHMMAX value, defaulting."
      SHMMAX=2147483648
   fi

   echo "# Oracle DB Settings" >> /etc/sysctl.conf
   echo "kernel.shmall=${SHMALL}" >> /etc/sysctl.conf
   echo "kernel.shmmax=${SHMMAX}" >> /etc/sysctl.conf
   echo "kernel.shmmni=4096" >> /etc/sysctl.conf
   echo "kernel.sem=${K_SEM}" >> /etc/sysctl.conf
   echo "net.core.rmem_default=262144" >> /etc/sysctl.conf
   echo "net.core.rmem_max=4194304" >> /etc/sysctl.conf
   echo "net.core.wmem_default=262144" >> /etc/sysctl.conf
   echo "net.core.wmem_max=1048576" >> /etc/sysctl.conf
   echo "net.ipv4.ip_local_port_range=9000 65500" >> /etc/sysctl.conf
   echo "fs.file-max=6815744" >> /etc/sysctl.conf
   echo "fs.aio-max-nr=1048576" >> /etc/sysctl.conf  

fi

exit



