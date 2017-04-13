#!/bin/bash

# Purpose: Generate QA data for the server
# Author: SDW
# Incept: 2014/01/10

#################FUNCTION DEFINITIONS########################

#-----------------
# Function: f_PathOfScript
#-----------------
# Returns the location of the script, irrespective of where it
# was launched.  This is useful for scripts that look for files
# in their current directory, or in relative paths from it
#
#-----------------
# Usage: f_PathOfScript
#-----------------
# Returns: <PATH>

f_PathOfScript () {

   unset RESULT

   # if $0 begins with a / then it is an absolute path
   # which we can get by removing the scipt name from the end of $0
   if [[ -n `echo $0 | grep "^/"` ]]; then
      BASENAME=`basename $0`
      RESULT=`echo $0 | sed 's/'"$BASENAME"'$//g'`

   # if this isn't an absolute path, see if removing the ./ from the
   # beginning of $0 results in just the basename - if so
   # the script is being executed from the present working directory
   elif [[ `echo $0 | sed 's/^.\///g'` == `basename $0` ]]; then
      RESULT=`pwd`

   # If we're not dealing with an absolute path, we're dealing with
   # a relative path, which we can get with pwd + $0 - basename
   else
      BASENAME=`basename $0`
      RESULT="`pwd`/`echo $0 | sed 's/'"$BASENAME"'$//g'`"
   fi

   echo $RESULT

}

cd `f_PathOfScript`

# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

if [[ $EUID != 0 ]]; then
   echo "FAILURE: This script must be run as root or with equivalent privilege."
   echo "         Setup has not been completed on this system."
   exit 2
fi

#### SETTINGS ####

# If VERBOSE is 0, output is suppressed, if it is non-zero output is displayed
VERBOSE=0


# Set the variable timestamp
if [[ -z $VTS ]]; then
   export VTS="date +%Y%m%d%H%M%S"
fi

# Define the logfile
if [[ -z $LOGFILE ]]; then
   export LOGFILE=/var/log/install/`basename $0`.log
   f_SetLogLevel 0
fi

# Define the output file
OS_HOSTNAME=`hostname`
QA_DIR=/opt/satellite/quality_assurance
QA_ARC=/opt/satellite/quality_assurance/archived
QA_SERVER=satellite
QA_SHARE=${QA_SERVER}:/opt/satellite/quality_assurance
OUTFILENAME=${OS_HOSTNAME}_`$VTS`.html
OUTFILE=${QA_DIR}/${OUTFILENAME}

# Variables
TPUT=/usr/bin/tput

###########NON-INTERACTIVE DETAILS##############

# User Name
QA_USER=$(who -m | grep " `/bin/ps --no-heading -p $$ -o tty` " | awk '{print $1}')

if [[ -z $QA_USER ]]; then
   QA_USER=kickstart
fi

# System ID
OS_NAME=`hostname | awk -F'.' '{print $1}'`
if [[ -z `host $OS_HOSTNAME 2>&1 | grep -i "not found"` ]]; then
   NET_FQDN=`host $OS_HOSTNAME | awk '{print $1}'`
else
   NET_FQDN=`hostname --fqdn`
fi

if [[ -n `echo $NET_FQDN | grep '\.'` ]]; then
   NET_DOMAIN=`echo ${NET_FQDN#*.}`
else
   NET_DOMAIN=
fi

OS_TYPE=`uname -s`
OS_RELEASE=`f_GetRelease`
RELEASE=`f_GetRelease | awk '{print $2}'`

OS_RUNLEVEL=`/bin/grep -v ^# /etc/inittab | /bin/grep -i "initdefault" | /bin/awk -F':' '{print $2}'`
if [[ -z $OS_RUNLEVEL ]]; then
   OS_RUNLEVEL=`/bin/systemctl get-default`
fi

if [[ "`f_DetectVM`" != "TRUE" ]]; then
   HW_CLASS="Physical"
else
   HW_CLASS="Virtual"
fi

#HW_SERIAL=`dmidecode | awk /"System Information"/,/"Serial Number"/ | grep "Serial Number" | awk -F':' '{print $NF}'`
HW_SERIAL=`dmidecode | awk /"System Information"/,/"Serial Number"/ | grep "Serial Number" | sed 's/.*Serial Number:[ \t]//'`

NET_PUBIF=`f_FindPubIF`
if [[ "$NET_PUBIF" != "FAILURE" ]]; then
   if [[ -f "/sys/class/net/${NET_PUBIF}/address" ]]; then
      NET_MAC_ADDR=`cat /sys/class/net/${NET_PUBIF}/address`
   else
      NET_MAC_ADDR=UNKNOWN
   fi
fi

NET_PUBIP=`f_IPforIF $NET_PUBIF`


# General Hardware
if [[ "`f_DetectVM`" != "TRUE" ]]; then
   HW_CLASS="Physical"
else
   HW_CLASS="Virtual"
fi

HW_VENDOR=`f_GetVendor`

HW_PRODUCT=`/usr/sbin/dmidecode | awk /"System Information"/,/"Serial Number"/ | grep "Product" | sed 's/.*Product Name:[ \t]//'`

# Network Hardware
NET_DRIVER=`/sbin/ethtool -i $NET_PUBIF | grep ^driver: | sed 's/^driver:[ \t]//'`

