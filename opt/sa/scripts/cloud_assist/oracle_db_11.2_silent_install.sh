#!/bin/bash

# Silently Installs Oracle 11.2 DB

## Define variables

# Logging
LOGDIR=/var/log/install
LFNAME=oracle_db_silent_install.log
LOGFILE=${LOGDIR}/${LFNAME}

# Directories
ASMDEVDIR=/dev/oracleasm/disks
ORACLE_BASE=/opt/oracle
INSTDIR=${ORACLE_BASE}/product/11.2.0
ORACLE_ASM_HOME=${INSTDIR}/grid
ORACLE_DB_HOME=${INSTDIR}/db_1
RSPDIR=/opt/sa/scripts/cloud_assist/oracle_rsp

# Response Files
DBRSP=${RSPDIR}/OracleDB11203InstallRSP.rsp
ASMRSP1=${RSPDIR}/OracleASM11203InstallRSP.rsp
ASMRSP2=${RSPDIR}/cfgrsp.properties

# Scripts and executables
DB_INSTALLER=/misc/software/Oracle/11.2/11.2.0.3/database/runInstaller
ASM_INSTALLER=/misc/software/Oracle/11.2/11.2.0.3/grid/runInstaller
LSNRCTL=${ORACLE_ASM_HOME}/bin/lsnrctl
ASMCA=${ORACLE_ASM_HOME}/bin/asmca


# Misc
ORACLE_USER=oracle
ORACLE_USER_HOME=$(getent passwd $ORACLE_USER | awk -F':' '{print $6}')
LISTENERORA=${ORACLE_ASM_HOME}/network/admin/listener.ora
TNSNAMESORA=${ORACLE_ASM_HOME}/network/admin/tnsnames.ora
FQDN=`hostname -f`

# Set a flag to tell us if the prechecks fail
PASS=TRUE

# Verify that ASM is installed, working, and that our disks have been labeled
ASMD_REQ="DATA01 DATA02 FLASH01"

for ASMD in $ASMD_REQ; do
   if [[ ! -b "${ASMDEVDIR}/${ASMD}" ]]; then
      echo "Error: ${ASMDEVDIR}/${ASMD} not found or not block special." | tee -a $LOGFILE
      PASS=FALSE
   fi
done

# Verify that we can see the installer 
if [[ ! -x "$ASM_INSTALLER" ]]; then
   echo "Error: $ASM_INSTALLER" | tee -a $LOGFILE
fi

# Verify that we can see all of the response files
for RSP in $DBRSP $ASMRSP1 $ASMRSP2; do
   if [[ ! -f "$RSP" ]]; then
      echo "Error: $RSP not found." | tee -a $LOGFILE
      PASS=FALSE
   fi
done

if [[ "$PASS" != "TRUE" ]]; then
   echo "Error: one or more of the prechecks failed, please check the log at [$LOGFILE]."
   exit 1
fi


# Unsetting the DISPLAY variable will force the installer into text mode
unset DISPLAY

## ASM Setup

# ASM install options
echo "Starting ASM install." | tee -a $LOGFILE
/bin/su - $ORACLE_USER -c "$ASM_INSTALLER \
-nowelcome -silent -ignorePrereq -ignoreSysPrereqs \
INVENTORY_LOCATION=/opt/oracle/oraInventory \
SELECTED_LANGUAGES=en \
ORACLE_BASE=${ORACLE_BASE} \
ORACLE_HOME=${ORACLE_ASM_HOME} \
oracle.install.option=HA_CONFIG \
oracle.install.asm.OSDBA=dba \
oracle.install.asm.OSOPER=dba \
oracle.install.asm.OSASM=dba \
oracle.install.crs.config.autoConfigureClusterNodeVIP=false \
oracle.install.asm.diskGroup.name=DATA \
oracle.install.asm.diskGroup.redundancy=EXTERNAL \
oracle.install.asm.diskGroup.diskDiscoveryString=${ASMDEVDIR}/* \
oracle.install.asm.diskGroup.disks=${ASMDEVDIR}/DATA01 \
oracle.install.asm.SYSASMPassword=kwtdec14 \
oracle.install.asm.monitorPassword=kwtsep09" 2>&1 | tee -a $LOGFILE

# The installer will be backgrounded so we need to watch it until it finishes
TIMER=0

while [[ -n `ps --no-header -u oracle -C java -o command | grep oracle.installer` ]];
   do let TIMER=$TIMER+1
   sleep 1
done
echo "ASM install completed in $TIMER seconds." | tee -a $LOGFILE

# ROOT.SH #1
echo "Running ${ORACLE_ASM_HOME}/root.sh" | tee -a $LOGFILE
${ORACLE_ASM_HOME}/root.sh 2>&1 | tee -a $LOGFILE

# CFGTOOLS
echo "Running CFGTOOLS setup" | tee -a $LOGFILE
/bin/su - $ORACLE_USER -c "${ORACLE_ASM_HOME}/cfgtoollogs/configToolAllCommands" 2>&1 | tee -a $LOGFILE
/bin/su - $ORACLE_USER -c "${ORACLE_ASM_HOME}/cfgtoollogs/configToolAllCommands RESPONSE_FILE=${ASMRSP2}" 2>&1 | tee -a $LOGFILE

