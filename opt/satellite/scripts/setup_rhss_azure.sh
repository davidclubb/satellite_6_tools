#!/bin/bash


# 2016 SDW
# This script is designed primarily to convert systems managed by RHSS 5 to RHSS 6
# It is designed to be run from the satellite itself to avoid the security risk and
# design work that would be required to execute it from the host itself - 
# i.e. creation of an API user, design of a security role, obfuscation of passwords etc...
# 
# This specific approach requires that a user with login and sudo rights be established
# on the remote host ahead of time and that a single SSH private key may be used
# to connect as that user and run commands.


#### BEGIN VARIABLE AND FUNCTION DEFS ####

# Read Satellite definitions and passwords from env file
. /opt/sa/scripts/.satapi.env

# make sure the satellite server is defined in /etc/hosts
if [[ -z `egrep '$RHSS' /etc/hosts` ]]; then
   echo "$RHSSIP   $RHSS" >> /etc/hosts
fi


APIPUT="curl -s -H Accept:application/json,version=2 -H Content-Type:application/json -X PUT -k -u ${USER}:${PASS}"
APIGET="curl -s GET -k -u ${USER}:${PASS}"

# Blacklist systems we don't want to accidentally modify.
BLACKLIST="
knerhsilp001
knerhsilp002
"

# Brief usage advice
f_Usage() {
   echo "Usage:"
   echo ""
   echo "$0"
   echo ""
   echo "OR"
   echo ""
   echo "$0 <tier> [<applicaton>] [<location>]"
   echo ""
   echo "WHERE"
   echo ""
   echo "application    The application name - this will be used to determine"
   echo "               the correct activation key, host group, and comment field."
   echo "               Currently recognized applications are SAP, ORACLEDB, and LEGACY."
   echo "               Any other value supplied will result in the use of a"
   echo "               default activation key and host group. In this case designated"
   echo "               as \"standard\"."
   echo "               Note: the LEGACY host groups are used to manage content hosts"
   echo "                     only.  No puppet configurations will be applied to hosts"
   echo "                     registered this way."
   echo ""
   echo "       tier    The tier is analagous to the product lifecycle.  Tier must be"
   echo "               provided as a single-letter abbreviation."
   echo "               I = Pilot"
   echo "               N = Non-Production"
   echo "               P = Production"
   echo ""
   echo "   location    This is an arbitrary field - as written here it does NOT correspond"
   echo "               with locations as defined in the Satellite.  It is only used to"
   echo "               modify the comment value of the host with a value used for reporting."
   echo ""
   

}

#### END VARIABLE AND FUNCTION DEFS ####


#### DISCOVERY INPUT AND VALIDATION ####

## Get hostname
HN=`hostname -f`
UHN=`hostname | awk -F'.' '{print $1}'`

if [[ `echo $HN | grep -o \\. | wc -l` -ge 2 ]]; then
   HN_FQDN=$HN
else
   # Need to find alternative source of FQDN
   HENT=$(getent hosts `hostname -s` | egrep -o -e '(\s|^)(\w*\.){2}\w*(\s|$)' | tr -d '[:space:]')
   if [[ `echo $HENT | grep -o \\. | wc -l` -ge 2 ]]; then
      HN_FQDN=$HENT
   fi
fi

# Determine domain
DEFAULT_DOMAIN=kiewitplaza.com

if [[ -z $HN_FQDN ]]; then
   #If we couldn't find an FQDN, then use the default domain
   DOMAIN=$DEFAULT_DOMAIN
   HN_FQDN="${UHN}.${DOMAIN}"
else
   DOMAIN=$(echo $HN_FQDN | sed "s/^${UHN}\.//")
fi

# Override invalid domains (Azure specifically)
DOL="reddog.microsoft.com"
for DO in $DOL; do

   if [[ "$DOMAIN" == "$DO" ]]; then
      DOMAIN=$DEFAULT_DOMAIN
   fi   

done

