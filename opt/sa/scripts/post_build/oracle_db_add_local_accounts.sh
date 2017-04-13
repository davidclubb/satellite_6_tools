#!/bin/bash

# Add local accounts and groups 

if [[ -z `grep "^oinstall:" /etc/group` ]]; then 
   echo "Adding [oinistall] group"
   groupadd -g 500 oinstall
fi

if [[ -z `grep "^dba:" /etc/group` ]]; then 
   echo "Adding [dba] group"
   groupadd -g 554 dba
fi

if [[ -z `grep "^oracle:" /etc/passwd` ]]; then
   echo "Adding [oracle] service account"
   useradd -u 500 -g 500 -G 554 -s /bin/bash -c "Oracle Service Account" -d /usr/local/home/oracle -p '$5$ruYZtuRF$lYqEZvkD3Dh9ZNomPY.RFSWD3IZ8VqE7XcHausPxbE.' oracle
fi

if [[ -z `grep "^kwtbkup:" /etc/passwd` ]]; then
   echo "Creating [kwtbkup] service account"
   useradd -u 504 -g dba -G oinstall -c "Service Account for OEM to Manage Backups" -d /usr/local/home/kwtbkup -p '$5$30CAGVUX$BwAmn2hhxF/Dk.c6IHYzpUxjIB6GfYIGPcC9W1L17G/' kwtbkup
fi


