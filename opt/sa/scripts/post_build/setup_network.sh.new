#!/bin/bash
#set -x

###################################################
# setup_network.sh
# Purpose: sets up the network for a newly imaged
#          or moved server.
# re-written 2012/06/06 SDW


##################VARIABLE DEFINITIONS#############
RETCODE=0
SCRIPTDIR1=/opt/sa/scripts/post_build
SCRIPTDIR2=.

NODES=${SCRIPTDIR1}/nodes
# Locate the "Configure Interface" script
#configure_net_interface.sh <Interface> <NEW IPv4 ADDRESS> <NEW IPv4 GATEWAY> <NEW IPv4 NETMASK>
if [[ -s "${SCRIPTDIR1}/configure_net_interface.sh" ]]; then
   CFGINT="${SCRIPTDIR1}/configure_net_interface.sh"
elif [[ -s "${SCRIPTDIR2}/configure_net_interface.sh" ]]; then
   CFGINT="${SCRIPTDIR2}/configure_net_interface.sh"
else
   echo "Critical dependency failure: unable to locate configure_net_interface.sh"
   exit 5
fi

# Locate and source common_functions.h
if [[ -s "/opt/sa/scripts/common_functions.sh" ]]; then
   source "/opt/sa/scripts/common_functions.sh"
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 5
fi


#####################MAIN EXECUTION START###################

# Read current system values

PIP=`f_FindPubIP`
if [[ $PIP != FAILURE ]] && [[ -n $PIP ]]; then
   if [[ -n `ifconfig -a | grep $PIP | grep 'Mask:'` ]]; then
      PNM=`ifconfig -a | grep $PIP | awk -F'Mask:' '{print $NF}' | head -1`
   elif [[ -n `ifconfig -a | grep $PIP | grep 'netmask'` ]]; then
      PNM=`ifconfig -a | grep $PIP | awk '{print $4}'`
   fi
   #PGW=`echo $PIP | awk -F'.' '{print $1"."$2"."$3".1"}'`
   PGW=`f_FindDefaultGW`