HOST=`echo $HN_FQDN | tr '[:upper:]' '[:lower:]' | tr -d '[;!@#$%^&*()+=|{}[] ]'`

# Validate the hostname of the remote host
# - Verify it is reachable via DNS
if [[ -z `getent hosts $HOST` ]]; then
   echo "Error: $HOST does not appear to be a valid hostname." 1>&2
   exit 1
fi

# - Sloppy way to enforce FQDN by looking for 2 dots in the string
if [[ $(echo $HOST | grep -o '\.' | wc -l) -ne 2 ]]; then
   echo "Error: $HOST is not a fully qualified hostname." 1>&2
   exit 2
fi
# - Make sure the hostname is not in the blacklist
for H in $BLACKLIST; do
   if [[ -n `echo $HOST | grep -i $H` ]]; then
      echo "Error: the host [$H] is blacklisted." 1>&2
      exit 3
   fi
done

# Determine release version
if [[ -z `cat /etc/redhat-release | grep '^Red Hat Enterprise Linux Server release'` ]]; then
   echo "Error: Unable to determine Red Hat Release version, exiting." 1>&2
   exit 5
fi

RELEASE=$(cat /etc/redhat-release | awk -F'release' '{print $2}' | awk '{print $1}' | awk -F'.' '{print $1}')

# Satellite 6 only supports RHEL 5, 6 and 7
if [[ $RELEASE -lt 5 ]] || [[ $RELEASE -gt 7 ]]; then
   echo "Error: Unsupported Red Hat Release version [$RELEASE]." 1>&2
   exit 6
fi

# Set variables based on release (different formats are required for string matching different elements)

keyos="rhel${RELEASE}"
hgos="RHEL ${RELEASE}"
envos="RHEL_${RELEASE}"

## Get tier

# - Prompt for tier if it wasnt provided on the command line
if [[ -n $1 ]]; then
   gTIER=$1
else
   #read -p "Select a tier (P=Prod/N=Non-Prod/I=Pilot): " gTIER
   echo "Error: Tier (P=Prod/N=Non-Prod/I=Pilot) must be provided on the command line."
   exit 20
fi

## Check tier

# Santitize user input
TIER=`echo $gTIER | tr '[:lower:]' '[:upper:]' | tr -d '[;!@#$%^&*()+=|{}[] ]' | cut -c1`

# Set variables based on tier - particularly we need to set the name of the puppet environment
# and the strings used to match the activation key and host group.
case $gTIER in

   p|P ) TIER=prod
         HGTIER="Production"
         ENVTIER="Prod"
         # This one is a little sloppy because we're hard-coding the exclusion of "Non".  This is only necessary
         # because "Prod" matches the lifecycle environment "Non-Prod" otherwise.
         #PUPPETENV=$( hammer -u $USER -p $PASS environment list | grep "_${ENVTIER}_" | grep -v "Non" | grep "$envos" | awk '{print $NF}')
         PUPPETENV=$( $APIGET https://${SATELLITE}/api/environments | sed 's/"/ /g' | grep -o "\w*_${ENVTIER}_${envos}_*\w*" | grep -v "Non_Prod" )
         ;;
   n|N ) TIER=nonprod
         HGTIER="Non-Production"
         ENVTIER="Non_Prod"
         #PUPPETENV=$( hammer -u $USER -p $PASS environment list | grep "_${ENVTIER}_" | grep "$envos" | awk '{print $NF}')
         PUPPETENV=$( $APIGET https://${SATELLITE}/api/environments | sed 's/"/ /g' | grep -o "\w*_${ENVTIER}_${envos}_*\w*" )
         ;;
   i|I ) TIER=pilot
         HGTIER="Pilot"
         ENVTIER="Pilot"
         #PUPPETENV=$( hammer -u $USER -p $PASS environment list | grep "_${ENVTIER}_" | grep "$envos" | awk '{print $NF}')
         PUPPETENV=$( $APIGET https://${SATELLITE}/api/environments | sed 's/"/ /g' | grep -o "\w*_${ENVTIER}_${envos}_*\w*" )
         ;;
     * ) echo "[$gTIER] is not a valid tier." 1>&2
         exit 7
         ;;
