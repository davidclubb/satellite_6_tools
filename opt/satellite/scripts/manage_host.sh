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
. /opt/satellite/scripts/.sat.env


# SSH variables for connecting to the remote host
SSHUSER=unixpa
SSHKEY=/root/.upak
SSHCOMM="/usr/bin/ssh -q -o stricthostkeychecking=no -o userknownhostsfile=/dev/null -o batchmode=true -i $SSHKEY"

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
   echo "$0 <hostname> <tier> [<applicaton>] [<location>]"
   echo ""
   echo "WHERE"
   echo ""
   echo "   hostname    The FQDN for the system you want to manage."
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


#### BEGIN USER INPUT AND VALIDATION ####

## Get hostname
# - Prompt for it if it wasn't provided
if [[ -z $1 ]]; then
   read -p "Provide the hostname you want to manage (fqdn): " gRHOST
else
   gRHOST=$1
fi

## Check hostname
# Santitize user input
RHOST=`echo $gRHOST | tr '[:upper:]' '[:lower:]' | tr -d '[;!@#$%^&*()+=|{}[] ]'`

# Validate the hostname of the remote host
# - Verify it is reachable via DNS
if [[ -z `getent hosts $RHOST` ]]; then
   echo "Error: $RHOST does not appear to be a valid hostname." 1>&2
   exit 1
fi

# - Sloppy way to enforce FQDN by looking for 2 dots in the string
if [[ $(echo $RHOST | grep -o '\.' | wc -l) -ne 2 ]]; then
   echo "Error: $RHOST is not a fully qualified hostname." 1>&2
   exit 2
fi
# - Make sure the hostname is not in the blacklist
for H in $BLACKLIST; do
   if [[ -n `echo $RHOST | grep -i $H` ]]; then
      echo "Error: the host [$H] is blacklisted." 1>&2
      exit 3
   fi
done

# See if we can connect via SSH
$SSHCOMM ${SSHUSER}@${RHOST} /bin/true
RETCODE=$?
if [[ "$RETCODE" != "0" ]]; then
   echo "Error connecting to $RHOST via SSH.  Please make sure $SSHUSER exists on that system and that its public key is in the authorized keys file." 1>&2
   exit $RETCODE
else
   # See if we can sudo via SSH
   ANSWER=$($SSHCOMM ${SSHUSER}@${RHOST} sudo -n whoami)
   if [[ "$ANSWER" != "root" ]]; then
      echo "Unable to issue commands via SUDO on $RHOST" 1>&2
      exit 4
   fi
fi

# Determine release version
if [[ -z `$SSHCOMM ${SSHUSER}@${RHOST} cat /etc/redhat-release | grep '^Red Hat Enterprise Linux Server release'` ]]; then
   echo "Error: Unable to determine Red Hat Release version, exiting." 1>&2
   exit 5
fi

RELEASE=$( $SSHCOMM ${SSHUSER}@${RHOST} cat /etc/redhat-release | awk -F'release' '{print $2}' | awk '{print $1}' | awk -F'.' '{print $1}')

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
if [[ -n $2 ]]; then
   gTIER=$2
else
   read -p "Select a tier (P=Prod/N=Non-Prod/I=Pilot): " gTIER
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
         PUPPETENV=$( hammer -u $USER -p $PASS environment list | grep "_${ENVTIER}_" | grep -v "Non" | grep "$envos" | awk '{print $NF}')
         ;;
   n|N ) TIER=nonprod
         HGTIER="Non-Production"
         ENVTIER="Non_Prod"
         PUPPETENV=$( hammer -u $USER -p $PASS environment list | grep "_${ENVTIER}_" | grep "$envos" | awk '{print $NF}')
         ;;
   i|I ) TIER=pilot
         HGTIER="Pilot"
         ENVTIER="Pilot"
         PUPPETENV=$( hammer -u $USER -p $PASS environment list | grep "_${ENVTIER}_" | grep "$envos" | awk '{print $NF}')
         ;;
     * ) echo "[$gTIER] is not a valid tier." 1>&2
         exit 7
         ;;
esac

