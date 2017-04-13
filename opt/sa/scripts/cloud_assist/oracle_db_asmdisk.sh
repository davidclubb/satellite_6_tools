#!/bin/bash

# Make sure ASM is running
/etc/init.d/oracleasm restart

# Free disks count
FC=0

# List all the SCSI type disks found
for d in `ls /sys/block | grep ^sd`; do
   FREE=YES

   # If disk is partitioned it isn't free
   if [[ -n `ls /sys/block/$d | grep ^sd` ]]; then
      FREE=NO
   fi

   # If the disk has an LVM label it isn't free
   if [[ -n `/sbin/pvs --noheadings | awk '{print $1}' | awk -F'/' '{print $3}' | tr -d '[0-9]' | grep $d` ]]; then
      FREE=NO
   fi

   if [[ $FREE == YES ]]; then
      let FC=$FC+1

      # The first disk will be labeled as FLASH01
      if [[ $FC -eq 1 ]]; then
         /sbin/parted -s /dev/${d} mklabel gpt mkpart primary -a optimal "1 -1"
         /usr/sbin/oracleasm createdisk FLASH01 /dev/${d}1
      elif [[ $FC -gt 1 ]] && [[ $FC -lt 10 ]]; then
         let DN=$FC-1
         /sbin/parted -s /dev/${d} mklabel gpt mkpart primary -a optimal "1 -1"
         /usr/sbin/oracleasm createdisk DATA0${DN} /dev/${d}1
      fi
   fi
done

