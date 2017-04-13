#!/bin/bash

# Retrieve a root password for a system

# Script needs to be run as root - automatically attempt sudo
if [[ $EUID != 0 ]]; then
   sudo $0 $@
   exit 0
fi

# Locations
PV=/root/pv
HIST=${PV}/history

if [[ $# -eq 0 ]]; then
   echo "You must provide the fully qualified domain name of a server."
   exit 4
fi

if [[ $# -gt 2 ]]; then
   echo "Invalid argument count."
   exit 1
fi

if [[ $# -eq 1 ]]; then
   FQDN=$1
   if [[ -s ${PV}/${FQDN} ]]; then
      cat ${PV}/${FQDN}
   else
      echo "Error: [$FQDN] not found in password vault."
      exit 2
   fi
else
   OPT=$1
   FQDN=$2
   
   case $OPT in
      -h ) if [[ -s ${PV}/${FQDN} ]]; then
              echo "Current Password: "
              cat ${PV}/${FQDN}
           else
              echo "Error: [$FQDN] not found in password vault."
              exit 2
           fi
           PASSTAR=${HIST}/${FQDN}.tar
           if [[ -s $PASSTAR ]]; then
              echo ""
              echo "Password History:"
              tar -xf $PASSTAR -O | strings | tac
           fi
           ;;
       * ) echo "Unrecognized option [$OPT]"
           exit 3
           ;;

   esac
fi

exit