esac

## Get type
# - Prompt for type if not given on the command line
if [[ -n $2 ]]; then
   gTYPE=$2
else
   #read -p "Select an application (SAP|ORACLEDB|LEGACY|OTHER) [or leave blank]: " gTYPE
   gTYPE=Generic
fi

## Check type

# Santitize user input
TYPE=`echo $gTYPE | tr '[:lower:]' '[:upper:]' | tr -d '[;!@#$%^&*()+=|{}[] ]'`

# Default application type is standard
#APP=standard

case $TYPE in
        SAP ) APP=sap
              HGAPP="SAP"
               ;;
   ORACLEDB ) APP=oracledb
              HGAPP="Oracle DB"
              ;;
     LEGACY ) APP=legacy
              HGAPP="Legacy"
              ;;
          * ) APP=standard
              HGAPP="Standard"
              ;;
esac

# Get location
# - Prompt for it if not provided on the command line
if [[ -n $3 ]]; then
   gLOC=$3
else
   #read -p "Please provide a location. (ex. KHONESTD|KHONEMDC|AZURE): " $gLOC
   gLOC=AZURE
fi

# Santitize user input
LOC=`echo $gLOC | tr '[:lower:]' '[:upper:]' | tr -d '[;!@#$%^&*()+=|{}[] ]'`

#### END USER INPUT AND VALIDATION ####


#### BEGIN CONTEXTUAL VARIABLE SETTING ####


## Construct Activation Key Name from input
AK="1-${keyos}-${TIER}-${APP}"

# Verify activation key exists
#if [[ -z `hammer -u $USER -p $PASS activation-key list --organization-id=$ORGID | awk '{print $3}' | grep "^${AK}$"` ]]; then
if [[ -z `$APIGET https://${SATELLITE}/katello/api/organizations/$ORGID/activation_keys | grep "\"name\":\"$AK\""` ]]; then
   echo "Error: Activation key [$AK] is invalid. This means there is an error in the script or the key has been deleted."
   exit 5
fi

