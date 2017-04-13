#!/bin/bash

. .satapi.env

HOSTID=272
HGID=17
COMMENT="Adding Spaces"

APIPUT="/bin/curl -s -H Accept:application/json,version=2 -H Content-Type:application/json -X PUT -k -u ${USER}:${PASS}"

set -x
$APIPUT -d "{\"host\":{\"comment\":\"${COMMENT}\", \"hostgroup_id\":$HGID, \"puppet_ca_proxy_id\":1}}" https://${SATELLITE}/api/hosts/${HOSTID} | python -mjson.tool