# Processor Information
HW_CPU_FAMILY=`dmidecode -t4 | grep Family: | awk -F': ' '{print $2}' | head -1`
HW_CPU_CACHEK=`grep "cache size" /proc/cpuinfo | head -1 | awk '{print $4}'`
if [[ $HW_CPU_CACHEK -lt 1024 ]]; then
   PCACHESTRING="${HW_CPU_CACHEK}K"
else
   PCACHESTRING="$( expr $HW_CPU_CACHEK / 1024 )M"
fi

# Get a socket count by looking at how many unique physical ids there are
HW_CPU_SOCKETS=`cat /proc/cpuinfo | grep "physical id" | sort -u | wc -l`
if [[ -z $HW_CPU_SOCKETS ]] || [[ $HW_CPU_SOCKETS == 0 ]]; then
   HW_CPU_SOCKETS=1
fi

# Get a physical core count by looking at how many unique core ids we have per physical id
unset HW_CPU_CORES
for i in `cat /proc/cpuinfo | grep "physical id" | sort -u | awk '{print $NF}'`; do
   THIS_CORE_COUNT=`cat /proc/cpuinfo | sed 's/\t/ /g' | sed 's/ //g' | awk /"physicalid:$i"/,/"coreid"/ | grep "coreid"| sort -u | wc -l`
   let HW_CPU_CORES=$HW_CPU_CORES+$THIS_CORE_COUNT
done

if [[ -z $HW_CPU_CORES ]]; then
   HW_CPU_CORES=1
fi

# Get a thread count based on the raw number of "processors" showing up
HW_CPU_THREADS=`cat /proc/cpuinfo | grep "^processor" | wc -l`

# If the core and thread counts don't agree, it can only be because hyperthreading is on
if [[ $phys_core_count != $thread_count ]]; then
   CPUNMBR="($HW_CPU_CORES cores, $HW_CPU_THREADS threads)"
else
   CPUNMBR="($HW_CPU_CORES cores)"
fi

# Grab the CPU speed
HW_CPU_SPEED=`/usr/sbin/dmidecode | grep "Current Speed" | egrep -v "Unknown" | sort | uniq | cut -c17-25`
HW_CPU_SPEED=`echo $HW_CPU_SPEED | sed 's/^ //' | sed 's/ $//'`

# Grab the CPU type
HW_CPU_NAME=`/usr/sbin/dmidecode | awk /"Processor Information"/,/"Core Enabled"/ | grep "Version:" | head -1 | sed 's/Version://' | awk -F'@' '{print $1}' | sed 's/\t/ /g' | sed 's/ \+ / /g'`
HW_CPU_NAME=`echo $HW_CPU_NAME| sed 's/^ //' | sed 's/ $//'`



# Memory Information
TOTALKB=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
let HW_MEM_MB=$TOTALKB/1024
let TOTALGB=$HW_MEM_MB/1024

HW_MEM_MODULES=`/usr/sbin/dmidecode -t 17 | grep Size | egrep -v 'No Module Installed' | sort | uniq -c | awk '{print $1"x"$3 $4" "}' | tr -d '\n'`

# Disk information

# Disk Count

HW_STORAGE_DISKS=`fdisk -l 2>&1 | grep ^Disk | egrep -v 'doesn|mapper|identifier|type|dm-' | wc -l`

# Total Space

for BYTES in `fdisk -l 2>&1 | grep "^Disk /dev" | egrep -v 'doesn|mapper|identifier|type|dm-' | awk '{print $5}'`; do ADDBYTES="$ADDBYTES + $BYTES"; done
HW_STORAGE_GB=$(echo `echo $ADDBYTES | sed 's/^+ //' | bc` / 1073741824 | bc)

# QA Checks

# If this is a RHEL 7 box it uses systemd which brings everything up in parallel
# including rc.local.  This adds an arbitrary wait to give the system a chance 
# to finish coming up before running the checks

if [[ $RELEASE -ge 7 ]]; then
   # Set a target uptime in seconds
   TUP=60

   # If the system's uptime has not yet reached the target
   if [[ `cat /proc/uptime | awk -F'.' '{print $1}'` -lt $TUP ]]; then

      # Sleep the number of seconds difference until it has
      sleep $(echo "$TUP - $(cat /proc/uptime | awk -F'.' '{print $1}')" | bc )
   fi
fi

# Multi-use variables

## Find the default kernel line - this is similar to what's contained in /proc/cmdline
## but determines default behavior rather than last behavior.

# Find the default kernel line in GRUB


DEFAULTKLINE=$(/sbin/grubby --info=$(/sbin/grubby --default-kernel) | sort -u | grep ^args | awk -F'"' '{print $2}')

### Task Scheduler 

# Settings and variables
SCHED_EXP_SETTING=noop

# Check current state

QA_SCHEDCHECK=PASS
# Look at each block device
#for bd in `find /sys/block/`; do
for bd in `ls /sys/block/ | /bin/egrep -v '^fd|^sr|^hdc' | sed 's/^/\/sys\/block\//g'`; do
   # Get the block device name from its path
   D=`echo $bd | /bin/awk -F'/' '{print $NF}'`

   # Pull the setting out of sysfs
   unset SETTING
   if [[ -f "${bd}/queue/scheduler" ]]; then
      SETTING=`/bin/cat "${bd}/queue/scheduler" 2>&1`
   fi

   # If the device name is valid and setting isn't "none" then check it.
