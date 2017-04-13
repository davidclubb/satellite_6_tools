#!/bin/bash

# Deprecated - use puppet

exit

# Common settings for common services

# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi

FULLNAME=`f_GetRelease`

PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`

CHKCONFIG=/sbin/chkconfig
INITD=/etc/init.d
TARS_DIR=/maint/scripts/tars

# Define the Deactivate and Activate lists.

DALIST="vsfptd cups ip6tables autofs avahi-daemon kudzu gpm apmd lpd smartd"

if [[ $PRODUCT == RHEL ]]; then

   if [[ $RELEASE -le 5 ]]; then
      ALIST="iptables sshd ntpd nfs kdump dnscheck"
   fi

   # Specific services for RHEL 6
   if [[ $RELEASE -eq 6 ]]; then
      ALIST="iptables sshd ntpd nfs kdump nslcd oddjobd dnscheck"
   fi

   # Specific services for RHEL 7
   if [[ $RELEASE -eq 7 ]]; then
      ALIST="firewalld sshd chronyd kdump nslcd oddjobd dnscheck"
   fi

fi

#Process De-activate list
for SN in $DALIST; do
   if [[ $PRODUCT == RHEL ]];then

      # For RHEL releases up to 6, most services are still SysV init
      if [[ $RELEASE -le 6 ]]; then
         if [[ -s "${INITD}/${SN}" ]]; then
            $CHKCONFIG $SN off
         fi
      else
         if [[ -s "/usr/lib/systemd/system/${SN}.service" ]]; then
            /bin/systemctl disable ${SN}.service 2>&1 | >>/dev/null
         fi
      fi
   fi
done

#Process Activate list
if [[ $PRODUCT == RHEL ]]; then

   for SN in $ALIST; do
      if [[ $RELEASE -le 6 ]]; then
         if [[ -s "${INITD}/${SN}" ]]; then
            $CHKCONFIG $SN --level 345 on
            #/sbin/service $SN start > /dev/null
         fi
      else
         if [[ -s "/usr/lib/systemd/system/${SN}.service" ]]; then
            /bin/systemctl enable ${SN}.service 2>&1 | >>/dev/null
         fi
      fi
   done
fi

# NSCD setup
if [[ $PRODUCT == RHEL ]];then
   if [[ $RELEASE -le 6 ]]; then
      /sbin/chkconfig --add nscd
      /sbin/chkconfig nscd on
      #/sbin/service nscd start 2>&1 | >> /dev/null
      /sbin/service nscd start > /dev/null
   else
      /bin/systemctl enable nscd.service 2>&1 | >>/dev/null
      /bin/systemctl start nscd.service 2>&1 | >>/dev/null
   fi
fi

# Disable ctrl+alt+delete to reboot
if [[ $PRODUCT == RHEL ]];then
   if [[ $RELEASE -lt 6 ]]; then
      if [[ -z `grep ctrlaltdel /etc/inittab | grep -i disabled` ]]; then
         sed -i.orig '/ctrlaltdel/s/^/#/;/ctrlaltdel/s/$/\nca::ctrlaltdel:\/bin\/echo "NOTICE: Ctrl+Alt+Delete is disabled" >\&1/' /etc/inittab
      fi
   elif [[ $RELEASE -eq 6 ]]; then
      # Placeholder
      echo "Control-Alt-Delete has been disabled"
   
   else
      ln -sf /dev/null /usr/lib/systemd/system/ctrl-alt-del.target
   fi
fi


