#!/bin/bash

# Post Clone steps to configure a new Azure VM

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


################END PRE-CHECKS###############################

################RUN SCRIPTS##################################

# if the argument '--reset' is given, the script's step file will be deleted
if [[ -n $1 ]] && [[ "$1" == "--reset" ]]; then
   /bin/rm `f_getStepFile`
fi

# Each action, whether it's the name of a script or a function
# must be run as a step # to make sure the process is resumable

# The last successful step is recorded to a file.  Steps that
# were completed successfully on previous runs will be skipped

#Update DNS info
f_runStep 100 "/opt/sa/scripts/check_my_dns.sh"

## Configure network (Convert DHCP to static)
#f_runStep 200 "/opt/sa/scripts/post_build/setup_network.sh"

# Register with the satellite
f_runStep 210 "/opt/sa/scripts/cloud_assist/setup_rhss_azure.sh N"

# Synchronize package levels with subscribed distros
f_runStep 300 "/opt/sa/scripts/yum_distro-sync.sh"

# Temporary step to add dnscheck to the runlevels
f_runStep 310 "/opt/sa/scripts/check_my_dns.sh"

# Ensures SCOM client cert is created/recreated properly
f_runStep 400 "/opt/sa/scripts/fix_scom.sh"

RCLOCAL=/etc/rc.d/rc.local
# Remove the VMTools thing from /etc/rc.local until I get it fixed in the template
sed -i '/setup_vmtools.sh/d' $RCLOCAL

# Propmt the system to QA on next boot
echo "/opt/sa/scripts/generate_qa.sh" >> $RCLOCAL
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

exit 0