#   if [[ -n $D ]] && [[ -n $SETTING ]] && [[ "$SETTING" != "none" ]]; then 
   if [[ -n $SETTING ]] && [[ "$SETTING" != "none" ]]; then 
      SCHEDULER=`echo $SETTING | /bin/awk -F']' '{print $1}' | awk -F'[' '{print $2}'`
      if [[ "$SCHEDULER" != "$SCHED_EXP_SETTING" ]]; then
         QA_SCHEDCHECK=FAIL
         #echo "QA_FAIL:QA_SCHEDCHECK:Scheduler for block device [$D] is [$SCHEDULER] but should be $SCHED_EXP_SETTING"
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SCHEDCHECK:Scheduler for block device [$D] is [$SCHEDULER] but should be $SCHED_EXP_SETTING"
      else
         if [[ $VERBOSE -gt 0 ]]; then
            #echo "QA_INFO:QA_SCHEDCHECK:Scheduler for block device $D is $SCHEDULER"
            QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SCHEDCHECK:Scheduler for block device $D is $SCHEDULER"
         fi
      fi
   fi
done

# Check persistent state


if [[ -z `echo $DEFAULTKLINE | grep "elevator="` ]]; then
   QA_SCHEDCHECK=FAIL
   #echo "QA_FAIL:QA_SCHEDCHECK:Scheduler not defined in GRUB"
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SCHEDCHECK:Scheduler not defined in GRUB"
else
   BOOTSCHED=`echo $DEFAULTKLINE | awk -F'elevator=' '{print $2}' | awk '{print $1}'`
   if [[ "$BOOTSCHED" != "$SCHED_EXP_SETTING" ]]; then
      #echo "QA_FAIL:QA_SCHEDCHECK:Scheduler defined as $BOOTSCHED in GRUB but should be $SCHED_EXP_SETTING"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SCHEDCHECK:Scheduler defined as $BOOTSCHED in GRUB but should be $SCHED_EXP_SETTING"
      QA_SCHEDCHECK=FAIL
   else
      if [[ $VERBOSE -gt 0 ]]; then
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SCHEDCHECK:Scheduler defined as $BOOTSCHED in GRUB"
         #echo "QA_INFO:QA_SCHEDCHECK:Scheduler defined as $BOOTSCHED in GRUB"
      fi
   fi
fi

### NET

QA_NETCHECK=PASS

# Determine the configuration protocol of the public network interface
IFPROTO=`/bin/grep "^BOOTPROTO=" /etc/sysconfig/network-scripts/ifcfg-${NET_PUBIF} | awk -F'=' '{print $2}' | sed 's/"//g'`

#if [[ "${IFPROTO}" != "static" ]]; then
#if [[ "${IFPROTO}" != "static" ]] && [[ "${IFPROTO}" != "none" ]]; then
#   QA_NETCHECK=FAIL
#   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_NETCHECK:Primary network interface [$NET_PUBIF] boot protocol is [$IFPROTO]"
#fi

QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_NETCHECK:Primary network interface [$NET_PUBIF] boot protocol is [$IFPROTO]"

### DNS

# Settings and variables
NSLIST="10.252.13.135 10.252.13.134 10.252.13.133"
SEARCHLIST="acmeplaza.com acme.com acmetest.com"

# Check resolver addresses
QA_DNSCHECK=PASS

for NS in $NSLIST; do
   if [[ -z `grep -v "#" /etc/resolv.conf | grep "nameserver" | grep $NS` ]]; then
      QA_DNSCHECK=FAIL
      #echo "QA_FAIL:QA_DNSCHECK:$NS not defined as a DNS resolver"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_DNSCHECK:$NS not defined as a DNS resolver"
   else
      if [[ $VERBOSE -gt 0 ]]; then
         #echo "QA_INFO:QA_DNSCHECK:$NS defined as a DNS resolver"
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_DNSCHECK:$NS defined as a DNS resolver"
      fi
   fi
done

NSFILTER=`echo $NSLIST | sed 's/ /|/g'`

for UNS in `grep -v "#" /etc/resolv.conf | grep "nameserver" | egrep -v "$NSFILTER" | awk '{print $2}'`; do
   QA_DNSCHECK=FAIL
   #echo "QA_FAIL:QA_DNSCHECK:Non-standard DNS resolver $UNS defined"
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_DNSCHECK:Non-standard DNS resolver $UNS defined"
done

# Check search suffixes

for DOM in $SEARCHLIST; do
   if [[ -z `/bin/grep -v "#" /etc/resolv.conf | /bin/grep "search" | /bin/egrep -i " $DOM | $DOM$"` ]]; then
      QA_DNSCHECK=FAIL
      #echo "QA_FAIL:QA_DNSCHECK:Search suffix $DOM is not defined"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_DNSCHECK:Search suffix $DOM is not defined"
   else
      if [[ $VERBOSE -gt 0 ]]; then
         #echo "QA_INFO:QA_DNSCHECK:Search suffix $DOM is defined"
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_DNSCHECK:Search suffix $DOM is defined"
      fi
   fi