## Get type
# - Prompt for type if not given on the command line
if [[ -n $3 ]]; then
   gTYPE=$3
else
   read -p "Select an application (SAP|ORACLEDB|LEGACY|OTHER) [or leave blank]: " gTYPE
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
if [[ -n $4 ]]; then
   gLOC=$4
else
   read -p "Please provide a location. (ex. KHONESTD|KHONEMDC|AZURE): " $gLOC
fi

# Santitize user input
LOC=`echo $gLOC | tr '[:lower:]' '[:upper:]' | tr -d '[;!@#$%^&*()+=|{}[] ]'`

#### END USER INPUT AND VALIDATION ####


#### BEGIN CONTEXTUAL VARIABLE SETTING ####


## Construct Activation Key Name from input
AK="1-${keyos}-${TIER}-${APP}"

# Verify activation key exists
if [[ -z `hammer -u $USER -p $PASS activation-key list --organization=$ORG | awk '{print $3}' | grep "^${AK}$"` ]]; then
   echo "Error: Activation key [$AK] is invalid. This means there is an error in the script or the key has been deleted."
   exit 5
fi

# Get the hostgroup ID based on selections
# Assumes the host group must be named "$hgos $HGAPP $HGTIER"
#
# Example: "RHEL 6 Standard Prod"
#
HGID=$( hammer -u $USER -p $PASS hostgroup list | grep "$hgos $HGAPP $HGTIER" | awk '{print $1}' )
if [[ -z $HGID ]]; then
   echo "Error: no Host Group exists for [ $hgos $HGAPP $HGTIER ]. The host group may have been deleted or not created yet."
   exit 7
fi

# Set the host group name based on the ID
HGNAME=$( hammer -u $USER -p $PASS hostgroup info --id $HGID | grep "^Name:" | sed -e "s/^Name:[[:space:]]*//" )


#### END CONTEXTUAL VARIABLE SETTING ####

# Explain what we're about to do
echo "Preparing to manage host with the following details:"
echo "FQDN: $RHOST"
echo "TIER: $HGTIER"
echo "TYPE: $HGAPP"
echo "Activation Key: $AK"
echo "Hostgroup Name: $HGNAME"
echo "Puppet Environment: $PUPPETENV"

if [[ -z $PUPPETENV ]]; then
   echo "Failed to determine puppet environment."
   exit
fi

echo ""
read -p "Does the information above look correct? (Enter to continue, Ctrl+C to quit): " JUNK

#### BEGIN HOST MANAGEMENT ####

## Remove OLD Satellite 5 configuration

# Hard-coded fix for an issue that may be specific to my environment
# - Several systems had nss.i686 but not p11-kit-trust.i686 - this caused the CA update to abort
#   This fix instructs the system to attempt installing the latter package prior to removing
#   RHN classic management.  If the system doesn't have a working repository, this will fail.
if [[ -n `$SSHCOMM ${SSHUSER}@${RHOST} sudo yum list nss.i686 2>&1 | grep "Installed"` ]]; then
   if [[ -z `$SSHCOMM ${SSHUSER}@${RHOST} sudo yum list p11-kit-trust.i686 2>&1 | grep "Installed"` ]]; then
      echo "Attempting to reconcile crypto prior to installation"
      $SSHCOMM ${SSHUSER}@${RHOST} sudo yum -y install p11-kit-trust.i686
   fi
fi
# make sure the satellite server is defined in /etc/hosts
if [[ -z `$SSHCOMM ${SSHUSER}@${RHOST} egrep "$RHSS" /etc/hosts` ]]; then
   $SSHCOMM ${SSHUSER}@${RHOST} "echo \"${RHSSIP} $RHSS\" | sudo tee -a /etc/hosts"
fi


# Remove RHN Classic RPMS
for pkg in yum-rhn-plugin rhn-check rhn-setup rhncfg-actions rhncfg rhnlib rhnsd.x86_64 rhn-client-tools rhncfg-client osad rhn-setup-gnome; do
   $SSHCOMM ${SSHUSER}@${RHOST} sudo rpm -e $pkg --nodeps 2>&1 | > /dev/null
done

