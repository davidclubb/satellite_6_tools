#!/bin/bash

# Incept 2015/05/28
# Author SDW
# Purpose: Configure firewall


# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi


# Define Variables
CP=/bin/cp
CAT=/bin/cat
RPM=/bin/rpm
EGREP=/bin/egrep
SYSTEMCTL=/bin/systemctl
FIREWALLCMD=/bin/firewall-offline-cmd

RELEASE=`f_GetRelease | awk '{print $2}'`

if [[ "$RELEASE" != "7" ]]; then
   echo "Not RHEL 7, firewalld does not apply."
   exit 0
fi

# If the service isn't enabled, enable it
if [[ -n `$SYSTEMCTL is-enabled firewalld | grep "^disabled$"` ]]; then
   $SYSTEMCTL enable firewalld 2>&1 | >> /dev/null
fi

# If the service isn't started, start it
#if [[ -n `$SYSTEMCTL is-active firewalld | grep "^inactive$"` ]]; then
#   $SYSTEMCTL start firewalld 2>&1 | >> /dev/null
#fi

#if [[ -z `$SYSTEMCTL is-active firewalld | grep "^active$"` ]]; then
#   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
#      echo "`$VTS`:$0:FAILURE - unable to start the firewalld daemon" | $LOG1
#   fi  
#   exit 2
#fi

ISNETUP=`f_IsNetUp`

if [[ $ISNETUP == NO ]]; then
   if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
      echo "`$VTS`:$0:FAILURE - network is not reachable, unable to determine correct settings" | $LOG1
   fi
   echo "   FAILURE: network is not set up or not working."
   echo "            Please set up the network and ensure"
   echo "            it is working, then run this script again."
   exit 3
fi



# If the server is in the DMZ or fails the "On Intranet" check, then
# use the more restrictive settings.

echo "Checking environment."
echo "   On Intranet?: `f_OnIntranet`"
echo "           DMZ?: `f_InDMZ`"
OIN=`f_OnIntranet`
DMZ=`f_InDMZ`

## Make sure to reload the existing ruies before continuing
#$FIREWALLCMD --reload
#
## Allow SCOM ports
#$FIREWALLCMD --add-port=1270/tcp
#$FIREWALLCMD --add-port=5723/tcp
$CAT << EOF > /etc/firewalld/services/SCOM.xml
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>SCOM Client</short>
  <description>Microsoft System Center Operations Manager Client</description>
  <port protocol="tcp" port="1270"/>
  <port protocol="tcp" port="5723"/>
</service>
EOF
$FIREWALLCMD --service=SCOM

$CAT << EOF > /etc/firewalld/services/CommVault.xml
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>CommVault Agent</short>
  <description>CommVault Agent</description>
  <port protocol="tcp" port="8390"/>
  <port protocol="tcp" port="8602"/>
</service>
EOF
$FIREWALLCMD --service=CommVault
#
## Allow COMMVAULT SERVER
$FIREWALLCMD --zone=trusted --add-source=10.252.241.10
#

if [[ "$1" == "SAP" ]]; then

$CAT << EOF > /etc/firewalld/services/SAP-App-CI.xml
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>SAP DB and CI</short>
  <description>SAP is a CRM Software Stack</description>
  <port protocol="tcp" port="1128"/>
  <port protocol="tcp" port="1129"/>
  <port protocol="tcp" port="3200-3299"/>
  <port protocol="tcp" port="3300-3399"/>
  <port protocol="tcp" port="3600-3699"/>
  <port protocol="tcp" port="3900-3999"/>
  <port protocol="tcp" port="4700-4799"/>
  <port protocol="tcp" port="4800-4899"/>
  <port protocol="tcp" port="8000"/>
  <port protocol="tcp" port="8001"/>
  <port protocol="tcp" port="8004"/>
  <port protocol="tcp" port="8400"/>
  <port protocol="tcp" port="8401"/>
  <port protocol="tcp" port="8404"/>
  <port protocol="tcp" port="50000"/>
  <port protocol="tcp" port="50100"/>
  <port protocol="tcp" port="50200"/>
  <port protocol="tcp" port="50300"/>
  <port protocol="tcp" port="50400"/>
  <port protocol="tcp" port="50500"/>
  <port protocol="tcp" port="50001"/>
  <port protocol="tcp" port="50101"/>
  <port protocol="tcp" port="50201"/>
  <port protocol="tcp" port="50301"/>
  <port protocol="tcp" port="50401"/>
  <port protocol="tcp" port="50501"/>
  <port protocol="tcp" port="50013"/>
  <port protocol="tcp" port="50113"/>
  <port protocol="tcp" port="50213"/>
  <port protocol="tcp" port="50313"/>
  <port protocol="tcp" port="50413"/>
  <port protocol="tcp" port="50513"/>
</service>
EOF
$CAT << EOF > /etc/firewalld/services/OracleDB.xml
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Oracle Database</short>
  <description>Covers Oracle Database Listener Ports</description>
  <port protocol="tcp" port="1521"/>
  <port protocol="tcp" port="1527"/>
  <port protocol="tcp" port="3872"/>
  <port protocol="tcp" port="4900"/>
</service>
EOF

$FIREWALLCMD --service=SAP-App-CI
$FIREWALLCMD --service=OracleDB

fi

if [[ "$1" == "OracleDB" ]]; then
$CAT << EOF > /etc/firewalld/services/OracleDB.xml
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>Oracle Database</short>
  <description>Covers Oracle Database Listener Ports</description>
  <port protocol="tcp" port="1521"/>
  <port protocol="tcp" port="1527"/>
  <port protocol="tcp" port="3872"/>
  <port protocol="tcp" port="4900"/>
</service>
EOF
$FIREWALLCMD --service=OracleDB
fi