### Stop the Listener
##echo "Stopping the listener" | tee -a $LOGFILE
##/bin/su - $ORACLE_USER -c "${LSNRCTL} stop" 2>&1 | tee -a $LOGFILE
##
### Add configs to listener.ora and tnsnames.ora
##echo "Configuring the listener" | tee -a $LOGFILE
##cat << EOF >> $LISTENERORA
##SID_LIST_LISTENER =
##        (SID_LIST =
##        (SID_DESC =
##                (SID_NAME = +ASM)
##                (ORACLE_HOME = ${ORACLE_ASM_HOME})
##        )
##        )
##EOF
##
##echo "Configuring tnsnames.ora" | tee -a $LOGFILE
##cat << EOF >> $TNSNAMESORA
##+ASM =
##  (DESCRIPTION =
##    (ADDRESS = (PROTOCOL = TCP)(HOST = ${FQDN})(PORT = 1521))
##    (CONNECT_DATA =
##      (SERVER = DEDICATED)
##      (SERVICE_NAME = +ASM)
##      (UR=A)
##    )
##  )
##
##
##EOF
##
### Start the Listener
##echo "Starting the listener" | tee -a $LOGFILE
##/bin/su - $ORACLE_USER -c "${LSNRCTL} start" 2>&1 | tee -a $LOGFILE

# Importing additional ASM disks
echo "Adding DATA02 ASM disk to DATA disk group" | tee -a $LOGFILE
/bin/su - $ORACLE_USER -c "${ASMCA} -silent -sysAsmPassword kwtdec14 -addDisk -diskGroupName DATA -disk '/dev/oracleasm/disks/DATA02'" 2>&1 | tee -a $LOGFILE

echo "Creating FLASH disk group and adding FLASH01" | tee -a $LOGFILE
/bin/su - $ORACLE_USER -c "${ASMCA} -silent -sysAsmPassword kwtdec14 -createDiskGroup -diskGroupName FLASH -redundancy EXTERNAL -disk '/dev/oracleasm/disks/FLASH01'" 2>&1 | tee -a $LOGFILE

## DB Install
/bin/su - $ORACLE_USER -c "${DB_INSTALLER} -silent -ignoreSysPrereqs -ignorePrereq -responseFile ${DBRSP}" 2>&1 | tee -a $LOGFILE

# The installer will be backgrounded so we need to watch it until it finishes
TIMER=0

while [[ -n `ps --no-header -u oracle -C java -o command | grep oracle.installer` ]];
   do let TIMER=$TIMER+1
   sleep 1
done

echo "Oracle install completed in $TIMER seconds."

# ROOT.SH #2
echo "Executing ${ORACLE_DB_HOME}/root.sh" | tee -a $LOGFILE
${ORACLE_DB_HOME}/root.sh 2>&1 | tee -a $LOGFILE

# SOFTLINK for TNSNAMES
echo "Creating softlink to tnsnames.ora"
ln -s /misc/tns_admin/tnsnames.ora ${ORACLE_DB_HOME}/network/admin/tnsnames.ora

# Configure the oracle user's system profile
OUSP=${ORACLE_USER_HOME}/.bash_profile

# Clear out previous definitions
TS=`date +%Y%m%d%H%M%S`
/bin/cp -p $OUSP ${OUSP}.${TS}

sed -i '/^ORACLE_BASE=/d;/^export ORACLE_BASE/d;/^ASM_HOME=/d;/^export ASM_HOME/d;/^ORACLE_HOME=/d;/^export ORACLE_HOME/d;/^PATH=/s/:\$ORACLE_HOME\/bin//g' $OUSP

# Add prelimary steps in
cat << EOF >> $OUSP
ORACLE_BASE=${ORACLE_BASE}
export ORACLE_BASE

ASM_HOME=${ORACLE_ASM_HOME}
export ASM_HOME

ORACLE_HOME=${ORACLE_DB_HOME}
export ORACLE_HOME

EOF

# Make sure a path is exported inside the profile
if [[ -z `grep "^PATH=" $OUSP` ]]; then
   echo "PATH=\$PATH:\$HOME/bin:\$ORACLE_HOME/bin" >> $OUSP
   echo "export PATH" >> $OUSP
else
   # Capture the existing PATH in a buffer file
   PATHBUF=/tmp/tmppth
   grep "^PATH=" $OUSP > $PATHBUF

   # Remove the existing PATH from the profile
   sed -i '/^PATH=/d;/^export PATH/d' $OUSP

   # Re-add the path to the end of the file
   cat $PATHBUF >> $OUSP

   # Add ORACLE_HOME/bin to the path
   sed -i '/^PATH=/s/$/:$ORACLE_HOME\/bin/' $OUSP
   echo "export PATH" >> $OUSP

   # Delete the buffer
   /bin/rm $PATHBUF
fi



