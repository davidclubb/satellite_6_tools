#!/bin/bash
RHOST=$1
if [[ -z $RHOST ]]; then
   echo "Please provide the name of a system to push unixpa to."
   exit 4
fi
echo "This script will attempt to ensure the \"unixpa\" user is setup and authorized."
echo "correctly on the remote system. In order for this to work we'll need to be able"
echo "to log in as root."
echo ""

# Test connectivity
SSHCOM="/usr/bin/ssh -q -o stricthostkeychecking=no -o userknownhostsfile=/dev/null"
echo "For security reasons you will be prompted to enter passwords multiple times."

$SSHCOM root@${RHOST} /bin/true
RETCODE=$?
if [[ "$RETCODE" != "0" ]]; then
   echo "Error connecting to $RHOST via SSH.  Please verify the password and that the user $RUSER exists there." 1>&2
   exit $RETCODE
else
#if [[ -z `$SSHCOM root@${RHOST} getent passwd unixpa` ]]; then
   $SSHCOM root@${RHOST} "groupdel unixpa;
   userdel unixpa;
   groupadd -g 501 unixpa;
   useradd -u 501 -g 501 -b /usr/local/home unixpa;
   mkdir /usr/local/home/unixpa/.ssh;
   chown unixpa:unixpa /usr/local/home/unixpa/.ssh;
   chmod 700 /usr/local/home/unixpa/.ssh;
   echo 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAwnJd0Rdh0UUnR/BybvZBrBJ9SxEZ21orRiLXD5BUqPPZE/YbStJ4zjqvZGCpSKBUzM5tS3oeDheEjoL4h/CARXZZmTnA5epQM1g6VnQ7d+suKijFBTpsiUcepv4DjSakkaGGu/Ic4e/tgvmCFJwbyPG0yOrgF10NlPfqexZw6Y3RrsHSa8NKHhuj3+2X87ySZnKigWkGDPRHAyhIk5b+O7tur8J7BfNQSeHMkMkLi6MRDDq6bdaYNqII6SC9M1c4mUNmr+aYk5uJmZBaDc1Ut0Cpuih1/YJ4nna5hJ15Pym+S5ZLFLZV0bVCYU3YGjbikCsDPLhU+XFGwCMk6ReaPw==' > /usr/local/home/unixpa/.ssh/authorized_keys;
   chmod 600 /usr/local/home/unixpa/.ssh/authorized_keys;
   chown unixpa:unixpa /usr/local/home/unixpa/.ssh/authorized_keys;
   echo 'Defaults:unixpa !requiretty' >> /etc/sudoers;
   echo 'Defaults:unixpa visiblepw' >> /etc/sudoers;
   echo 'unixpa                  ALL=(ALL)       NOPASSWD: ALL' >> /etc/sudoers;
   "
fi

