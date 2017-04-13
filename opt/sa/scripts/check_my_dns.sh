#!/bin/bash

# Check to see if the server is correctly registered in DNS and register it if not.

SCRIPTDIR1=/opt/sa/scripts
DNSUPDATE=${SCRIPTDIR1}/update_dns.sh

source /opt/sa/scripts/.dnscheck.env

# Locate and source common_functions.sh
if [[ -s "${SCRIPTDIR1}/common_functions.sh" ]]; then
   source "${SCRIPTDIR1}/common_functions.sh"
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 255
fi

NET_PUBIF=`f_FindPubIF`
NET_PUBIP=`f_IPforIF $NET_PUBIF`

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
   DOMAIN=$DEFAULTDOMAIN
fi

# if the domain was set to reddog.microsoft.com, fix it 
if [[ "$DOMAIN" == "reddog.microsoft.com" ]]; then
   DOMAIN=$DEFAULTDOMAIN
fi

unset DNSCHECKFAIL
# Forward registration check
if [[ -z `/usr/bin/dig +short -t A ${UHNAME}.${DOMAIN} | /bin/grep $NET_PUBIP` ]]; then
   DNSCHECKFAIL=TRUE
fi

# Reverse registration check
if [[ -z `/usr/bin/dig +short -x $NET_PUBIP | /bin/grep "^${UHNAME}\."` ]]; then
   DNSCHECKFAIL=TRUE
fi

# Resolv.conf check
if [[ -z `grep ^search /etc/resolv.conf | egrep "${DEFAULTDOMAIN}"` ]]; then
   echo "Fixing resolv.conf"
   echo "search $SEARCHLIST" > /etc/resolv.conf
   for ns in $SERVERLIST; do
      echo "nameserver $ns" >> /etc/resolv.conf
   done
fi


if [[ -n $DNSCHECKFAIL ]]; then

   echo "`date`: Updating this system's hosts file..."
   # Remove any current entries to this systems's unqualified or fully qualified domain name from hosts
   sed -i.`date +%Y%m%d%H%M%S` "/[[:space:]]${UHNAME}\./d;/[[:space:]]${UHNAME}[[:space:]]/d" /etc/hosts
   # Add a new, correctly formatted hosts entry
   echo -e "${NET_PUBIP}\t${UHNAME}.${DOMAIN}\t${UHNAME}" >> /etc/hosts

   echo "`date`: Updating this system's DNS record..."
   RESPONSE=`$DNSUPDATE`
   SUCCESS=`echo $RESPONSE | awk -F'"success":' '{print $2}' | awk -F',' '{print $1}'`
   if [[ "$SUCCESS" == "true" ]]; then
      echo "`date`: Update succeeded!"
      exit 0
   else
      echo "`date`: Update failed."
      echo "Full output:"
      echo ""
      echo "$RESPONSE"
      exit 1
   fi

else
   echo "`date`: DNS record already up to date, nothing to do."
   exit 0
fi


