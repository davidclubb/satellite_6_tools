#!/bin/bash

source .sat.env

if [[ -z $1 ]]; then
   echo "You must provide a host name"
   exit 1
else
   HOST=$1
fi



HGID=$( curl -X GET -s -k -u ${USER}:${PASS}  https://${SATELLITE}/api/v2/hosts/$HOST | sed 's/[:]/ /g' | awk -F'hostgroup_id" ' '{print $2}' | awk -F',' '{print $1}' )
HGN=$( curl -X GET -s -k -u ${USER}:${PASS}  https://${SATELLITE}/api/v2/hosts/$HOST | sed 's/[:]/ /g' | awk -F'hostgroup_name" ' '{print $2}' | awk -F',' '{print $1}' )
curl -X GET -s -k -u ${USER}:${PASS}  https://${SATELLITE}/api/v2/hosts/$HOST 
#echo "$HGID $HGN"
