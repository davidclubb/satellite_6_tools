#!/bin/bash

# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.sh"
   exit
fi

RELEASE=`f_GetRelease | awk '{print $2}'`


# RHEL 7 doesn't need vmtools and rc.local is deprecated
RCLOCAL=/etc/rc.d/rc.local
if [[ $RELEASE -le 6 ]]; then

   echo 'pkill -9 puppet' >> $RCLOCAL
   echo '/usr/bin/puppet agent --test' >> $RCLOCAL
   echo '/etc/init.d/puppet restart' >> $RCLOCAL
   echo '/etc/init.d/nscd stop;/etc/init.d/nscd reload' >> $RCLOCAL
   echo "sed -i '/puppet/d' $RCLOCAL" >> $RCLOCAL
   echo "sed -i '/nscd/d' $RCLOCAL" >> $RCLOCAL
   echo '/opt/sa/scripts/setup_vmtools.sh' >> $RCLOCAL
   echo "sed -i '/setup_vmtools.sh/d' $RCLOCAL" >> $RCLOCAL
   echo '/opt/sa/scripts/generate_qa.sh' >> $RCLOCAL
   echo "sed -i '/generate_qa.sh/d' $RCLOCAL" >> $RCLOCAL
else
   echo 'TO=0'
   echo 'until [[ -n `/bin/systemctl is-active network | grep "^active\$"` ]] || [[ $TO == 120 ]]; do sleep 1; let TO=$TO+1; done' >> $RCLOCAL
   echo 'pkill -9 puppet' >> $RCLOCAL
   echo 'systemctl stop nscd.service' >> $RCLOCAL
   echo 'systemctl reload nscd.service' >> $RCLOCAL
   echo '/usr/bin/puppet agent --test' >> $RCLOCAL
   echo "sed -i '/puppet/d' $RCLOCAL" >> $RCLOCAL
   echo "sed -i '/nscd/d' $RCLOCAL" >> $RCLOCAL
   echo '/opt/sa/scripts/generate_qa.sh' >> $RCLOCAL
   echo "sed -i '/generate_qa.sh/d' $RCLOCAL" >> $RCLOCAL
   chmod +x $RCLOCAL

fi

