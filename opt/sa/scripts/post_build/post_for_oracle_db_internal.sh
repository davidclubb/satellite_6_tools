#!/bin/bash

# Post Build steps to create Oracle DB Server

# Define log file
export LOGFILE=/var/log/install/post_build.log

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
COMPLETION_FILE=/root/.post_build.complete

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

if [[ -n $1 ]]; then
   case $1 in

   11 ) echo "Setting up install for Oracle DB Version $1"
        SISCRIPT=/opt/sa/scripts/post_build/oracle_db_11.2_silent_install.sh
        ;;
   12 ) echo "Setting up install for Oracle DB Version $1"
        SISCRIPT=/opt/sa/scripts/post_build/oracle_db_12_silent_install.sh
        ;;
    * ) echo "FAILURE: [$1] is not a recognized value for Oracle DB Version."
        exit 20
        ;;
   esac
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

# Standardize network configuration
f_runStep 110 "/opt/sa/scripts/post_build/setup_network.sh"

# Synchronize package levels with subscribed distros
f_runStep 200 "/usr/bin/yum -y distribution-synchronization"

# Install supplementary packages
f_runStep 300 "/opt/sa/scripts/post_build/oracle_db_supplementary_packages.sh"

# Try to force a puppet run
f_runStep 400 "/opt/sa/scripts/post_build/puppetrun.sh"

# Temporary step to add dnscheck to the runlevels
f_runStep 405 "/sbin/chkconfig dnscheck on"

# Ensures SCOM client cert is created/recreated properly
f_runStep 410 "/opt/sa/scripts/fix_scom.sh"

# Set up kernel tuning parameters
f_runStep 420 "/opt/sa/scripts/setup_sysctl.sh ORACLEDB"

# Activate kernel tunings
f_runStep 430 "/sbin/sysctl -p"

# Add local accounts
f_runStep 500 "/opt/sa/scripts/post_build/oracle_db_add_local_accounts.sh"

# Add required filesystems
f_runStep 510 "/opt/sa/scripts/post_build/oracle_db_filesystem_setup.sh"

# Label ASM Disks
f_runStep 520 "/opt/sa/scripts/post_build/oracle_db_asmdisk.sh"

# Set miscellaneous permissions
f_runStep 530 "/opt/sa/scripts/post_build/oracle_db_permissions.sh"

# Install the Database

f_runStep 540 "$SISCRIPT"

# Configure firewalld if RHEL 7
f_runStep 600 "/opt/sa/scripts/post_build/setup_firewalld.sh ORACLEDB"

# Setup first run (generate QA, set up VMTools etc...)
f_runStep 700 "/opt/sa/scripts/post_build/setup_firstrun.sh"



################END RUN SCRIPTS##############################


# Drop a "setup_completed" file in root's home directory
touch $COMPLETION_FILE

if [[ -s /etc/motd.sav ]]; then
   /bin/mv /etc/motd.sav /etc/motd
else
   echo "Server Setup Completed `date`" > /etc/motd
fi

#echo "Script complete. The system will be rebooted to finalize any changes."


# Reboot within the next minute
#echo "reboot" | /usr/bin/at `date -d "+1 minute" "+%H:%M"`

exit 0

