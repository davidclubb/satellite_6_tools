#!/bin/bash

if [[ -s /etc/exports ]]; then
   cat /etc/exports | sed 's/[[:space:]]/ \\\n  /g' > /etc/exports.new
   echo "Sorted file exported as /etc/exports.new"
else
   echo "No filesystems exported"
fi