fi
PUBIF=`f_FindPubIF`
if [[ $PUBIF == FAILURE ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Error: failed to identify public network interface - is the NIC active?" | $LOG1
      exit 9
   else
      unset PUBIF
      export PUBIF=`f_AskPubIF`
   fi
fi

# Initially set "New" values based on "Present" Values.
NIP=$PIP
NNM=$PNM
NGW=$PGW

## Hostname

# First try the nodes file

if [[ -s $NODES ]]; then
   # Find the hostname and domain from the nodelist via the MAC
   MAC=`/sbin/ifconfig $PUBIF | /bin/grep -i 'HWaddr' | /bin/awk '{print $5}'`
   NHN=`/bin/grep -i "^${MAC}," $NODES | awk -F',' '{print $2}'`
   DOMAIN=`/bin/grep -i "^${MAC}," $NODES | awk -F',' '{print $3}'`
   # Check for manual settings
   MIP=`/bin/grep -i "^${MAC}," $NODES | awk -F',' '{print $5}'`
   if [[ -n $MIP ]]; then
      NIP=$MIP
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0 Info: IP address manually set to [$NIP] by nodes file." | $LOG1
      else
         echo "IP address manually set to [$NIP] by nodes file."
      fi
   fi
   
   MNM=`/bin/grep -i "^${MAC}," $NODES | awk -F',' '{print $6}'`
   if [[ -n $MNM ]]; then
      NNM=$MNM
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0 Info: Netmask manually set to [$NNM] by nodes file." | $LOG1
      else
         echo "Netmask manually set to [$NNM] by nodes file."
      fi
   fi

   MGW=`/bin/grep -i "^${MAC}," $NODES | awk -F',' '{print $7}'`
   if [[ -n $MGW ]]; then
      NGW=$MGW
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0 Info: Gateway manually set to [$NGW] by nodes file." | $LOG1
      else
         echo "Gateway address manually set to [$NGW] by nodes file."
      fi
   fi

   
fi

# Next try DNS
if [[ $PIP != FAILURE ]] && [[ -z $NHN ]]; then
   NHN=`/usr/bin/dig -x $PIP +short | awk -F'.' '{print $1}'`
fi

# Next try to set it based on the local system values
if [[ -z $NHN ]]; then
   NHN=`hostname | awk -F'.' '{print $1}'`
fi

if [[ $PIP != FAILURE ]] && [[ -n `echo $NHN | egrep -i 'unnamed|setup000|localhost'` ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Error: [$NHN] is an invalid host name, aborting network configuration" | $LOG1
   else
      echo "Error: [$NHN] is an invalid host name, aborting network configuration"
   fi
   exit 10
fi

# Set the domain name
# if there are fewer than two dots in the hostname, assume it's unqualified
if [[ `hostname | grep -o '\.' | wc -l` -lt 2 ]]; then
   UHNAME=`hostname`
else
   FQDN=`hostname`
   UHNAME=`echo $FQDN | awk -F'.' '{print $1}'`
   DOMAIN=`echo $FQDN | sed "s/^${UHNAME}\.//" | tr '[:upper:]' '[:lower:]'`
fi

# if the domain wasn't set by the above command check /etc/sysconfig/network
if [[ -z $DOMAIN ]]; then
   if [[ `grep '^HOSTNAME=' /etc/sysconfig/network | awk -F'=' '{print $2}' | grep -o '\.' | wc -l` -eq 2 ]]; then
      FQDN=`grep '^HOSTNAME=' /etc/sysconfig/network | awk -F'=' '{print $2}'`
      DOMAIN=`echo $FQDN | sed "s/^${UHNAME}\.//" | tr '[:upper:]' '[:lower:]'`
   fi
fi

# if the domain wasn't set by the above command check /etc/hosts
if [[ -z $DOMAIN ]]; then
   for e in `grep "^$myip" /etc/hosts | grep ${UHNAME} | sed "s/^${myip}//;s/${UHNAME}//g"`; do
      if [[ `echo $e | grep -o '\.' | wc -l` -eq 2 ]]; then
         DOMAIN=`echo $e | sed "s/^\.//" | tr '[:upper:]' '[:lower:]'`
      fi
   done
fi

# if the domain wasn't set by any of the above, default
if [[ -z $DOMAIN ]]; then
   DOMAIN=acmeplaza.com
fi


# If the hostname exists in DNS use the DNS IP address
# This may not be desired as it will override the nodes file
# but it will force people to keep DNS accurate

DNSIP=`/usr/bin/dig +short -t a ${NHN}.${DOMAIN}`
if [[ -n $DNSIP ]] && [[ "$DNSIP" != "$NIP" ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Warning: [$NHN] is listed in DNS with a different IP [$DNSIP]. The DNS information will be used." | $LOG1
   else
      echo "Warning: [$NHN] is listed in DNS with a different IP [$DNSIP]. The DNS information will be used."
   fi

   #Check to see if the gateway is still relevant
   PFX=`/bin/ipcalc -p $NIP $NNM | awk -F'=' '{print $2}'`
   NWA=`/bin/ipcalc -n $NIP $NNM | awk -F'=' '{print $2}'`

   if [[ `f_IsIPInCIDR ${NWA}/${PFX} $DNSIP` == 0 ]]; then
      # The IP in DNS has the same netmask and GW as the current one
      NIP=$DNSIP
   else
      # The IP in DNS has a different netmask and GW from current one
      # Assume a /24 - this is the highest probability for success
      NGW=`echo $DNSIP | awk -F'.' '{print $1"."$2"."$3".1"}'`
      NNM=255.255.255.0
      NIP=$DNSIP
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`:$0 Warning: Gateway manually adjusted to [$NGW]. If this is incorrect, fix the IP in DNS." | $LOG1
         echo "`$VTS`:$0 Warning: Netmask manually adjusted to [$NNM]. If this is incorrect, fix the IP in DNS." | $LOG1
      else
         echo "Warning: Gateway manually adjusted to [$NGW]. If this is incorrect, fix the IP in DNS." | $LOG1
         echo "Warning: Netmask manually adjusted to [$NNM]. If this is incorrect, fix the IP in DNS." | $LOG1
      fi

   fi
fi

# Generate a static IP configuration based on DHCP information

#$CFGINT $PUBIF $PIP $PGW $PNM
$CFGINT $PUBIF $NIP $NGW $NNM
RETCODE=$?
if [[ $RETCODE != 0 ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Error: the command \`$CFGINT $PUBIF $PIP $PGW $PNM\` has failed with [$RETCODE]" | $LOG1
      exit
   else
      echo "FAILURE: the command:"
      echo "   \`$CFGINT $PUBIF $PIP $PGW $PNM\`"
      echo "   has failed.  Please investigate and try again."
   fi
   exit $RETCODE
else
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Info: the command \`$CFGINT $PUBIF $PIP $PGW $PNM\` has succeeded" | $LOG1
   fi
fi

#/etc/init.d/network restart
RETCODE=$?

if [[ $RETCODE != 0 ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0 Error: network failed to restart exit code [$RETCODE]" | $LOG1
   else
      echo "FAILURE: Error Restarting Network"
   fi
   exit $RETCODE
fi


##Changing the hostname
#
# Remove any existing refrences to the hostname in the hosts file
if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
   echo "`$VTS`:$0 Info: updating /etc/hosts" | $LOG1
fi

sed -i.`date +%Y%m%d%H%M%S` "/[[:space:]]${NHN}[[:space:]]/d;/[[:space:]]${NHN}$/d;/[[:space:]]${NHN}\./d;/^${NIP}/d" /etc/hosts


# Add a single, correctly formatted entry
echo "$NIP	${NHN}.${DOMAIN} $NHN" >> /etc/hosts

# Shorten the hostname per SAP requirements
sed -i '/^HOSTNAME=/s/\..*//' /etc/sysconfig/network
hostname $NHN

# make sure localhost is defined in /etc/hosts
if [[ -z `grep "^127.0.0.1" /etc/hosts` ]]; then
   echo "Adding localhost to /etc/hosts"
   #echo '127.0.0.1 localhost localhost.localdomain' >> /etc/hosts
   echo '127.0.0.1 localhost.localdomain localhost' >> /etc/hosts
else
   sed -i 's/^127.0.0.1.*/127.0.0.1\tlocalhost.localdomain localhost/' /etc/hosts
fi

sed -i "s/^::1.*/::1\tlocalhost6.localdomain6 localhost6/" /etc/hosts

# make sure the satellite server is defined in /etc/hosts
if [[ -z `egrep 'knerhsilp002' /etc/hosts` ]]; then
   echo "10.251.13.36	knerhsilp002.acmeplaza.com" >> /etc/hosts
fi

#Drop a stop file in /etc/ to indicate that the network was successfully set up
#This will prevent the "fix_profile" script from removing the directives from
#root's profile if something went wrong.
if [[ $RETCODE == 0 ]]; then
   touch /etc/setup_net_complete
   #echo "Network setup is complete."
else
   exit $RETCODE
fi