# Empty all cached info in YUM
$SSHCOMM ${SSHUSER}@${RHOST} sudo yum clean all 2>&1 | > /dev/null

## Remove OLD Satellite 6 configuration
# This is useful if the system is being migrated from another Satellite 6, or if it is
# necessary to re-register it cleanly.

# Empty out subscription manager
$SSHCOMM ${SSHUSER}@${RHOST} sudo subscription-manager clean 2>&1 | > /dev/null

# Remove SAT6 management RPMs
KCRPM=`$SSHCOMM ${SSHUSER}@${RHOST} rpm -qa | grep katello-ca-consumer`
for pkg in puppet facter katello-agent $KCRPM; do
   $SSHCOMM ${SSHUSER}@${RHOST} sudo rpm -e $pkg --nodeps 2>&1 | > /dev/null
done

# Clean existing puppet/facter cache and config
# - Had several systems that had been managed by another puppet master
#   once upon a time - the remnants of those installations caused conflicts

for d in /etc/puppet /var/lib/puppet /etc/puppetlabs /etc/facter; do
   $SSHCOMM ${SSHUSER}@${RHOST} "
   if [[ -d $d ]]; then 
      sudo /bin/rm -rf $d
   fi
   "
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
   if [[ -z $( $SSHCOMM ${SSHUSER}@${RHOST} rpm -qa virt-what ) ]]; then
      $SSHCOMM ${SSHUSER}@${RHOST} sudo rpm -Uvh http://${RHSS}/pub/virt-what-latest.el5.x86_64.rpm | sed "s/^/$RHOST: /g"
   fi
   if [[ -z $( $SSHCOMM ${SSHUSER}@${RHOST} rpm -qa python-dateutil ) ]]; then
      $SSHCOMM ${SSHUSER}@${RHOST} sudo rpm -Uvh http://${RHSS}/pub/python-dateutil-latest.el5.noarch.rpm | sed "s/^/$RHOST: /g"
   fi
fi

# Install the basic subscription manager RPMs directly from the satellite web server
if [[ -z $( $SSHCOMM ${SSHUSER}@${RHOST} rpm -qa python-rhsm ) ]]; then
   $SSHCOMM ${SSHUSER}@${RHOST} sudo rpm -Uvh http://${RHSS}/pub/$PYSMRPM | sed "s/^/$RHOST: /g"
fi
if [[ -z $( $SSHCOMM ${SSHUSER}@${RHOST} rpm -qa subscription-manager ) ]]; then
   $SSHCOMM ${SSHUSER}@${RHOST} sudo rpm -Uvh http://${RHSS}/pub/$SMRPM | sed "s/^/$RHOST: /g"
fi


# Install CA certs from Satellite 6
#$SSHCOMM ${SSHUSER}@${RHOST} sudo yum -y localinstall http://${RHSS}/pub/katello-ca-consumer-latest.noarch.rpm | sed "s/^/$RHOST: /g"
$SSHCOMM ${SSHUSER}@${RHOST} sudo rpm --force -Uvh http://${RHSS}/pub/katello-ca-consumer-latest.noarch.rpm | sed "s/^/$RHOST: /g"

## FQDN Workaround
# The satellite doesn't correctly handle systems which do not use FQDN for the internal hostname
# The systems will show up multiple times under hosts and content hosts and neither will be valid.
# This workaround checks to see if the internal hostname is FQDN - if not the internal hostname
# is temporarily set to the FQDN while the system is registered.  It will be set back afterward.
if [[ `$SSHCOMM ${SSHUSER}@${RHOST} hostname` != `$SSHCOMM ${SSHUSER}@${RHOST} hostname -f` ]]; then
   OHN=`$SSHCOMM ${SSHUSER}@${RHOST} hostname`
   FHN=`$SSHCOMM ${SSHUSER}@${RHOST} hostname -f`
   echo "$RHOST does not use FQDN for hosthame. Temporarily changing the hostname from [$OHN] to [$FHN]"
   $SSHCOMM ${SSHUSER}@${RHOST} sudo hostname $FHN | sed "s/^/$RHOST: /g"
fi