# Get the hostgroup ID based on selections
# Assumes the host group must be named "$hgos $HGAPP $HGTIER"
#
# Example: "RHEL 6 Standard Prod"
#
#echo "hammer -u $USER -p $PASS hostgroup list | grep \"$hgos $HGAPP $HGTIER\" | awk '{print $1}' )"
#HGID=$( hammer -u $USER -p $PASS hostgroup list | grep "$hgos $HGAPP $HGTIER" | awk '{print $1}' )
HGID=$( $APIGET  https://${SATELLITE}/api/hostgroups?per_page=1000 | sed 's/"id":/\n/g' | grep "$hgos $HGAPP $HGTIER" | awk -F',' '{print $1}' )

# $APIGET https://${SATELLITE}/api/hostgroups | sed 's/"name":/\n/g' | awk -F',' '{print $1}' | grep ^\" | tr -d '"'

#echo "hammer -u $USER -p $PASS hostgroup list | grep "$hgos $HGAPP $HGTIER" | awk '{print $1}'"
if [[ -z $HGID ]]; then
   echo "Error: no Host Group exists for [ $hgos $HGAPP $HGTIER ]. The host group may have been deleted or not created yet."
   exit 7
fi

# Set the host group name based on the ID
#HGNAME=$( hammer -u $USER -p $PASS hostgroup info --id $HGID | grep "^Name:" | sed -e "s/^Name:[[:space:]]*//" )
HGNAME=$( $APIGET  https://${SATELLITE}/api/hostgroups?per_page=1000 | sed 's/"id":/\n/g' | grep "$hgos $HGAPP $HGTIER" | awk -F'"name":"' '{print $2}' | awk -F'"' '{print $1}' )


#### END CONTEXTUAL VARIABLE SETTING ####

# Explain what we're about to do
echo "Preparing to manage host with the following details:"
echo "FQDN: $HOST"
echo "TIER: $HGTIER"
echo "TYPE: $HGAPP"
echo "Activation Key: $AK"
echo "Hostgroup Name: $HGNAME"
echo "Puppet Environment: $PUPPETENV"

if [[ -z $PUPPETENV ]]; then
   echo "Failed to determine puppet environment."
   exit
fi

#echo ""
#read -p "Does the information above look correct? (Enter to continue, Ctrl+C to quit): " JUNK

#### BEGIN HOST MANAGEMENT ####

## Remove OLD Satellite 5 configuration

# Hard-coded fix for an issue that may be specific to my environment
# - Several systems had nss.i686 but not p11-kit-trust.i686 - this caused the CA update to abort
#   This fix instructs the system to attempt installing the latter package prior to removing
#   RHN classic management.  If the system doesn't have a working repository, this will fail.
if [[ -n `yum list nss.i686 2>&1 | grep "Installed"` ]]; then
   if [[ -z `yum list p11-kit-trust.i686 2>&1 | grep "Installed"` ]]; then
      echo "Attempting to reconcile crypto prior to installation"
      yum -y install p11-kit-trust.i686
   fi
fi


# Remove RHN Classic RPMS
RHNRPMS="
osad
rhncfg
rhncfg-actions
rhncfg-client
rhncfg rhnlib
rhn-check
rhn-client-tools
rhnlib
rhnsd
rhnsd.x86_64
rhn-setup
rhn-setup-gnome
yum-rhn-plugin
"
for pkg in $RHNRPMS; do
   rpm -e $pkg --nodeps 2>&1 | grep -v 'not installed'
done

# Empty all cached info in YUM
yum clean all 2>&1 | > /dev/null

## Remove OLD Satellite 6 configuration
# This is useful if the system is being migrated from another Satellite 6, or if it is
# necessary to re-register it cleanly.

# Empty out subscription manager
subscription-manager clean 2>&1 | > /dev/null

# Remove SAT6 management RPMs
KCRPM=`rpm -qa | grep katello-ca-consumer`
for pkg in puppet facter katello-agent $KCRPM; do
   rpm -e $pkg --nodeps 2>&1 | > /dev/null
done

# Clean existing puppet/facter cache and config
# - Had several systems that had been managed by another puppet master
#   once upon a time - the remnants of those installations caused conflicts
#for d in /etc/puppet /var/lib/puppet /etc/puppetlabs /etc/facter; do
for d in /etc/puppet /etc/puppetlabs /etc/facter; do
   if [[ -d $d ]]; then 
      /bin/rm -rf $d
   fi
done

## Install management software
#  Since these systems will not likely have access to Satellite 6 rpms via yum
#  packages required to install subscription-manager have been placed on the satellite in /var/www/html/pub
#  and symlinked with "latest" in place of the actual version number.  These will have
#  to be placed on the satellite and symlinked manually for this next process to work.

# Set the name of latest Subscription Manager RPMs based on release 
PYSMRPM=python-rhsm-latest.el${RELEASE}.x86_64.rpm
SMRPM=subscription-manager-latest.el${RELEASE}.x86_64.rpm

# Some additional RPMs that I've only seen required to manage RHEL 5
if [[ $RELEASE == 5 ]]; then
   if [[ -z $( rpm -qa virt-what ) ]]; then
      rpm -Uvh http://${RHSS}/pub/virt-what-latest.el5.x86_64.rpm | sed "s/^/$HOST: /g"
   fi
   if [[ -z $( rpm -qa python-dateutil ) ]]; then
      rpm -Uvh http://${RHSS}/pub/python-dateutil-latest.el5.noarch.rpm | sed "s/^/$HOST: /g"
   fi
fi

# Install the basic subscription manager RPMs directly from the satellite web server
if [[ -z $( rpm -qa python-rhsm ) ]]; then
   rpm -Uvh http://${RHSS}/pub/$PYSMRPM | sed "s/^/$HOST: /g"
fi
if [[ -z $( rpm -qa subscription-manager ) ]]; then
   rpm -Uvh http://${RHSS}/pub/$SMRPM | sed "s/^/$HOST: /g"
fi


# Install CA certs from Satellite 6
#$SSHCOMM ${SSHUSER}@${HOST} sudo yum -y localinstall http://${RHSS}/pub/katello-ca-consumer-latest.noarch.rpm | sed "s/^/$HOST: /g"
rpm --force -Uvh http://${RHSS}/pub/katello-ca-consumer-latest.noarch.rpm | sed "s/^/$HOST: /g"

## FQDN Workaround
# The satellite doesn't correctly handle systems which do not use FQDN for the internal hostname
# The systems will show up multiple times under hosts and content hosts and neither will be valid.
# This workaround checks to see if the internal hostname is FQDN - if not the internal hostname
# is temporarily set to the FQDN while the system is registered.  It will be set back afterward.
if [[ `hostname` != `hostname -f` ]]; then
   OHN=`hostname`
   FHN=`hostname -f`
   echo "$HOST does not use FQDN for hosthame. Temporarily changing the hostname from [$OHN] to [$FHN]"
   hostname $FHN | sed "s/^/$HOST: /g"
fi

# Register with Satellite 6
subscription-manager register --org="$ORG" --activationkey="${AK}" --name="`hostname -f`" --force | sed "s/^/$HOST: /g"

# Write the activation key name to the filesystem (this is not actually used by the satellite - this is part of my specific QA processes)
echo $AK > /root/activationkey

# Get the host ID for the newly registered host from the Satellite
HOSTID=$( $APIGET https://${SATELLITE}/api/hosts/${HOST} | awk -F"\"name\":\"${HOST}\",\"id\":" '{print $2}' | awk -F',' '{print $1}' )

# Format the comment field to contain description data - this is not actually used by the satellite - it is part of my specifc QA process)
if [[ "$TIER" == "prod" ]]; then
   cTIER=Production
else
   cTIER=Non-Production
fi

COMMENT="${LOC}:${TYPE}:${cTIER}" 

# Put the host in the correct host group, set proxy address, add location
if [[ -n $HOSTID ]] && [[ -n $HGID ]]; then
   $APIPUT -d "{\"host\":{\"comment\":\"${COMMENT}\", \"hostgroup_id\":$HGID, \"puppet_ca_proxy_id\":1}}" https://${SATELLITE}/api/hosts/${HOSTID}

else
   echo "Unable to determine HOSTID or HOST Group ID"
   exit 12
fi

## Check for an existing puppet cert for this host and revoke it if found
## (This is important for re-installs, etc...)
#if [[ -n `puppet cert list $HOST 2>&1 | grep "^+"` ]]; then
#   puppet cert clean $HOST
#fi

# Install katello agent and puppet
yum -y install katello-agent puppet | sed "s/^/$HOST: /g"

# Reconcile katello agent
/usr/sbin/katello-package-upload | sed "s/^/$HOST: /g"

# Configure puppet agent 
PUPCONF=/etc/puppet/puppet.conf
sed -i '/^server/d;/^environment/d' $PUPCONF
echo "environment=${PUPPETENV}"  >> $PUPCONF
echo "server=${RHSS}" >> $PUPCONF
puppet agent --test 

# Set the puppet daemon to run automatically
if [[ $RELEASE -le 6 ]]; then
   /sbin/chkconfig puppet on | sed "s/^/$HOST: /g"
   /etc/init.d/puppet start | sed "s/^/$HOST: /g"
elif [[ $RELEASE -eq 7 ]]; then
   hostnamectl set-hostname ${HOST}
   systemctl enable puppet
   systemctl start puppet
fi
# If the hostname had to be changed to FQDN earlier, change it back now
if [[ -n $OHN ]]; then
   echo "Setting the internal hostname for $HOST back to [$OHN]"
   hostname $OHN
   if [[ $RELEASE -eq 7 ]]; then
      hostnamectl set-hostname ${OHN}
   fi
fi
