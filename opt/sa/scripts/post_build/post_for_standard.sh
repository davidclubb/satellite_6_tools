#!/bin/bash 

# Purpose: Apply standardized configuration to new Linux build
# Incept: 2013/12/27
# Author: SDW
# VERSION: 20131227a


#################FUNCTION DEFINITIONS########################

# Avoid running this setup concurrently
ME=`basename $0`
RUNNING=`ps --no-header -C $ME -o pid`
MYPID=$$
NOTME=`echo $RUNNING | sed "s/^$MYPID //;s/ $MYPID$//;s/^$MYPID$//"`
if [[ -n $NOTME ]]; then
   echo ""
   echo "WARNING: [$ME] is running on this system with PID [$NOTME] - setup is not complete!"
   echo ""
   exit
fi


# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.sh"
   exit
fi

RELEASE=`f_GetRelease | awk '{print $2}'`

export LOGFILE=/var/log/install/setup_linux.log
if [[ ! -d /var/log/install ]]; then mkdir -p /var/log/install; fi
f_SetLogLevel 0
export VTS="date +%Y%m%d%H%M%S"

SCRIPT_DIR=/opt/sa/scripts/post_build
COMPLETION_FILE=/root/.setup_linux.sh.complete

trap "exit 1" TERM
export SPID=$$

################END FUNCTION DEFINITIONS#####################

################PRE-CHECKS###################################

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         This system HAS NOT been configured for LDAP."
   exit 2
fi


################END PRE-CHECKS###############################

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
@    /var/log/install/setup_linux.log for details.            @
@    /root/ks-post.log.1                                      @
@                                                             @
@ To attempt to complete post-install setup, please run       @
@ /opt/sa/scripts/post_build/setup_linux.sh                  @
@                                                             @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
EOF


################END DEAD MAN SWITCH##########################

################RUN SCRIPTS##################################

# if the argument '--reset' is given, the script's step file will be deleted
if [[ -n $1 ]] && [[ "$1" == "--reset" ]]; then
   /bin/rm `f_getStepFile`
fi

# Each action, whether it's the name of a script or a function
# must be run as a step # to make sure the process is resumable

# The last successful step is recorded to a file.  Steps that 
# were completed successfully on previous runs will be skipped

# Configure DNS check
f_runStep 100 "${SCRIPT_DIR}/setup_dnscheck.sh"

# Set up default local accounts
f_runStep 200 "${SCRIPT_DIR}/setup_default_accounts.sh"

# Set up default services
f_runStep 300 "${SCRIPT_DIR}/setup_services.sh"

# Configure network (Convert DHCP to static)
f_runStep 400 "${SCRIPT_DIR}/setup_network.sh"

# Copy Files
#f_runStep 600 "${SCRIPT_DIR}/setup_files.sh"

# Setup first run (generate QA, set up VMTools etc...)
f_runStep 500 "${SCRIPT_DIR}/setup_firstrun.sh"



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