# Register with Satellite 6
$SSHCOMM ${SSHUSER}@${RHOST} sudo subscription-manager register --org="$ORG" --activationkey="${AK}" --name="`hostname -f`" --force | sed "s/^/$RHOST: /g"

# Write the activation key name to the filesystem (this is not actually used by the satellite - this is part of my specific QA processes)
$SSHCOMM ${SSHUSER}@${RHOST} "sudo sh -c \"echo $AK > /root/activationkey\""

# Get the host ID for the newly registered host from the Satellite
HOSTID=$( hammer -u $USER -p $PASS host info --name $1 | grep ^Id: | awk '{print $NF}' )

# Format the comment field to contain description data - this is not actually used by the satellite - it is part of my specifc QA process)
if [[ "$TIER" == "prod" ]]; then
   cTIER=Production
else
   cTIER=Non-Production
fi

COMMENT="${LOC}:${TYPE}:${cTIER}" 

# Put the host in the correct host group, set proxy address, add location
if [[ -n $HOSTID ]] && [[ -n $HGID ]]; then
   #hammer -u $USER -p $PASS host update --hostgroup-id $HGID --id $HOSTID
   #hammer -u $USER -p $PASS host update --hostgroup-id $HGID --id $HOSTID --puppet-ca-proxy $RHSS
   hammer -u $USER -p $PASS host update --hostgroup-id $HGID --id $HOSTID --puppet-ca-proxy $RHSS --comment $COMMENT

else
   echo "DEBUG: HOSTID [$HOSTID]"
   echo "DEBUG: HGID [$HGID]"
   echo "Unable to determine HOSTID or HOST Group ID"
fi

# Check for an existing puppet cert for this host and revoke it if found
# (This is important for re-installs, etc...)
if [[ -n `puppet cert list $RHOST 2>&1 | grep "^+"` ]]; then
   puppet cert clean $RHOST
fi

# Install katello agent and puppet
$SSHCOMM ${SSHUSER}@${RHOST} sudo yum -y install katello-agent puppet | sed "s/^/$RHOST: /g"

# Reconcile katello agent
$SSHCOMM ${SSHUSER}@${RHOST} sudo /usr/sbin/katello-package-upload | sed "s/^/$RHOST: /g"

# Configure puppet agent 
PUPCONF=/etc/puppet/puppet.conf
$SSHCOMM ${SSHUSER}@${RHOST} "sudo sed -i '/^server/d;/^environment/d' $PUPCONF"
$SSHCOMM ${SSHUSER}@${RHOST} "echo  \"environment=${PUPPETENV}\" | sudo tee -a $PUPCONF"
$SSHCOMM ${SSHUSER}@${RHOST} "echo \"server=${RHSS}\" | sudo tee -a $PUPCONF"
$SSHCOMM ${SSHUSER}@${RHOST} sudo puppet agent --test --noop | sed "s/^/$RHOST: /g"

# Set the puppet daemon to run automatically
if [[ $RELEASE -le 6 ]]; then
   $SSHCOMM ${SSHUSER}@${RHOST} sudo /sbin/chkconfig puppet on | sed "s/^/$RHOST: /g"
   $SSHCOMM ${SSHUSER}@${RHOST} sudo /etc/init.d/puppet start | sed "s/^/$RHOST: /g"
elif [[ $RELEASE -eq 7 ]]; then
   $SSHCOMM ${SSHUSER}@${RHOST} sudo hostnamectl set-hostname ${RHOST}
   $SSHCOMM ${SSHUSER}@${RHOST} sudo systemctl enable puppet
   $SSHCOMM ${SSHUSER}@${RHOST} sudo systemctl start puppet
fi
# If the hostname had to be changed to FQDN earlier, change it back now
if [[ -n $OHN ]]; then
   echo "Setting the internal hostname for $RHOST back to [$OHN]"
   $SSHCOMM ${SSHUSER}@${RHOST} sudo hostname $OHN
   if [[ $RELEASE -eq 7 ]]; then
      $SSHCOMM ${SSHUSER}@${RHOST} sudo hostnamectl set-hostname ${OHN}
   fi
fi