done

# Check to see if the server is registered in DNS

# Forward registration check
if [[ -z `/usr/bin/dig +short -t A ${OS_NAME}.${NET_DOMAIN} | /bin/grep $NET_PUBIP` ]]; then
   QA_DNSCHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_DNSCHECK:Server's host record [${OS_NAME}.${NET_DOMAIN}] is not registered in DNS."
fi

# Reverse registration check
if [[ -z `/usr/bin/dig +short -x $NET_PUBIP | /bin/grep "^${OS_NAME}\."` ]]; then
   QA_DNSCHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_DNSCHECK:Server's PTR (reverse) record [$NET_PUBIP] is not registered in DNS."
fi

### Check for SCOM Agent

# Settings and variables
SCOMBIN=omiserver
SCOMINIT=scx-cimd
SCOMRPM=scx

# Check 1 is the service installed
QA_SCOMCHECK=PASS
if [[ -z `/bin/rpm -qa $SCOMRPM` ]]; then
   QA_SCOMCHECK=FAIL
   #echo "QA_FAIL:QA_SCOMCHECK:SCOM agent not installed"
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SCOMCHECK:SCOM agent not installed"
else
   if [[ $VERBOSE -gt 0 ]]; then
      #echo "QA_INFO:QA_SCOMCHECK:SCOM agent version `/bin/rpm -qa scx` installed"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SCOMCHECK:SCOM agent version `/bin/rpm -qa scx` installed"
   fi
fi

# Check 2 is the service running

if [[ -z `/bin/ps --no-header -C $SCOMBIN -o pid` ]]; then
   QA_SCOMCHECK=FAIL
   #echo "QA_FAIL:QA_SCOMCHECK:SCOM daemon not running"
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SCOMCHECK:SCOM daemon not running"
else
   if [[ $VERBOSE -gt 0 ]]; then
      #echo "QA_INFO:QA_SCOMCHECK:SCOM daemon is running with PID`/bin/ps --no-header -C $SCOMBIN -o pid`"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SCOMCHECK:SCOM daemon is running with PID`/bin/ps --no-header -C $SCOMBIN -o pid`"
   fi
fi

# Check 3 is the service persistent

if [[ -z `/sbin/chkconfig --list $SCOMINIT 2>&1 | grep '3:on' | grep '5:on'` ]]; then
   QA_SCOMCHECK=FAIL
   #echo "QA_FAIL:QA_SCOMCHECK:SCOM daemon not set to start automatically"
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SCOMCHECK:SCOM daemon not set to start automatically"
else
   if [[ $VERBOSE -gt 0 ]]; then
      #echo "QA_INFO:QA_SCOMCHECK:SCOM daemon set to start automatically"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SCOMCHECK:SCOM daemon set to start automatically"
   fi
fi

### Check Authentication 


# Settings and variables
#DCS="knedcxiwp003.acmeplaza.com knedcxiwp004.acmeplaza.com knedcxiwp005.acmeplaza.com"
DCS="knedcxiwp004.acmeplaza.com knedcxiwp005.acmeplaza.com knedcxiwp003.acmeplaza.com" 

if [[ $RELEASE -lt 6 ]]; then
   LDC1=/etc/ldap.conf
   LDRPS="nss_ldap openldap openldap-clients cyrus-sasl-gssapi"
elif [[ $RELEASE -eq 6 ]]; then
   LDC1=/etc/nslcd.conf
   LDRPS="nss-pam-ldapd openldap openldap-clients pam_ldap"
else
   LDC1=/etc/nslcd.conf
   LDRPS="nss-pam-ldapd openldap openldap-clients"
fi

KRPS="pam_krb5 krb5-libs krb5-workstation"
LDC2=/etc/openldap/ldap.conf

# Check LDAP installation
QA_AUTHCHECK=PASS

for map in passwd shadow group; do
   if [[ -z `/bin/grep "^${map}:" /etc/nsswitch.conf | grep ldap` ]]; then
      QA_AUTHCHECK=FAIL
      #echo "QA_FAIL:QA_AUTHCHECK:LDAP is not defined as a source for $map in nsswitch"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:LDAP is not defined as a source for $map in nsswitch"
   fi
done


for LDRP in $LDRPS; do
   if [[ -z `/bin/rpm -qa $LDRP` ]]; then
      QA_AUTHCHECK=FAIL
      #echo "QA_FAIL:QA_AUTHCHECK:The package $LDRP is required for LDAP but not installed"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:The package $LDRP is required for LDAP but not installed"
   else
      if [[ $VERBOSE -gt 0 ]]; then
         #echo "QA_INFO:QA_AUTHCHECK:The package $LDRP is installed"
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_AUTHCHECK:The package $LDRP is installed"
      fi
   fi
done

# Check LDAP Configuration

