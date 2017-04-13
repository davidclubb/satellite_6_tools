#!/bin/bash

source .sat.env

if [[ -z $1 ]]; then
   echo "You must provide a host name"
   exit 1
else
   HOST=$1
fi

curl -X GET -s -k -u ${USER}:${PASS}  https://${SATELLITE}/api/v2/hosts/$HOST | python -mjson.tool
