#!/bin/bash

# Updates the server's own DNS record
# As of 04-05-2016 this script is still a work in progress - infrastructure pieces are not yet functional

# Include common_functions.h
SCRIPTDIR1=/opt/sa/scripts/

# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.sh" ]]; then
   source "${SCRIPTDIR1}/common_functions.sh"
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 255
fi

#read -p "Please provide a domain user with rights to update DNS: " gapiuser
#
#if [[ -n "$gapiuser" ]]; then
#   apiuser=$gapiuser
#else
#   echo "A user with sufficent credentials is required. Aborting."
#   exit 2
#fi

apiuser=automation.dnsclient
apipass=LookForMe53

apiurl=https://kneschiwp001.acmeplaza.com/dnsapi/v1/
myip=`f_FindPubIP`

# if there are fewer than two dots in the hostname, assuem it's unqualified
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

# if the domain wasn't set by any of the above default
if [[ -z $DOMAIN ]]; then
   DOMAIN=acmeplaza.com
fi

# if the domain was set to reddog.microsoft.com, fix it
if [[ "$DOMAIN" == "reddog.microsoft.com" ]]; then
   DOMAIN=acmeplaza.com
fi

# Make sure we're not doing something stupid
if [[ "$UHNAME" == "localhost" ]] || [[ "$UHNAME" == "localhost.localdomain" ]] || [[ "$UHNAME" == "rhel6-hyperv" ]] || [[ "$UHNAME" == "rhel6-temp" ]] || [[ "$DOMAIN" == "localdomain" ]]; then
   echo "Failure: You must name this system before attempting to update DNS."
   exit
fi

curl -k -X POST --form "action=update_dns" --form "domain=$DOMAIN" --form "recType=A" --form "recName=$UHNAME" --form "recValue=$myip" --user ${apiuser}:${apipass} $apiurl

#echo ""
#echo curl -k -X POST --form "action=update_dns" --form "domain=$DOMAIN" --form "recType=A" --form "recName=$UHNAME" --form "recValue=$myip" --user ${apiuser}:${apipass} $apiurl
