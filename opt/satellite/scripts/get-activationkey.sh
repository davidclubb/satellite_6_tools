#!/bin/bash

source .sat.env

if [[ -z $1 ]]; then
   echo "You must provide a host name"
   exit 1
else
   HOST=$1
fi

AKID=$( curl -X GET -s -k -u ${USER}:${PASS}  https://${SATELLITE}/api/v2/hosts/$HOST | sed 's/[":{}\[]/ /g' | awk -F'activation_keys' '{print $2}' | awk -F']' '{print $1}' | awk -F',' '{print $1}' | awk '{print $NF}' )
AKN=$( curl -X GET -s -k -u ${USER}:${PASS}  https://${SATELLITE}/api/v2/hosts/$HOST | sed 's/[":{}\[]/ /g' | awk -F'activation_keys' '{print $2}' | awk -F']' '{print $1}' | awk '{print $NF}' )

echo "$AKID $AKN"

#"activation_keys":[{"id":13,"name":"1-rhel6-pilot-sap"}],