if [[ "$QA_AUTHCHECK" != "FAIL" ]]; then
   # Read crucial settings
   BINDDN=`grep -i "^binddn" $LDC1 | sed 's/^binddn[ \t]//I'`
   BINDPW=`grep -i "^bindpw" $LDC1 | sed 's/^bindpw[ \t]//I'`
   URI=`grep -i "^uri" $LDC1 | sed 's/^uri[ \t]//I'`
   SSL=`grep -i "^ssl" $LDC1 | sed 's/^ssl[ \t]//I' | tr '[:upper:]' '[:lower:]'`
   
   if [[ -z $BINDDN ]]; then
      QA_AUTHCHECK=FAIL
      #echo "QA_FAIL:QA_AUTHCHECK:The Bind DN is not specified in the LDAP configuration"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:The Bind DN is not specified in the LDAP configuration"
   fi
   if [[ -z $BINDPW ]]; then
      QA_AUTHCHECK=FAIL
      #echo "QA_FAIL:QA_AUTHCHECK:The Bind DN's password is not specified in the LDAP configuration"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:The Bind DN's password is not specified in the LDAP configuration"
   fi
   if [[ -z $SSL ]]; then
      QA_AUTHCHECK=FAIL
      #echo "QA_FAIL:QA_AUTHCHECK:LDAP is not configured to use SSL"
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:LDAP is not configured to use SSL"
   elif [[ "$SSL" != "yes" ]]; then
      if [[ $RELEASE -ne 5 ]]; then
         QA_AUTHCHECK=FAIL
         #echo "QA_FAIL:QA_AUTHCHECK:LDAP SSL mode is set to \'$SSL\' but should be \'yes\'"
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:LDAP SSL mode is set to '$SSL' but should be 'yes'"
      fi
   fi

   for DC in $DCS; do
      if [[ -z `echo $URI | grep -i $DC` ]]; then
         QA_AUTHCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:$DC is missing from the LDAP URI"
      fi
   done
fi

# Check NSLCD status if RHEL 6

if [[ $RELEASE -eq 6 ]]; then
   if [[ -z `/sbin/chkconfig --list nslcd 2>&1 | grep '3:on' | grep '5:on'` ]]; then
      QA_AUTHCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:nslcd is not set to start automatically"
   fi
   if [[ -z `/bin/ps --no-header -C nslcd -o pid` ]]; then
      QA_AUTHCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:nslcd is not running"
   fi
fi

# Check NSLCD status if RHEL 7

if [[ $RELEASE -eq 7 ]]; then
   if [[ -z `/bin/systemctl is-enabled nslcd | grep 'enabled'` ]]; then
      QA_AUTHCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:nslcd is not set to start automatically"
   fi
   if [[ -z `/bin/systemctl is-active nslcd | grep 'active'` ]]; then
      QA_AUTHCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_AUTHCHECK:nslcd is not running"
   fi
fi


# Check Kerberos configuration
QA_KERBEROSCHECK=PASS

KRBCONF=/etc/krb5.conf
KRBEDR=ACMEPLAZA.COM
KRBRPS="krb5-libs pam_krb5 krb5-workstation"


for KRBRP in $KRBRPS; do
   if [[ -z `/bin/rpm -qa $KRBRP` ]]; then
      QA_KERBEROSCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KERBEROSCHECK:The package $KRBRP is required for kerberos but not installed"
   fi
done
if [[ "$QA_KERBEROSCHECK" != "FAIL" ]]; then
   KRBCDR=`/bin/egrep "^[ \t]default_realm[ \t]=" $KRBCONF | /bin/sed 's/^[ \t]default_realm[ \t]=[ \t]//g'`
   if [[ "$KRBCDR" != "$KRBEDR" ]]; then
      QA_KERBEROSCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KERBEROSCHECK:Default realm is set to [$KRBCDR], should be [$KRBEDR] "
   fi
fi


## By default the system should be getting managed by Satellite 6, but Satellite 5 will pass.

QA_SATCHECK=PASS
SAT6CFG1=/etc/rhsm/rhsm.conf
SUBMGR=/usr/sbin/subscription-manager
SAT5CFG1=/etc/sysconfig/rhn/rhnsd

