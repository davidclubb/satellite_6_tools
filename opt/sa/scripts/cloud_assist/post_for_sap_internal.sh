#!/bin/bash

# Post Clone steps to create SAP DB/CI Server

# Define log file
export LOGFILE=/var/log/install/post_clone.log

################DEAD MAN SWITCH##############################
if [[ ! -s /etc/motd.sav ]]; then
   /bin/mv /etc/motd /etc/motd.sav
fi

/bin/cat << EOF > /etc/motd
@@@@@@@@@@@@@@@@@@@@@@@@@@[NOTICE]@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@                                                             @
@ Post-install setup has not been successfully completed      @
@ on this machine.                                            @
@ Please review the following logs for details:               @
@    $LOGFILE
@                                                             @
@ To attempt to complete post-install setup, please run       @
@    $0
@                                                             @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF

################END DEAD MAN SWITCH##########################

#################FUNCTION DEFINITIONS########################

# Make sure /opt/sa/scripts is defined and mounted
if [[ -z `/bin/grep '/opt/sa' /etc/fstab` ]]; then
   echo "knenfsmdc001.acmeplaza.com:/opt_sa  /opt/sa  nfs  soft,intr,defaults  0 0" >> /etc/fstab
   /bin/mount /opt/sa
fi

# Include Common Functions Library
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.sh"
   exit 255
fi

# Set up logging
if [[ ! -d /var/log/install ]]; then mkdir -p /var/log/install; fi
f_SetLogLevel 0
export VTS="date +%Y%m%d%H%M%S"

# Define a completion file to indicate that this script has run to completion before
COMPLETION_FILE=/root/.post_clone.complete

# Exit with an error message if cancelled
trap "exit 1" TERM

# Export the PID for logging functions
export SPID=$$

#################FUNCTION DEFINITIONS########################

################PRE-CHECKS###################################

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   exit 2
fi

# This script requires a SID be passed in as the first argument

if [[ -z $1 ]]; then
   echo "`$VTS`:FAILURE: You must provide an SAP SID as the first argument to `basename $0`." | tee -a /var/log/install/post-clone.log
	   exit 3
   else
   if [[ "$1" == "--reset" ]]; then
      /bin/rm `f_getStepFile`
      echo "Run history has been cleared, please run this script again to"
      echo "start from step 1."
      exit 0
   elif [[ -z `echo $1 | tr '[:lower:]' '[:upper:]' | egrep '(^[A-Z|0-9]{3}$)'` ]]; then
      echo "`$VTS`:FAILURE: [$0] is not a valid SAP SID." | tee -a /var/log/install/post-clone.log
      exit 4
   fi
      
fi

################END PRE-CHECKS###############################

################SET PARAMETERS###############################

SID=`echo $1 | tr '[:lower:]' '[:upper:]'`


################END SET PARAMETERS###########################

################RUN SCRIPTS##################################


# Each action, whether it's the name of a script or a function
# must be run as a step # to make sure the process is resumable

# The last successful step is recorded to a file.  Steps that
# were completed successfully on previous runs will be skipped

# Update DNS info
f_runStep 100 "/opt/sa/scripts/check_my_dns.sh"

# Add local accounts - it's crucial this be done BEFORE joining to the satellite
f_runStep 150 "/opt/sa/scripts/cloud_assist/sap_dbci_add_local_accounts.sh $SID"

# Register with the satellite
#f_runStep 200 "/opt/sa/scripts/setup_rhss.sh SAP"

# Synchronize package levels with subscribed distros
f_runStep 300 "/usr/bin/yum -y distribution-synchronization"

# Install supplementary packages
f_runStep 350 "/opt/sa/scripts/cloud_assist/sap_dbci_supplementary_packages.sh"

# Temporary step to add dnscheck to the runlevels
f_runStep 310 "/sbin/chkconfig dnscheck on"

# Ensures SCOM client cert is created/recreated properly
f_runStep 400 "/opt/sa/scripts/fix_scom.sh"

# Set up kernel tuning parameters
f_runStep 500 "/opt/sa/scripts/setup_sysctl.sh SAP"

# Activate kernel tunings
f_runStep 510 "/sbin/sysctl -p"

# Add required filesystems
f_runStep 700 "/opt/sa/scripts/cloud_assist/sap_dbci_filesystem_setup.sh $SID"

# Set miscellaneous permissions
f_runStep 800 "/opt/sa/scripts/cloud_assist/sap_dbci_permissions.sh"


RCLOCAL=/etc/rc.d/rc.local
# Remove the VMTools thing from /etc/rc.local until I get it fixed in the template
sed -i '/setup_vmtools.sh/d' $RCLOCAL

# Propmt the system to QA on next boot
echo "/opt/sa/scripts/generate_qa.sh" >> $RCLOCAL

# Tell it to remove the QA step after it has run once
echo "sed -i '/generate_qa.sh/d' $RCLOCAL" >> $RCLOCAL

# Drop a "setup_completed" file in root's home directory
touch $COMPLETION_FILE

# Remove dead man switch
sed -i.`date +%Y%m%d%H%M%S` '/\/var\/satellite\/post_scripts/d' /etc/fstab
#if [[ -s /etc/motd.sav ]]; then
#   /bin/mv /etc/motd.sav /etc/motd
#else
   echo "Server Setup Completed `date`" > /etc/motd
#fi

# Reboot within the next minute
echo "reboot" | /usr/bin/at `date -d "+1 minute" "+%H:%M"`

# Exit cleanly
exit 0


