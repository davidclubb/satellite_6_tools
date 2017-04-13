#!/bin/bash

# Deprecated !
echo "This script has been deprecated, use Satellite 6"
exit

if [[ -n `hostname | grep -i knerhsilp` ]] || [[ -n `ip addr | grep '10.252.14.5/'` ]]; then 
   echo "Don't run this from the satellite!"
   exit
fi

# Include common_functions.h
SCRIPTDIR1=/var/satellite/post_scripts/

# Locate and source common_functions.h
if [[ -s "${SCRIPTDIR1}/common_functions.sh" ]]; then
   source "${SCRIPTDIR1}/common_functions.sh"
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 255
fi

SSDNSNAME=knerhsilp001.acmeplaza.com

# Get distro and release
DISTRO=`f_GetRelease | awk '{print $1}'`
RELEASE=`f_GetRelease | awk '{print $2}'`


if [[ "$DISTRO" != "RHEL" ]]; then
   echo "Error: Only Red Hat Enterprise Server is supported."
   exit 3
fi

if [[ $RELEASE -lt 5 ]] || [[ $RELEASE -gt 7 ]]; then
   echo "Error: $DISTRO $RELEASE is not a supported release."
   exit 4
fi

# Set key prefix

case $RELEASE in

   5 ) KEYPREFIX=1-rhel5
       ;;
   6 ) KEYPREFIX=1-rhel6
       ;;
   7 ) KEYPREFIX=1-rhel7
       ;;
   * ) echo "Error: unsupported release"
       exit 5
       ;;
esac

# Set key suffix
GBU=$1

case $GBU in

        SAP ) KEYSUFFIX=SAP
              ;;
   ORACLEDB ) KEYSUFFIX=oracledb
              ;;
     LEGACY ) KEYSUFFIX=legacy
              ;;
          * ) KEYSUFFIX=standard
              ;;
esac

ACTIVATIONKEY=${KEYPREFIX}-${KEYSUFFIX}

# Determine profile name - basically the simple hostname

PROFILENAME=`hostname | awk -F'.' '{print $1}' | tr '[:upper:]' '[:lower:]'`

#### KEYS ####

# Install the SSL certificate from the satellite server
/usr/bin/wget -q --no-check-certificate https://${SSDNSNAME}/pub/RHN-ORG-TRUSTED-SSL-CERT -O /usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT

# Use the SSL cert for the rhn agent
/bin/sed 's/RHNS-CA-CERT/RHN-ORG-TRUSTED-SSL-CERT/g' -i /etc/sysconfig/rhn/up2date

# Create a backup of all imported RPM GPG keys
for pk in `/bin/rpm -qa gpg-pubkey*`; do /bin/rpm -qi $pk; done > /root/rpmpubkey.bak.`date +%Y%m%d%H%M%S`

# Remove all existing RPM GPG keys
for pk in `/bin/rpm -qa gpg-pubkey*`; do /bin/rpm -e $pk; done

# Install the RPM signing key matching this release from the satellite server
rpm --import http://${SSDNSNAME}/pub/RPM-GPG-KEY-redhat-release-${RELEASE}
#/bin/rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

# Install the satellite custom signing key
/bin/rpm --import http://${SSDNSNAME}/pub/ACME-RHSS-GPG-KEY

# Set the address of the satellite server for the rhn agent
/bin/sed "s/xmlrpc.rhn.redhat.com/${SSDNSNAME}/g" -i /etc/sysconfig/rhn/up2date

# Change the frequency of rhn agent check-in to the minimum of 60 minutes
sed -i "s/INTERVAL=.*/INTERVAL=60/" /etc/sysconfig/rhn/rhnsd

# Disable any existing repositories
for REPO in `/bin/ls /etc/yum.repos.d | grep "\.repo$"`; do
   /bin/mv /etc/yum.repos.d/${REPO} /etc/yum.repos.d/${REPO}.`date +%Y%m%d%H%M%S`
done


# Restart the rhn agent after reconfiguration
/etc/init.d/rhnsd restart

# Allow the satellite server to perform all actions via the agent
mkdir -p /etc/sysconfig/rhn/allowed-actions/script
touch /etc/sysconfig/rhn/allowed-actions/script/run
mkdir -p /etc/sysconfig/rhn/allowed-actions/configfiles
touch /etc/sysconfig/rhn/allowed-actions/configfiles/all

# Install public key(s) for custom channels
/bin/rpm --import http://knerhsilp001.acmeplaza.com/pub/ACME-RHSS-GPG-KEY


# Registration
echo "Beginning registration process, this may take several seconds."
/usr/sbin/rhnreg_ks --force --profilename=${PROFILENAME} --serverUrl=https://${SSDNSNAME}/XMLRPC --sslCACert=/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT --activationkey=${ACTIVATIONKEY}
RESULT=$?

if [[ $RESULT == 0 ]]; then
   echo "Registration succeeded."
   if [[ -x /usr/bin/rhn-actions-control ]]; then
      /usr/bin/rhn-actions-control --enable-all
   fi
   echo "${ACTIVATIONKEY}" > /root/activationkey
else
   echo "Registration unsuccessful."
fi