if [[ -s $SAT6CFG1 ]] && [[ -z `$SUBMGR identity 2>&1 | /bin/grep "RHN Classic"` ]]; then

   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:System configured with Subscription Manager"
   
   SAT6ESS=satellite.acmeplaza.com
   SAT6ESP=https
   PUPCFG=/etc/puppet/puppet.conf
   PUPEPM=${SAT6ESS}
   
   SAT6RPS="subscription-manager katello-agent facter puppet katello-ca-consumer-${SAT6ESS}"
   for SATRP in $SAT6RPS; do
      if [[ -z `/bin/rpm -qa $SATRP` ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:The package $SATRP is required for satellite but not installed"
      fi
   done

   if [[ "$QA_SATCHECK" != "FAIL" ]]; then

      SAT6CSS=`/bin/grep "^hostname" $SAT6CFG1 | /bin/awk -F'=' '{print $2}' | /bin/awk '{print $1}'`
      SAT6CSP=`/bin/grep "^baseurl" $SAT6CFG1 | /bin/awk -F'=' '{print $2}' | /bin/awk -F'://' '{print $1}' | tr '[:upper:]' '[:lower:]'`
      PUPCPM=`/bin/grep "^server=" $PUPCFG | /bin/awk -F'=' '{print $2}' | /bin/awk '{print $1}'`
      PUPCEN=`/bin/grep "^environment=" $PUPCFG | /bin/awk -F'=' '{print $2}' | /bin/awk '{print $1}'`

      if [[ -n `$SUBMGR identity 2>&1 | /bin/grep "not yet registered"` ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:Subscription Manager reports system not registered."
      fi
      if [[ "$SAT6CSS" != "$SAT6ESS" ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:Subscription Manager is pointed to [$SATCSS], should be [$SATESS]"
      fi
      if [[ "$SATCSP" != "$SATESP" ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:Subscription Manager is using [$SATCSP], should be [$SATESP]"
      fi
      if [[ "$PUPCPM" != "$PUPCPM" ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:Puppet agent Puppet Master is [$PUPCPM], should be [$PUPEPM]"
      fi
      if [[ -n $PUPCEN ]]; then
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:Puppet agent Environment is [$PUPCEN]"
      else
         #QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:Puppet agent Environment not configured in [$PUPCFG]."
      fi
      if [[ -s /root/ks.cfg ]]; then
         KSCFG=/root/ks.cfg
      elif [[ -s /root/anaconda-ks.cfg ]]; then
         KSCFG=/root/anaconda-ks.cfg
      fi
      if [[ -n $KSCFG ]] && [[ -n `/bin/grep rhnreg_ks $KSCFG` ]]; then
         KSKEY=`/bin/grep -m 1 rhnreg_ks $KSCFG | awk -F',' '{print $NF}'`
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:System kickstarted with activation key [$KSKEY]"
      fi
      if [[ -s /root/activationkey ]]; then
         AKEY=`/bin/cat /root/activationkey`
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:System last registered with activation key [$AKEY]"
      fi

   fi

   
elif [[ -s $SAT5CFG1 ]]; then 
   
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:system configured with RHN client"

   ## Check Satellite Registration
   SATCLICFG1=/etc/sysconfig/rhn/up2date
   SATCLICFG2=/etc/sysconfig/rhn/rhnsd
   SATCLID=/etc/init.d/rhnsd
   SATRPS="rhn-client-tools rhnlib rhnsd rhn-check yum-rhn-plugin"
   SATESS=satellite5.acmeplaza.com
   SATESP=https
   SATECI=60
   
   
   for SATRP in $SATRPS; do
      if [[ -z `/bin/rpm -qa $SATRP` ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:The package $SATRP is required for satellite but not installed"
      fi
   done
   
   if [[ "$QA_SATCHECK" != "FAIL" ]]; then
      SATCSS=`/bin/grep "^serverURL=" $SATCLICFG1 | /bin/awk -F'//' '{print $2}' | /bin/awk -F'/' '{print $1}' | tr '[:upper:]' '[:lower:]'`
      SATCSP=`/bin/grep "^serverURL=" $SATCLICFG1 | /bin/awk -F'=' '{print $2}' | /bin/awk -F'://' '{print $1}' | tr '[:upper:]' '[:lower:]'`
      SATCCI=`/bin/grep "^INTERVAL=" $SATCLICFG2 | /bin/awk -F'=' '{print $2}'`
      if [[ "$SATCSS" != "$SATESS" ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:RHN client is pointed to [$SATCSS], should be [$SATESS]"
      fi
      if [[ "$SATCSP" != "$SATESP" ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:RHN is using [$SATCSP], should be [$SATESP]"
      fi
      if [[ "$SATCCI" != "$SATECI" ]]; then
         QA_SATCHECK=FAIL
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:RHN client check interval is [$SATCCI], should be [$SATECI]"
      fi
      if [[ -s /root/ks.cfg ]]; then
         KSCFG=/root/ks.cfg
      elif [[ -s /root/anaconda-ks.cfg ]]; then
         KSCFG=/root/anaconda-ks.cfg
      fi
      if [[ -n $KSCFG ]] && [[ -n `/bin/grep rhnreg_ks $KSCFG` ]]; then
         KSKEY=`/bin/grep -m 1 rhnreg_ks $KSCFG | awk -F',' '{print $NF}'`
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:System kickstarted with activation key [$KSKEY]"
      fi
      if [[ -s /root/activationkey ]]; then
         AKEY=`/bin/cat /root/activationkey`
         QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_INFO:QA_SATCHECK:System last registered with activation key [$AKEY]"
      fi
      
   fi
else
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SATCHECK:Unable to find subscription manager or RHN registration."
   QA_SATCHECK=FAIL
fi

## Check Kernel Dump settings

# Verify the crashkernel boot option
QA_KDUMPCHECK=PASS

if [[ -z `echo $DEFAULTKLINE | grep crashkernel` ]]; then
   QA_KDUMPCHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KDUMPCHECK: crashkernel option not present in GRUB"
fi

# Verify daemon is running
if [[ `cat /sys/kernel/kexec_crash_loaded 2>&1` != 1 ]]; then
   QA_KDUMPCHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KDUMPCHECK: crashkernel not loaded"
fi

# Verify config
KDUMPCFG=/etc/kdump.conf
KDEPATH=/var/crash
KDEML=7
KDEDL=14

if [[ ! -s $KDUMPCFG ]]; then
   QA_KDUMPCHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KDUMPCHECK:kdump configuration file $KDUMPCFG missing or empty"
else
   KDCPATH=`/bin/grep "^path" $KDUMPCFG | /bin/sed 's/^path[ \t]//g'`
   KDCCOMM=`/bin/grep "^core_collector" $KDUMPCFG`
   KDCML=`echo $KDCCOMM | awk -F'--message-level' '{print $2}' | awk '{print $1}'`
   KDCDL=`echo $KDCCOMM | awk -F'-d' '{print $2}' | awk '{print $1}'`
   if [[ "$KDCPATH" != "$KDEPATH" ]]; then
      QA_KDUMPCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KDUMPCHECK:kdump path is [$KDCPATH], should be [$KDEPATH]"
   fi
   if [[ "$KDCML" != "$KDEML" ]]; then
      QA_KDUMPCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KDUMPCHECK:kdump message level is [$KDCML], should be [$KDEML]"
   fi
   if [[ "$KDCDL" != "$KDEDL" ]]; then
      QA_KDUMPCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KDUMPCHECK:kdump dump level is [$KDCDL], should be [$KDEDL]"
   fi
   if [[ -z `echo $KDCCOMM | egrep '\-c|\-l'` ]]; then
      QA_KDUMPCHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_KDUMPCHECK:kdump is not configured to use compression"
   fi
fi

## Check syslog

#if [[ $RELEASE -lt 6 ]]; then
#   SYSLOGCONF=/etc/syslog.conf
#else
   SYSLOGCONF=/etc/rsyslog.conf
#fi
LRIP=10.0.192.130

QA_SYSLOGCHECK=PASS

if [[ -z `/bin/egrep -v '^#|^$' $SYSLOGCONF | /bin/grep 'authpriv\.\*' | /bin/grep "@${LRIP}"` ]]; then
   QA_SYSLOGCHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SYSLOGCHECK:LogRythm[$LRIP] not configured as a logging target for authpriv"
fi

## Check NTP settings

#server ntp.acme.com iburst
NTPSERVER=ntp.acme.com
ACCEPTIBLEDRIFT=90

QA_TIMECHECK=PASS

# Check time against NTP
NTPTIME=$(/bin/date -d "`/usr/sbin/ntpdate -d $NTPSERVER 2>&1 | grep "^reference time" | head -1 | awk '{print $4,$5,$6,$7,$8}'`" +%s)
SERVERTIME=`/bin/date +%s`
let TIMEDIFF=$NTPTIME-$SERVERTIME
ATIMEDIFF=`echo $TIMEDIFF | sed 's/^-//'`

if [[ $ATIMEDIFF -gt $ACCEPTIBLEDRIFT ]]; then
   QA_TIMECHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_TIMECHECK:Time difference between server and NTP is [$ATIMEDIFF] seconds, max allowable is [$ACCEPTIBLEDRIFT]"
fi

if [[ $RELEASE -le 6 ]]; then
   if [[ -z `/bin/grep "^server" /etc/ntp.conf | grep $NTPSERVER` ]]; then
      QA_TIMECHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_TIMECHECK:[$NTPSERVER] is not configured as a source clock in /etc/ntp.conf"
   fi
else
   if [[ -z `/bin/grep "^server" /etc/chrony.conf | grep $NTPSERVER` ]]; then
      QA_TIMECHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_TIMECHECK:[$NTPSERVER] is not configured as a source clock in /etc/chrony.conf"
   fi
fi

## Check SELINUX
QA_SELINUXCHECK=PASS
if [[ $RELEASE -lt 7 ]]; then
   SELINUX_ES=disabled
else
   SELINUX_ES=permissive
fi
SELINUX_FS=`/bin/grep "^SELINUX=" /etc/sysconfig/selinux 2>&1 | /bin/awk -F'=' '{print $2}'`
if [[ -n $SELINUX_FS ]] && [[ "$SELINUX_FS" != "$SELINUX_ES" ]]; then
   QA_SELINUXCHECK=FAIL
   QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SELINUXCHECK:SELinux set to [$SELINUX_FS], should be set to [$SELINUX_ES]"
fi

#SELINUX=enforcing

## Audit Services

QA_SERVICECHECK=PASS

#REQUIRED_SERVICES="scx-cimd ntpd nscd nfs nfslock"
REQUIRED_SERVICES="scx-cimd ntpd nscd"

if [[ $RELEASE -le 5 ]]; then
   #REQUIRED_SERVICES="iptables sshd ntpd nfs kdump"
   REQUIRED_SERVICES="iptables sshd ntpd kdump"
fi

# Specific services for RHEL 6
if [[ $RELEASE -eq 6 ]]; then
   #REQUIRED_SERVICES="iptables sshd ntpd nfs kdump nslcd oddjobd"
   REQUIRED_SERVICES="iptables sshd ntpd kdump nslcd oddjobd"
fi

# Specific services for RHEL 7
if [[ $RELEASE -eq 7 ]]; then
   REQUIRED_SERVICES="firewalld sshd chronyd kdump nslcd oddjobd"
fi


PROHIBITED_SERVICES=

for RS in $REQUIRED_SERVICES; do

   if [[ ! -s "/etc/init.d/${RS}" ]] && [[ ! -s "/usr/lib/systemd/system/${RS}.service" ]]; then
      QA_SERVICECHECK=FAIL
      QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SERVICECHECK:required service [$RS] is not installed"
   else
      if [[ $RELEASE -le 6 ]]; then
         if [[ -z `/sbin/chkconfig --list $RS 2>&1 | grep '3:on' | grep '5:on'` ]]; then
            QA_SERVICECHECK=FAIL
            QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SERVICECHECK:required service [$RS] not set to start automatically"
         fi
      else
         if [[ -z `/bin/systemctl is-enabled $RS | grep 'enabled'` ]]; then
            QA_SERVICECHECK=FAIL
            QA_LOGBUFF="$QA_LOGBUFF"\\n"QA_FAIL:QA_SERVICECHECK:required service [$RS] not set to start automatically"
         fi
      fi
   fi

done



## Check SUDOers





# Report
ALIST="
OS_HOSTNAME
OS_NAME
OS_RELEASE
OS_TYPE
OS_RUNLEVEL
NET_DOMAIN
NET_DRIVER
NET_FQDN
NET_MAC_ADDR
NET_PUBIF
NET_PUBIP
HW_CLASS
HW_CPU_CACHEK
HW_CPU_CORES
HW_CPU_FAMILY
HW_CPU_NAME
HW_CPU_SOCKETS
HW_CPU_SPEED
HW_CPU_THREADS
HW_MEM_MB
HW_MEM_MODULES
HW_PRODUCT
HW_SERIAL
HW_STORAGE_DISKS
HW_STORAGE_GB
HW_VENDOR
"

CHECKLIST="
QA_AUTHCHECK
QA_NETCHECK
QA_DNSCHECK
QA_SCHEDCHECK
QA_SCOMCHECK
QA_KDUMPCHECK
QA_KERBEROSCHECK
QA_SATCHECK
QA_TIMECHECK
QA_SYSLOGCHECK
QA_SELINUXCHECK
QA_SERVICECHECK
"

#for ATTRIB in $ALIST; do
#   eval BUFF=\$$ATTRIB
#   echo "${ATTRIB}=${BUFF}"
#done

# Generate HTML

# Prepare the directory
if [[ ! -d $QA_DIR ]]; then
   /bin/mkdir -p $QA_DIR
fi

# Mount to the QA share if needed
if [[ -z `/bin/grep " $QA_DIR " "/etc/mtab"` ]]; then
   /bin/mount -o rw $QA_SHARE $QA_DIR
fi

# Prepare the archive directory
if [[ ! -d $QA_ARC ]]; then
   /bin/mkdir -p $QA_ARC
fi


# Delete any older QA's for this hostname
for QAF in `/bin/ls $QA_DIR | /bin/grep "^${OS_HOSTNAME}_.*.html"`; do
   #/bin/mv "${QA_DIR}/${QAF}" "${QA_ARC}/${QAF}"
   /bin/rm "${QA_DIR}/${QAF}"
done


echo "
<!DOCTYPE html>
<html>
<body>

<br><font size="6"><strong>QA Report for: $OS_NAME<strong></font><br>
Generated: `date` by $QA_USER
<br>
<br>
<strong>System Attributes:</strong>
<table border=\"1\" style=\"width:75%\">
   <tr>
      <th><strong>Attribute</strong></th>
      <th><strong>Value</strong></th>
   </tr>
" > $OUTFILE

for ATTRIB in $ALIST; do
   eval BUFF=\$$ATTRIB
   echo "   <tr>"
   echo "      <td>$ATTRIB</td>"
   echo "      <td>$BUFF</td>"
   echo "   </tr>"
done >> $OUTFILE

echo "
</table>
<br>
<br>
<strong>QA Check Results:</strong>
<table border=\"1\" style=\"width:50%\">
" >> $OUTFILE
CHECKCOUNT=0
PASSCOUNT=0
for CHECK in $CHECKLIST; do
   let CHECKCOUNT=$CHECKCOUNT+1
   eval BUFF=\$$CHECK
   if [[ $BUFF == FAIL ]]; then
      # Set the font color to red
      FC='red'
   else
      let PASSCOUNT=$PASSCOUNT+1
      # Set the font color to green
      FC='green'
   fi
   echo "   <tr>"
   echo "      <td><font color=\"$FC\">$CHECK</font></td>"
   echo "      <td>$BUFF</td>"
   echo "   </tr>"
done >> $OUTFILE

SCORE=`echo "scale=2;($PASSCOUNT/$CHECKCOUNT)*100" | bc | awk -F'.' '{print $1}'` >> $OUTFILE

echo -e "
</table>
<strong>Score: ${SCORE}%</strong>
<br>
<br>
<strong>QA Log:</strong>
<br>
<textarea cols="100" rows="8">
$QA_LOGBUFF
</textarea>

</body>
</html>
" >> $OUTFILE

/bin/cp $OUTFILE ${QA_ARC}/

echo "The QA Score for this system is ${SCORE}%"
echo "This QA record can be read from:"
echo "   [ https://${QA_SERVER}/pub/quality_assurance/archived/${OUTFILENAME} ]"

# Change directory to root
cd /

# Unmount the QA share
/bin/umount $QA_DIR

# Remove the script from rc.local if needed
sed -i "/`basename $0`/d" /etc/rc.local
exit

