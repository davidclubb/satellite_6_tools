#!/bin/bash

# Adds local users 

# - deprecated - use Puppet instead
exit


# Include common_functions.h
if [[ -s /var/satellite/post_scripts/common_functions.sh ]]; then
   source /var/satellite/post_scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit
fi

#for sf in "/etc/passwd /etc/shadow /etc/group"; do
#   chattr -i $sf
#done

FULLNAME=`f_GetRelease`

PRODUCT=`echo $FULLNAME | awk '{print $1}'`
RELEASE=`echo $FULLNAME | awk '{print $2}'`
UPDATE=`echo $FULLNAME | awk '{print $3}'`

# Everything gets unixpa
if [[ -z `grep "^unixpa:" /etc/group` ]]; then groupadd -g 501 unixpa; fi
if [[ -z `grep "^unixpa:" /etc/passwd` ]]; then useradd -u 501 -g 501 -s /bin/bash -c "UNIX Privileged Account" -p '<redacted password hash>' -d /usr/local/home/unixpa unixpa; fi

if [[ -z `grep "^unixaa:" /etc/group` ]]; then groupadd -g 1300 unixaa; fi
if [[ -z `grep "^unixaa:" /etc/passwd` ]]; then useradd -u 1300 -g 1300 -s /bin/bash -c "UNIX Action Account" -p '<reacted password hash>' -d /usr/local/home/unixaa unixaa; fi

if [[ -z `grep "^unixama:" /etc/group` ]]; then groupadd -g 1301 unixama; fi
if [[ -z `grep "^unixama:" /etc/passwd` ]]; then useradd -u 1301 -g 1301 -s /bin/bash -c "UNIX Action Account" -p '<redacted password hash>' -d /usr/local/home/unixama unixama; fi



# Install the authorized key for unixpa
/bin/mkdir -p /usr/local/home/unixpa/.ssh
echo '<redacted public key>' >> /usr/local/home/unixpa/.ssh/authorized_keys
/bin/chmod 700 /usr/local/home/unixpa/.ssh
/bin/chmod 600 /usr/local/home/unixpa/.ssh/authorized_keys
/bin/chown -R 501:501 /usr/local/home/unixpa/.ssh

# Remove unnecessary accounts
UNNEEDED_ACCOUNTS="
games
"
for UA in $UNNEEDED_ACCOUNTS; do
   if [[ -n `grep ^${UA}: /etc/passwd` ]]; then 
      echo "# ${UA} Removed `date` by $0" >> /etc/.passwd.removed
      grep "^${UA}" /etc/passwd >> /etc/.ps.removed
      echo "# ${UA} Removed `date` by $0" >> /etc/.shd.removed
      grep "^${UA}" /etc/shadow >> /etc/.shd.removed
      /usr/sbin/userdel -f ${UA}; 
      
   fi
done
UNNEEDED_GROUPS="
games
"

for UG in $UNNEEDED_GROUPS; do
   if [[ -n `grep ^${UG}: /etc/group` ]]; then
      echo "# ${UG} Removed `date` by $0" >> /etc/.group.removed
      grep "^${UG}" /etc/group >> /etc/.gp.removed
      /usr/sbin/groupdel ${UG};
   fi
done


#for sf in "/etc/passwd /etc/shadow /etc/group"; do
#   chattr +ui $sf
#done
