#!/bin/bash

# This script is based on a PHP based autiomation report tool.

exit
# Usage

f_Usage() {

   $0 



}


# Set variables
ORIGIN=`hostname`
TARGET=$ORIGIN
PNAME=`basename $0`
TB=$USER
CAT=remediation
DESC="Testing the API"
TARGETIP=`getent hosts $TARGET | awk '{print $1}'`
TIMESAVED=0
START=`date "+%Y-%m-%d %H:%M:%S"`
 
# Put your script's payload here
/bin/true
RETVAL=$?
 
sleep 1
 
END=`date "+%Y-%m-%d %H:%M:%S"`
 
 
 
if [[ $RETVAL == 0 ]]; then
   SUCCESS=true
else
   SUCCESS=false
fi
		 
# Update the DB with the event
curl -k -X POST --form "origin_hostname=$ORIGIN" --form "target_hostname=$TARGET" --form "processname=$PNAME" --form "triggeredby=$TB" --form "category=$CAT" --form "description=$DESC" --form "target_ip=$TARGETIP" --form "timesaved=$TIMESAVED" --form "datestarted=$START" --form "datefinished=$END" --form "success=$SUCCESS" --netrc https://kneschiwp001.kiewitplaza.com/reportingapi/




