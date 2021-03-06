# These are common functions that may be included in other scripts
# with one of the following:

#  . common_functions.h
# source common_functions.h

CF_VERS=20160609A


# Some of these functions are dependent upon a timestamp variable called TS
# In general the script using the function should provide this, but in case it does not
# One will be generated here

if [[ -z $TS ]]; then
   export TS=`date +%Y%m%d%H%M%S`
fi

#-----------------
# Function: f_CreateBondMaster
#-----------------
# Accepts the IP, Netmask and filename
# and creates a bond config
#-----------------
# Usage: f_CreateBondMaster <IP> <DEVNAME> <NETMASK> <FILE>
#-----------------
# Returns: SUCCESS, FAILURE
f_CreateBondMaster () {

   IP=$1
   DEV=$2
   NM=$3
   FN=$4
   RESULT=SUCCESS
   # If the config file already exists, back it up
   if [[ -f $FN ]]; then
      #mv $FN ${FN}.${TS}
      if [[ $? -ne 0 ]]; then
         RESULT=FAILURE
      fi
   fi

   if [[ $RESULT != FAILURE ]]; then
   # Write out the File

cat << EOF > $FN
DEVICE=${DEV}
ONBOOT=yes
IPADDR=${IP}
NETMASK=${NM}
GATEWAYDEV=${DEV}
PEERDNS=no
USERCTL=no
EOF

   fi
   if [[ -z `grep $DEV $FN` ]] || [[ -z `grep $IP $FN` ]] || [[ -z `grep $NM $FN` ]]; then
      RESULT=FAILURE
      if [[ -f ${FN}.${TS} ]]; then
         #If the new bond script fails validation, restore the backup if there is one
         /bin/cp ${FN}.${TS} ${FN}
      fi
   fi

   echo $RESULT

}

#-----------------
# Function: f_DetectVM
#-----------------
# Determines if the server is a VM
#-----------------
# Usage: f_DetectVM
#-----------------
# Returns: TRUE | FALSE

f_DetectVM () {
   RESULT=FALSE
   if [[ -n `/usr/sbin/dmidecode | awk /"System Information"/,/"Serial Number"/ | grep "Product" | egrep -i 'rhev|vmware|Virtual Machine'` ]]; then
      RESULT=TRUE
   fi

   echo $RESULT

}



#-----------------
# Function: f_FindPubIP
#-----------------
# Determines the public IP of the current server
#-----------------
# Usage: f_FindPubIP
#-----------------
# Returns: <IPv4 Address>, FAILURE
f_FindPubIP () {

   #Method 1 - ifconfig - only really works if an IP is already assigned to a running device
   #IPLIST=`ifconfig -a | grep "inet addr" | awk '{print $2}' | awk -F':' '{print $NF}' | grep -v 127.0.0.1`
   IPLIST=`/sbin/ifconfig -a | grep "inet " | awk '{print $2}' | awk -F':' '{print $NF}' | grep -v 127.0.0.1`

   if [[ -z $IPLIST ]]; then
      #Method 2 - DNS/hosts file
      HN=`hostname`
      IPLIST=`getent hosts $HN`
   fi

   if [[ `echo $IPLIST | wc -w` -eq 1 ]]; then
      # If we only have one IP then go with it
      RESULT=$IPLIST
   else
      # If we have more than one IP then we need to figure out which
      # is the public IP
      # We'll do this by looking at the default gateway
      GW=`f_FindDefaultGW`
      if [[ $GW != FAILURE ]]; then
         # Check to see if the first thee octets of an IP match
         # the first three octets of the gateway - that should
         # mean that's our public IP
         FTO=`echo $GW | awk -F'.' '{print $1"."$2"."$3"."}'`
         for i in $IPLIST; do
            if [[ -n `echo $i | grep ^$FTO` ]]; then
               RESULT=$i
            fi
         done
      fi
   fi
   if [[ -z $RESULT ]] || [[ $RESULT == NOLINK ]]; then
      RESULT=FAILURE
   fi

   echo $RESULT
}

#-----------------
# Function: f_FindDefaultGW
#-----------------
# Determines the default gateway of the machine
#-----------------
# Usage: f_FindDefaultGW
#-----------------
# Returns: <IPv4 Gateway Address>, FAILURE

f_FindDefaultGW () {

   RESULT=FAILURE
   # Method 1 - read from sysconfig
   GW=`grep ^GATEWAY /etc/sysconfig/network | awk -F'=' '{print $NF}'`
   # Method 2 - the gateway via route
   if [[ -z $GW ]]; then
      GW=`route -n | grep ^0.0.0.0 | awk '{print $2}'`
   fi

   if [[ -n $GW ]]; then
      RESULT=$GW
   fi
   echo $RESULT
}

#-----------------
# Function: f_CreateBondSlave
#-----------------
# Accepts the Device Name, Bond Name, and File Name
# and creates a slave config
#-----------------
# Usage: f_CreateBondSlave <DEV> <MASTER> <FILE>
#-----------------
# Returns: SUCCESS, FAILURE
f_CreateBondSlave () {

   DEV=$1
   MASTER=$2
   FN=$3
   RESULT=SUCCESS
   # If the config file already exists, try to read the HWADDR from it
   if [[ -f $FN ]]; then
      HWADDR=`grep "^HWADDR=" $FN | awk -F'=' '{print $2}'`
   fi

   # if bonding was set up previously, read the real hwaddr
   if [[ -z $HWADDR ]]; then 
      if [[ -d /proc/net/bonding ]]; then 
         PROCBOND=`grep -R $DEV /proc/net/bonding/ | awk -F':' '{print $1}'`
         if [[ -n $PROCBOND ]]; then
            HWADDR=`cat $PROCBOND | awk "/${DEV}/,/Permanent/" | grep Permanent | awk '{print $NF}'`
         fi
      fi
   fi

   # if it's still not set, then fall back on the output of ifconfig
   if [[ -z $HWADDR ]]; then
      HWADDR=`/sbin/ifconfig ${DEV} | grep -i hwaddr | awk '{print $NF}'`
   fi

   if [[ $RESULT != FAILURE ]]; then
   # Write out the File

cat << EOF > $FN
DEVICE=${DEV}
ONBOOT=yes
TYPE=Ethernet
BOOTPROTO=none
MASTER=${MASTER}
SLAVE=yes
USERCTL=no
PEERDNS=no
HWADDR=$HWADDR
#ETHTOOL_OPTS='speed 100 duplex full autoneg off'
#ETHTOOL_OPTS='autoneg on'
EOF
   fi
   if [[ -z `grep $DEV $FN` ]] || [[ -z `grep $MASTER $FN` ]]; then
      RESULT=FAILURE
      if [[ -f ${FN}.${TS} ]]; then
         #If the new config failed then restore the backup if we made one
         /bin/cp ${FN}.${TS} ${FN}
      fi
   fi

   echo $RESULT

}

#-----------------
# Function: f_CheckIF
#-----------------
# Checks NIC device names to ensure they
# exist and are up
#-----------------
# Usage: f_CheckIF <DEV>
#-----------------
# Returns: SUCCESS, FAILURE, NOLINK
f_CheckIF () {

   DEV=$1
   RESULT=SUCCESS
   if [[ -n `ethtool -i $DEV 2>&1 | grep "No such device"` ]]; then
      RESULT=FAILURE
   elif [[ -z `ethtool $DEV | grep Link | grep -i yes` ]]; then
      RESULT=NOLINK
   fi

   echo $RESULT

}

#-----------------
# Function: f_IPforIF
#-----------------
# Checks for an IP assigned to a NIC
#-----------------
# Usage: f_IPforIF <DEV>
#-----------------
# Returns: <IP>, NONE
f_IPforIF () {
   unset RESULT
   IF=$1
   if [[ -f /etc/sysconfig/network-scripts/ifcfg-${IF} ]]; then
      RESULT=`grep ^IPADDR /etc/sysconfig/network-scripts/ifcfg-${IF} | awk -F'=' '{print $NF}' | sed 's/"//g'`
   fi
   if [[ -z $RESULT ]]; then
      RESULT=`ifconfig $IF | grep "inet addr" | awk '{print $2}' | awk -F':' '{print $NF}' | sed 's/"//g'`
   fi
   if [[ -z $RESULT ]]; then
      RESULT=`ifconfig $IF | grep "inet " | awk '{print $2}' | awk -F':' '{print $NF}' | sed 's/"//g'`
   fi
   if [[ -z $RESULT ]] || [[ $RESULT == NOLINK ]]; then
      RESULT=NONE
   fi
   echo $RESULT
}

# Function: f_GetRelease
#-----------------
# Reads distro/release info and responds with three fields:
# The abbreviated Distro name, the Release version, the Update version
#-----------------
# Usage: f_GetRelease
#-----------------
# Returns: <DISTRO> <RELEASE> <UPDATE>

f_GetRelease () {
   DISTRO=NON_REDHAT
   RELEASE=0
   UPDATE=0

   # Check for a redhat-release file
   if [[ -f /etc/redhat-release ]]; then

      # if the word "Update" doesn't appear in the release further parsing is required
      if [[ -z `cat /etc/redhat-release | grep Update` ]]; then
         VERSION=`cat /etc/redhat-release | awk -F'release' '{print $2}' | awk '{print $1}'`
  
         # If the version string doesn't have a dot in it assume it's a .0 release, otherwise the 
         # Update is the number after the dot 
         if [[ -z `echo $VERSION | grep '.'` ]]; then
            RELEASE=$VERSION
            UPDATE=0
         else
            RELEASE=`echo $VERSION | awk -F'.' '{print $1}'`
            UPDATE=`echo $VERSION | awk -F'.' '{print $2}'`
         fi

      # If the word "Update" does appear, then parse the string
      else
        RELEASE=`cat /etc/redhat-release | awk -F'release' '{print $NF}' | awk '{print $1}'`
        UPDATE=`cat /etc/redhat-release | tr -d '()' | awk -F'Update' '{print $NF}' | awk '{print $1}'`
        VERSION=${RELEASE}.${UPDATE}
      fi

      # If the kernel's "el" string doesn't match the release, the kernel overrides the redhat-release file
      # Update is set to X because there is no reliable way to determine update level
      if [[ -z `uname -r | grep -i "el${RELEASE}"` ]]; then
         RELEASE=`uname -r | awk -F'.el' '{print $2}' | cut -c1`
         UPDATE=X
      fi

      if [[ -n `cat /etc/redhat-release | grep "Red Hat Enterprise Linux Server release"` ]]; then
         DISTRO=RHEL
      elif [[ -n `cat /etc/redhat-release | grep "Red Hat Enterprise Linux Everything release"` ]]; then
         DISTRO=RHEL
      elif [[ -n `cat /etc/redhat-release | grep "Red Hat Linux release"` ]]; then
         DISTRO=RH
      elif [[ -n `cat /etc/redhat-release | grep "Red Hat Enterprise Linux ES release"` ]]; then
         DISTRO=RHES
      elif [[ -n `cat /etc/redhat-release | grep "Red Hat Enterprise Linux AS release"` ]]; then
         DISTRO=RHAS
      else
         DISTRO=UNKNOWN_REDHAT
      fi
   fi

   echo "$DISTRO $RELEASE $UPDATE"

}

#-----------------
# Function: f_ValidIPv4
#-----------------
# Checks a string to ensure it contains a valid
# ipv4 address
#-----------------
# Usage: f_ValidIPv4 <IP>
#-----------------
# Returns: TRUE, FALSE
f_ValidIPv4 () {

   IPv4=$1
   # Valid until proven otherwise
   RESULT=TRUE

   # Does it have 4 octets?
   if [[ `echo $IPv4 | awk -F'.' '{print NF}'` -ne 4 ]]; then
      RESULT=FALSE
   else
      # Look at each octet
      for o in `echo $IPv4 | sed  's/\./ /g'`; do
         # Is the octet numeric?
         if [[ -z `echo $o | egrep "^[0-9]+$"` ]]; then
            RESULT=FALSE
         else
            # Is the octet less than 0 or greater than 255?
            if [[ $o -lt 0 ]] || [[ $o -gt 255 ]]; then
               RESULT=FALSE
            fi
         fi
      done
   fi
   echo $RESULT
}

#-----------------
# Function: f_MakeSiteMenu
#-----------------
# Reads a text file with "<number>:<name>" format and displays a
# multi-column menu to the screen to ask for choices.
#-----------------
# Usage: f_MakeSiteMenu
#-----------------
# Returns: Menu | FAILURE
f_MakeSiteMenu() {

   MENUFILE=$1

   if [[ -s $MENUFILE ]]; then

     # The number of spaces to indent the first menu column
     LEFTINDENT=3

     # The width of each menu column
     #COLWIDTH=30

     # Determine width dynamically
     LONGEST=0
     for s in `cat $MENUFILE | awk -F':' '{print $2}'`; do
        if [[ `echo $s | wc -m` -gt $LONGEST ]]; then
           LONGEST=`echo $s | wc -m`
        fi
     done
     let COLWIDTH=$LONGEST+3

     # The number of entries in each column
     COLHEIGHT=10

     # Start the row counter at 0
     row=0

     # Start the "character" column counter at the left indent
     col=$LEFTINDENT

     # Read in each line of the file
     for ENTRY in `grep -v ^# $MENUFILE`; do

        # Move cursor to the right according to the col variable
        for (( i=1; i<=$col; i++ )); do
           tput cuf1
        done

        # Sift out the number from the name
        ENTNUM=`echo $ENTRY | awk -F':' '{print $1}'`
        # Pad single digits with a space to align on the parenthesis
        if [[ $ENTNUM -lt 10 ]]; then
           ENTNUM=" $ENTNUM"
        fi
        ENTNAME=`echo $ENTRY | awk -F':' '{print $2}'`

        # Write out the menu choice
        echo -n "${ENTNUM})$ENTNAME"

        # Increment the row counter
        let row=$row+1

        # Position the cursor for the next write
        if [[ $row -lt $COLHEIGHT ]]; then
           #If the row is less than the COLHEIGHT
           #Set the cursor to the beginning of the line
           tput cr
           #And drop it down one row
           tput cud1
        elif [[ $row -eq $COLHEIGHT ]]; then
           #If the number of lines written is equal to the COLHEIGHT we need
           # to start another column.

           #move back up to the first row
           for (( i=1; i<$COLHEIGHT; i++ )); do
              tput cuu1
           done

           #add COLWIDTH to the column width so the cursor will start the correct
           #number of spaces to the right
           let col=$col+$COLWIDTH

           # Set the cursor to the beginning of the line
           tput cr

           #reset the row counter so we know when we reach the next row
           row=0
        fi

     done

     #Set the final cursor position beneath the menu
     let finalmove=$COLHEIGHT-$row
     tput cr
     for (( i=1; i<=$finalmove; i++ )); do
        tput cud1
     done
   else
      echo "FAILURE"
   fi

}

#-----------------
# Function: f_IsNetUp
#-----------------
# Attempts to determine if the network is functional by pinging
# the default gateway.  While it is possible to have rudimentary
# network without a default gateway, this seeks to answer whether
# we have "full" networking with routing etc...
#-----------------
# Usage: f_IsNetUp
#-----------------
# Returns: YES | NO

f_IsNetUp () {
   RESULT=NO
   DEFAULT_GW=`f_FindDefaultGW`
   TO=10
   WAIT=0
   FLAG=/tmp/inu${TS} 
   # If you don't have a default gateway, consider the network down
   if [[ $DEFAULT_GW != FAILURE ]]; then
      # The ping check has to be backgrounded to make sure that we can kill it if it hangs
      # And because it is backgrounded it is difficult to read a variable set by it, so we're touching
      # A file instead
      if [[ -n `ping -w 1 -c 2 -q $DEFAULT_GW 2>&1 | egrep ' 0% packet| 50% packet'` ]]; then touch $FLAG; fi &
      if [[ -n `/sbin/arping -c3 $DEFAULT_GW 2>&1 | tail -1 | egrep -v ' 0 response'` ]]; then touch $FLAG; fi &
      while [[ -n `jobs -l` ]]; do
        jobs 2>&1 > /dev/null
        sleep 1
        let WAIT=$WAIT+1
        if [[ $WAIT -ge $TO ]]; then
           JPID=`jobs -l | awk '{print $2}'`
           if [[ -n $JPID ]]; then kill -9 $JPID; fi
        fi
      done
   fi
   
   # If the file got touched then the network is up, in addition to
   # Changing the flag, we need to remove the file for future checks
   if [[ -f $FLAG ]]; then /bin/rm $FLAG; RESULT=YES; fi
   
   echo $RESULT
}

#-----------------
# Function: f_OnIntranet
#-----------------
# Attempts to determine if we are on the internal network
# This should not be run unless basic network connectivity
# has been determined
#-----------------
# Usage: f_OnIntranet
#-----------------
# Returns: TRUE | FALSE

f_OnIntranet () {
   RESULT=FALSE
   TO=5
   FLAG=/tmp/aw${TS}
   NSLIST="10.252.13.135 10.252.13.134 10.252.13.133 10.252.26.4"
   DOMLIST='acmeplaza.com|acme.com|acmetest.com'
   for NS in $NSLIST; do
      WAIT=0
      if [[ ! -f $FLAG ]]; then
         if [[ -n `nslookup $NS $NS | egrep "$DOMLIST"` ]]; then touch $FLAG; fi &
         while [[ -n `jobs -l` ]]; do
            jobs 2>&1 > /dev/null
            if [[ $WAIT -ge $TO ]]; then
               JPID=`jobs -l | grep 'nslookup' | awk '{print $2}'`
               if [[ -n $JPID ]]; then kill -9 $JPID; fi
            fi
            sleep 1
            let WAIT=$WAIT+1
         done
      fi
   done

   # If the file got touched then we're on the west network, in addition to
   # Changing the flag, we need to remove the file for future checks
   if [[ -f $FLAG ]]; then /bin/rm $FLAG; RESULT=TRUE; fi

   echo $RESULT

}


#-----------------
# Function: f_FindPubIF
#-----------------
# Attempts to determine which interface to use as the public interface.
# It will check the following items in order to determine which to use:
#    -The interface assigned to the default gateway
#    -The first interface with a real IP plumbed up
#    -Network configuration files
# If there is no existing public interface, it will then try to determine
# which interface to use as the public interface.  It will do so by
# checking link status.  
# 
#-----------------
# Usage: f_FindPubIF
#-----------------
# Returns: <IFNAME> | FAILURE

f_FindPubIF () {
    
   CONFDIR=/etc/sysconfig/network-scripts 

   # Gather some information
   GW=`f_FindDefaultGW`
   PUBIP=`f_FindPubIP`

   # Get a list of all of the eligible interfaces currently active
   IFLIST=
   for IF in `/sbin/ifconfig -a | egrep -v "^ |^$|lo|usb" | awk '{print $1}' | awk -F':' '{print $1}'`; do
      IFLIST="$IFLIST $IF"
   done

   # Get a list of all of the config files that have IPADDR set
   IFCFGLIST=
   for f in `ls $CONFDIR | grep ^ifcfg- | egrep -v "\.|ifcfg-lo|ifcfg-usb*"`; do
      if [[ -n `grep "^IPADDR=" ${CONFDIR}/${f}` ]]; then
         IFCFGLIST="$IFCFGLIST $f"
      fi
   done


   # Attempt one - which interface is assigned to the default gateway? 
   if [[ $GW != FAILURE ]]; then
      PUBIF=`/sbin/route | grep "$GW" | awk '{print $NF}'`
   fi

   # Attempt two - if there IS a public IP, which interface is it attached to?
   if [[ -z $PUBIF ]] && [[ $PUBIP != FAILURE ]]; then
      for IF in $IFLIST; do
         if [[ `f_IPforIF $IF` == $PUBIP ]]; then
            PUBIF=$IF
         fi
      done
   fi
   
   # Attempt three - do any of the valid interfaces have an IP in the same subnet as the gateway?
   if [[ -z $PUBIF ]] && [[ $GW != FAILURE ]]; then
      FTO=`echo $GW | awk -F'.' '{print $1"."$2"."$3"."}'`
      for IF in $IFLIST; do
         IFIP=`f_IPforIF $IF`
         if [[ -z $PUBIF ]] && [[ -n `echo $IFIP | grep "^${FTO}"` ]]; then
            PUBIF=$IF
         fi
      done
   fi
   
   # Attempt four - what is the first interface with an ip plumbed up on it?
   if [[ -z $PUBIF ]]; then   
      for IF in $IFLIST; do
         IFIP=`f_IPforIF $IF`
         if [[ -z PUBIF ]] && [[ -n `echo $IFIP|  grep -v 'NONE|127.0.0.1'` ]]; then
            PUBIF=$IF
         fi
      done
   fi

   # At this point it's safe to say that there is no recognizable network status
   # Or configuration from which to pick the public interface.
  
   # Attempt five - what is the first interface with an active link?

   if [[ -z $PUBIF ]]; then
      for IF in $IFLIST; do
         # Sometimes the interface has to be brought up before it will properly
         # report a link.  So we'll check each interface to see if it's up, and if
         # not, we'll plumb it before looking for a link.
         WASDOWN=
         if [[ -z `/sbin/ifconfig | egrep -v '^$|^ ' | grep "^$IF"` ]]; then
            /sbin/ifconfig $IF up
            sleep 1
            WASDOWN=YES
         fi
         if [[ -z $CANDIDATE ]] && [[ -n `/sbin/ethtool $IF 2>&1 | grep -i 'Link detected:' | grep -i 'yes'` ]]; then
            CANDIDATE=$IF
            CANDIDATE_CFG="${CONFDIR}/ifcfg-${CANDIDATE}"
            # Bonding drivers often lie about their link status, so we have to
            # disregard the results we get back from them. We'll check the real 
            # interface later to see if it's part of a bond.
            if [[ -n `echo $IF | grep "^bond"` ]]; then 
               unset CANDIDATE
            elif [[ -s $CANDIDATE_CFG ]] && [[ -n `grep "^MASTER=" $CANDIDATE_CFG` ]]; then
               CANDIDATE=`grep "^MASTER=" $CANDIDATE_CFG | awk -F'=' '{print $2}'`
            fi
         fi
         if [[ $WASDOWN == YES ]]; then
            /sbin/ifconfig $IF down
         fi
      done
      if [[ -n $CANDIDATE ]]; then
         PUBIF=$CANDIDATE
      fi
   fi
   
   # At this point, if we still haven't found the public interface, there is nothing
   # to distinguish one interface from another so we'll admit defeat.

   if [[ -z $PUBIF ]]; then
      RESULT=FAILURE
   else
      RESULT=$PUBIF
   fi

   echo $RESULT
   
   
}

#-----------------
# Function: f_AskPubIF
#-----------------
# Interactive
# Scans the system for usable ethernet devices
# then displays the devide names and descriptions
# and asks the user to choose a device
# NOTE: this function will not exit until a valid
# selection has been made
#-----------------
# Usage: f_AskPubIF
#-----------------
# Returns: <Ethernet Device Name>

f_AskPubIF () {

   unset PUBIF 
   echo "Please select a public interface from the following:" 1>&2
   echo "" 1>&2

   # Use the name of the first interface as a default  
   FIRST_IF=`/sbin/ifconfig -a | egrep -v "^ |^$|lo|usb|sit" | awk '{print $1}' | head -1`

   # Look at each interface that currently has a driver loaded
   for IF in `/sbin/ifconfig -a | egrep -v "^ |^$|lo|usb|sit" | awk '{print $1}'`; do

      # If we see a bonded device, display the names of its slaves as a description
      if [[ -n `echo $IF | grep bond` ]]; then
         unset SLAVES
         for SLAVE in `grep "MASTER=${IF}" /etc/sysconfig/network-scripts/ifcfg-eth*`; do
            SLAVES="$SLAVES `echo $SLAVE | awk -F'ifcfg-' '{print $2}' | awk -F':' '{print $1}'`"
         done
         IF_DESC="( slaves:$SLAVES )"
      # If we see something that is NOT a bond or virutal device...
      else
         # Get the PCI address from ethtool
         IF_PCI=`/sbin/ethtool -i $IF | grep bus-info | awk -F':' '{print $3":"$4}'`
         # ...and the description from lspci
         IF_DESC="(`/sbin/lspci | grep "^$IF_PCI" | awk -F': ' '{print $NF}' | cut -c 1-60 | sed -e 's/($//;s/ $//'`...)"
      fi

      # Display the device and description
      echo "   $IF $IF_DESC" 1>&2
   done
   echo " " 1>&2
   while [[ -z $PUBIF ]]; do
      read -p "Public Interface [$FIRST_IF]: " GPUBIF 
      if [[ -z $GPUBIF ]]; then
         PUBIF=$FIRST_IF
      elif [[ -z `/sbin/ifconfig -a | egrep -v "^ |^$|lo|usb|sit" | grep ^${GPUBIF}` ]]; then
         echo "Error: \"$GPUBIF\" is not a valid selection."
         read -p "      Press enter to try again." JUNK
         UNSET GPUBIF
         tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el; tput cuu1; tput el
      else
         PUBIF=$GPUBIF
      fi
   done

   echo $PUBIF

}
   


#-----------------
# Function: f_SpinningCountdown
#-----------------
# Displays a visual countdown bar that shrinks as it approaches
# zero and displays a spinner to increase visibility.  The idea
# is to give as much opportunity to cancel as possible before 
# doing some disruptive action.
#-----------------
# Usage: f_SpinningCountdown <SEC>
#-----------------
# Returns: NULL
f_SpinningCountdown() {


   COUNT=$1
   MCOUNT=$COUNT

   while [[ $MCOUNT -ge 0 ]]; do
   DASHES=
   for (( i=1; i<=$MCOUNT; i++ )); do
      DASHES="${DASHES}="
   done
   echo -n "[$DASHES"
   echo -n "$MCOUNT]"
   tput sc
   # Each character is displayed for 1/16th of a second
   # Do all of them 4 times for one whole second
   for j in {1..4}; do
      tput rc
      echo -n "|"
      sleep .053
      tput rc
      echo -n "/"
      sleep .053
      tput rc
      echo -n "-"
      sleep .053
      tput rc
      echo -n '\'
      sleep .053
   done

   let MCOUNT=$MCOUNT-1
   tput cr
   tput el


   done

}

#-----------------
# Function: f_PathOfScript
#-----------------
# Returns the location of the script, irrespective of where it
# was launched.  This is useful for scripts that look for files
# in their current directory, or in relative paths from it
#
#-----------------
# Usage: f_PathOfScript
#-----------------
# Returns: <PATH>

f_PathOfScript () {

   unset RESULT

   # if $0 begins with a / then it is an absolute path
   # which we can get by removing the scipt name from the end of $0
   if [[ -n `echo $0 | grep "^/"` ]]; then
      BASENAME=`basename $0`
      RESULT=`echo $0 | sed 's/'"$BASENAME"'$//g'`

   # if this isn't an absolute path, see if removing the ./ from the
   # beginning of $0 results in just the basename - if so
   # the script is being executed from the present working directory
   elif [[ `echo $0 | sed 's/^.\///g'` == `basename $0` ]]; then
      RESULT=`pwd`

   # If we're not dealing with an absolute path, we're dealing with
   # a relative path, which we can get with pwd + $0 - basename
   else
      BASENAME=`basename $0`
      RESULT="`pwd`/`echo $0 | sed 's/'"$BASENAME"'$//g'`"
   fi

   echo $RESULT

}

#-----------------
# Function: f_GetVendor
#-----------------
# Returns the name of the hardware vendor for the current server
# Current possible responses:
#    IBM
#    HP
#    VMWARE
#    DELL
#    UNK
#-----------------
# Usage: f_GetVendor
#-----------------
# Returns: <Vendor>

f_GetVendor () {

   DMIDECODE=/usr/sbin/dmidecode
   unset RESULT
   if [[ -n `$DMIDECODE -t system 2>&1 | grep Manufacturer: | grep -i VMWARE` ]]; then
      RESULT=VMWARE
   elif [[ -n `$DMIDECODE -t system 2>&1 | grep Manufacturer: | grep -i IBM` ]]; then
      RESULT=IBM
   elif [[ -n `$DMIDECODE -t system 2>&1 | grep Manufacturer: | grep -i HP` ]]; then
      RESULT=HP
   elif [[ -n `$DMIDECODE -t system 2>&1 | grep Manufacturer: | grep -i DELL` ]]; then
      RESULT=DELL
   elif [[ -n `$DMIDECODE -t system 2>&1 | grep Manufacturer: | grep -i Cisco` ]]; then
      RESULT=CISCO
   elif [[ -n `$DMIDECODE -t system 2>&1 | grep Manufacturer: | grep -i Microsoft` ]]; then
      RESULT=MICROSOFT
   else
      RESULT=UNK
   fi
   echo $RESULT

}

#-----------------
# Function: f_GetImageServerIP
#-----------------
# Attempts to ascertain the correct IP address for the image server
#-----------------
# Usage: f_GetImageServerIP
#-----------------
# Returns: <IP> 
f_GetImageServerIP () {
   IMGSRVPHN=imageprimary.acmeplaza.com
   IMGSRVMN=satellite5.acmeplaza.com
   HCIP=10.252.14.5
   unset IMGSRVIP
   
   # First try the private hostname
   IMGSRVIP=`getent hosts $IMGSRVPHN | awk '{print $1}'`
 
   # Next try the machine hostname
   if [[ -z $IMGSRVIP ]]; then
      IMGSRVIP=`getent hosts $IMGSRVMN | awk '{print $1}'`
   fi

   # Last fall back on the hard-coded IP
   if [[ -z $IMGSRVIP ]]; then
      IMGSRVIP=$HCIP
   fi

   echo $IMGSRVIP

}

#-----------------
# Function: f_GetPhysicalDriveCount
#-----------------
# Attempts to ascertain the number of physical drives installed
# on a server.  Negative numbers represent error codes
# Error Codes:
#   -1 unknown vendor
#   -2 missing utility
#   -3 unknown adapter
#-----------------
# Usage: f_GetPhysicalDriveCount
#-----------------
# Returns: <Drive Count> | <Error Code>
f_GetPhysicalDriveCount () {

   VENDOR=`f_GetVendor`

   # Figure out architecure
   if [[ -n `uname -m | grep x86_64` ]]; then
      ARCH=64
   else
      ARCH=32
   fi

   # Break down the process by vendor
   if [[ $VENDOR == HP ]]; then
      if [[ ! -x /usr/sbin/hpacucli ]]; then
         PDC="-2"
      else
         PDC=`/usr/sbin/hpacucli controller all show config | grep physicaldrive | wc -l`
      fi
   elif [[ $VENDOR == IBM ]]; then
      # Check for adaptec RAID
      if [[ -n `/sbin/lspci | grep -i raid | grep -i adaptec` ]]; then
         ARCCONF=/sbin/arcconf
         if [[ ! -x $ARCCONF ]]; then
            PDC="-2"
         else
            CC=`$ARCCONF getconfig 9 | grep "Controllers found" | awk '{print $NF}'`
            tdc=0
            for (( c=1; c <= CC; c++ )); do
              dc=`$ARCCONF getconfig $c | grep -i "Device is a Hard drive" | wc -l`
              let tdc=$tdc+$dc
            done
            PDC=$tdc
         fi
            
      # Check for LSI RAID
      elif [[ -n `/sbin/lspci | grep -i raid | grep -i LSI` ]]; then
         if [[ $ARCH == 64 ]]; then
            MEGACLI=/opt/MegaRAID/MegaCli/MegaCli64
         else
            MEGACLI=/opt/MegaRAID/MegaCli/MegaCli
         fi
         tdc=0
         for dc in `$MEGACLI -PDGetNum -aALL | grep "Physical Drives" | awk '{print $NF}'`; do 
            let tdc=$tdc+$dc
         done
         PDC=$tdc
      # Check for older LSI storage controller
      elif [[ -n `/sbin/lspci | grep -i storage | grep -i LSI` ]]; then
         PDC=`cat /proc/scsi/scsi | sed ':a;N;$!ba;s/\n//g; s/Host:/\nHost:/g' | grep Direct-Access | egrep -v 'LSI|ROM' | wc -l`
      else
         PDC="-3"
      fi
   elif [[ $VENDOR == DELL ]]; then
      # Best guess for DELL - has not been tested
      PDC=`cat /proc/scsi/scsi | sed ':a;N;$!ba;s/\n//g; s/Host:/\nHost:/g' | grep Direct-Access | egrep -v 'Dell|ROM' | wc -l`
   elif [[ $VENDOR == VMWARE ]]; then
      # For practical purposes, the physical drive count is the same as the logical drive count.
      PDC=`fdisk -l 2>&1 | grep ^Disk | egrep -v 'doesn|mapper|identifier' | wc -l`
   else
      PDC="-1"
   fi
           
   echo $PDC 
}

#------------------------------------------------------
# Function f_IsHostValid
# Purpose: Check if a hostname can be resolved to an IP
#          if that IP is live and listening on specified port
# Usage: f_IsHostValid <hostname> <port>
# Returns: 0 if the host is valid
#          1 if the host is a hostname and failed a DNS lookup
#          2 if the host failed a ping test
#          3 if the host is not listening to <port>
#          4 if the port is not valid or missing
#------------------------------------------------------

f_IsHostValid () {
   hostToCheck=$1
   portOfInterest=$2
   HostValid=TRUE
   ExitCode=0

   # Check to see if we were passed an IP or a hostname
   #if [[ ! `echo $hostToCheck | sed 's/\.//g'` =~ ^[0-9]+$ ]]; then
   if [[ -z `echo $hostToCheck | sed 's/\.//g' | egrep "^[0-9]+$"` ]]; then
      # Host does not appear to be an IP so verify valid lookup
      if [[ -z `getent hosts $hostToCheck` ]]; then
         ExitCode=1
         HostValid=FALSE
      fi
   fi

   if [[ -z $portOfInterest ]]; then
      # Port was not passed to the command
      ExitCode=4
      HostValid=FALSE
   else
      if [[ "$portOfInterest" -lt "0" ]] || [[ "$portOfInterest" -gt 65534 ]]; then
         ExitCode=4
         HostValid=FALSE
      fi
   fi

   # Only do subsequent tests if the host hasn't already failed

   # Ping test
   #if [[ $HostValid == TRUE ]]; then
   #   if [[ -n `ping -c1 -w2 $hostToCheck | grep "0 received"` ]]; then
   #      ExitCode=2
   #      HostValid=FALSE
   #   fi
   #fi

   # SSH test

   if [[ $HostValid == TRUE ]]; then
      if [[ -z `/usr/bin/nmap -P0 $hostToCheck -p $portOfInterest 2>&1 | grep "^$portOfInterest/" | grep "open"` ]]; then
         ExitCode=3
         HostValid=FALSE
      fi
   fi

   echo $ExitCode
}

#------------------------------------------------------
# Function f_SetLogLevel
# Purpose: Modifies redirection variables based on
#          debug level passed in
#
# Usage: f_SetLogLevel <level>
#
#        levels
#          0 basic reporting, logfile only
#          1 basic reporting, logfile and screen
#          2 verbose reporting, logfile only
#          3 verbose reporting, logfile and screen
#          4 maximum verbose reporting, logfile only
#          5 maximum verbose reporting, logfile and screen
#
#          NOTE: nohup will prevent psync.sh from outputting to the
#                screen
#
# Returns: 0 log level is valid
#          1 log level is not valid
#
#    Note: LOG1, LOG2 and LOG3 variables are various degrees of
#          verbosity.  After loglevel is set you will pipe the
#          output you want to be logged to one of those variables
#          Send general stuff that should always be logged to $LOG1
#          Use the higher level variables for debug style messages.
#------------------------------------------------------
f_SetLogLevel () {

   LL=$1
   RETVAL=0

   unset LOG1 LOG2 LOG3

   case $LL in

      0) export LOG1="f_Log $LOGFILE"
         export LOG2="f_Log /dev/null"
         export LOG3="f_Log /dev/null"
         ;;
      1) export LOG1="tee -a $LOGFILE"
         export LOG2="f_Log /dev/null"
         export LOG3="f_Log /dev/null"
         ;;
      2) export LOG1="f_Log $LOGFILE"
         export LOG2="f_Log $LOGFILE"
         export LOG3="f_Log /dev/null"
         ;;
      3) export LOG1="tee -a $LOGFILE"
         export LOG2="tee -a $LOGFILE"
         export LOG3="f_Log /dev/null"
         ;;
      4) export LOG1="f_Log $LOGFILE"
         export LOG2="f_Log $LOGFILE"
         export LOG3="f_Log $LOGFILE"
         ;;
      5) export LOG1="tee -a $LOGFILE"
         export LOG2="tee -a $LOGFILE"
         export LOG3="tee -a $LOGFILE"
         ;;
      *) RETVAL=1
         export LOG1="f_Log $LOGFILE"
         export LOG2="f_Log /dev/null"
         export LOG3="f_Log /dev/null"
         ;;

   esac
   #echo $RETVAL

}


#------------------------------------------------------
# Function f_Log
# Purpose: Writes input a file - this is being used
#          because >> cannot be executed from a variable
#
# Usage: <command to log> 2>&1 | f_Log <logfile>
#
# Returns: 0 success
#          1 log file or directory not writable
#          2 invalid argument count
#------------------------------------------------------
f_Log () {

   unset N
   read N
   unset LF
   LF=$1
   RETVAL=0

   # If the logfile value passed in is empty, do nothing
   if [[ -z $LF ]]; then
      RETVAL=2
   # If the logfile value passed in is /dev/null, do nothing
   elif [[ "$LF" == "/dev/null" ]]; then
      RETVAL=0
   else
      # if the logfile doesn't exist, try to create it
      if  [[ ! -f $LF ]]; then
         touch $LF 2>&1 >>/dev/null
      fi
      # whether we tried to create it or not, see if the logfile
      # is writeable
      if [[ ! -w $LF ]]; then
         RETVAL=1
      elif [[ -n "$N" ]]; then
         # if the file is writeable, and we're not dealing with a
         # null string, then write it.
         echo "$N" >> $LOGFILE
      fi

   fi

   #return $RETVAL

}

#------------------------------------------------------
# Function f_IsIPInCIDR
# Purpose: Verify whether an IP address is in a CIDR block
#
# Usage: <CIDR> <IP>
#
# Returns: 0 IP is in CIDR
#          1 IP is not in CIDR
#          2 IP is not valid
#          3 CIDR is not valid
#          4 Invalid argument count
#------------------------------------------------------
f_IsIPInCIDR() {

   unset l_CIDR l_IP HIGHEST LOWEST RETVAL
   l_CIDR=$1
   l_IP=$2

   if [[ -n $l_IP ]]; then

      # Verify we have a valid IP address
 

      if [[ `f_ValidIPv4 $l_IP` == TRUE ]]; then
   
         # Validate CIDR provided  
         # Separate CIDR into network and PREFIX
   
         l_CN=`echo $l_CIDR | awk -F'/' '{print $1}'`
         l_CP=`echo $l_CIDR | awk -F'/' '{print $2}'`
   
         # Check the prefix
         # Valid prefixes are numeric and between 1 and 32
         #if [[ $l_CP =~ ^[0-9]+$ ]] && [[ $l_CP -ge 1 ]] && [[ $l_CP -le 32 ]]; then     
         if [[ -n `echo $l_CP egrep "^[0-9]+$"` ]] && [[ $l_CP -ge 1 ]] && [[ $l_CP -le 32 ]]; then     

            # Expand the CIDR network if needed
            while [[ `echo $l_CN | sed 's/\./ /g' | wc -w` -lt 4 ]]; do
               l_CN="${l_CN}.0"
            done

            # Validate the expanded CIDR network is a valid IPv4 number
            if [[ `f_ValidIPv4 $l_CN` == TRUE ]]; then

               # Find the lowest valid host IP for the given CIDR
               LOWEST=`echo $l_CN | awk -F'.' '{print $1"."$2"."$3".1"}'`
         
               # Find the highest valid host IP for the given CIDR
               HIGHEST=`/bin/ipcalc -sb $l_CIDR | sed 's/^BROADCAST=//' | awk -F'.' '{print $1"."$2"."$3"."($4 - 1)}'`
         
               # Determine if l_IP is "higher" than LOWEST
      
               if [[ `f_IP_ABS $l_IP` -ge `f_IP_ABS $LOWEST` ]] && [[ `f_IP_ABS $l_IP` -le `f_IP_ABS $HIGHEST` ]]; then
                  RETVAL=0
               else
                  RETVAL=1
               fi
            else
               # CIDR network is invalid
               RETVAL=3

            fi

         else

            # CIDR prefix is invalid
            RETVAL=3

         fi
      else
         # IPv4 provided is invalid
         RETVAL=2
      fi

   else
      # If there is no second argument, then we have an invalid argument count
      RETVAL=4
   fi

   echo $RETVAL

}

#------------------------------------------------------
# Function f_IP_ABS
# Purpose: Converts an IPv4 address into an absolute value
#          To allow mathematical comparisons
#
# Usage: f_IP_ABS <IPv4>
#
# Returns: 1 IP is not a valid IPv4 address
#          <Absolute Value of the IP address>
#------------------------------------------------------

f_IP_ABS() {

   unset l_IP ABSVO1 ABSVO2 ABSV03 ABSV04 ABSV
   l_IP=$1

   ABSVO1=`echo $l_IP | awk -F'.' '{print $1" * 255 * 255 * 255"}' | bc`
   ABSVO2=`echo $l_IP | awk -F'.' '{print $2" * 255 * 255"}' | bc`
   ABSVO3=`echo $l_IP | awk -F'.' '{print $3" * 255"}' | bc`
   ABSVO4=`echo $l_IP | awk -F'.' '{print $4}'`
   let ABSV=${ABSVO1}+${ABSVO2}+${ABSVO3}+${ABSVO4}

   echo $ABSV

}

#------------------------------------------------------
# Function f_setStep()
# Purpose: To manage step position for resuming a script
#          in case of premature exit
#
# Usage: f_setStep <start|end> <step #> <step file>
#
# Where: <start|end> indicates that the step is being started
#                    or ended
#        <step #>    indicates the step number
#        <step file> indicates the file to store the current
#                    step in for resuming
#
# Returns: 0 for success
#          1 for invalid argument count
#          2 for invalid mode
#          3 for invalid step number
#------------------------------------------------------
f_setStep() {
   unset sMODE sSTEP nSTEP sRETCODE
   sMODE=$1
   sSTEP=$2

   # Check for valid number of arguments
   if [[ $# -lt 2 ]]; then
      sRETCODE=1
   else
      if [[ $sMODE != "start" ]] && [[ $sMODE != "end" ]]; then
         sRETCODE=2
      elif [[ -z `echo $sSTEP | egrep "^[0-9]+$"` ]]; then
         sRETCODE=3
      fi
   fi

   if [[ -z $sRETCODE ]]; then
      # Check to see if a "STEPFILE" variable has been globally set

      STEPFILE=`f_getStepFile`

      # If we're starting the step, set the stepfile to the step we're starting
      # If we're ending the step, increment the step by 1
      if [[ $sMODE == "start" ]]; then
         echo $sSTEP > $STEPFILE
      elif [[ $sMODE == "end" ]]; then
         let nSTEP=$sSTEP+1
         echo $nSTEP > $STEPFILE
      fi

      sRETCODE=0
   fi
}

#------------------------------------------------------
# Function f_getStepFile()
# Purpose: Returns the name of the file recording the last
#          attempted step, either from a global "STEPFILE"
#          variable defined in the script or from a
#          filename under /root derrived from the name of
#          the script itself.
#
# Usage: f_getStepFile
#
# Returns: The qualified path to the step file
#------------------------------------------------------

f_getStepFile(){

   if [[ -z $STEPFILE ]]; then
      # if there is no STEPFILE variable, create one
      export STEPFILE="/root/."`basename $0`".step"
   fi

   echo $STEPFILE

}

#------------------------------------------------------
# Function f_getStep()
# Purpose: Reads the last attempted step from the step file
#
# Usage: f_getStep
#
# Returns: 0 if no file is found
#          or last attempted step number
#------------------------------------------------------

f_getStep(){
   # Default to step 0
   S=0

   STEPFILE=`f_getStepFile`

   # If the file doesn't exist, or is empty, then create it with Step 0
   # Otherwise set S to the value in the file
   if [[ ! -s $STEPFILE ]]; then
      echo $S > $STEPFILE
   else
      S=`cat $STEPFILE`
   fi

   echo $S

}

#------------------------------------------------------
# Function f_stepMsg()
# Purpose: Reports the result of a given step
#
# Usage: f_stepMsg <status> <step #> <step name> [<return code>]
#
# Where: <status> is one of: success, failure, skipped
#        <step #>    indicates the step number
#        <step name> is the filename or function name of the step
#        <return code> is the return code in case of failure
#
# Returns: NULL
#------------------------------------------------------

f_stepMsg(){
   STATUS=$1
   STEP=$2
   PART=$3
   RETCODE=$4

   if [[ $STATUS == failure ]]; then
      echo ""
      echo "@!!!!!!!!!!!!!!!!!!!!!!!!FAILURE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#"
      echo "@  STEP: $STEP"
      echo "@  ACTION: $PART"
      echo "@  RETURN CODE: $RETCODE"
      echo "@  Address the issue and re-run $0 to resume."
      echo "@!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#"
      echo ""
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`: Step $STEP failed on action $PART with return code $RETCODE" | $LOG1
      fi
   elif [[ $STATUS == success ]]; then
      echo "Step $STEP \`$PART\` succeeded."
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`: Step $STEP \`$PART\` succeeded." | $LOG1
      fi
   elif [[ $STATUS == skipped ]]; then
      echo "Step $STEP \`$PART\` skipped."
      if [[ -n $LOGFILE ]] && [[ -n $VTS ]]; then
         echo "`$VTS`: Step $STEP \`$PART\` skipped." | $LOG1
      fi
   fi

}

#------------------------------------------------------
# Function f_runStep()
# Purpose: Runs a command IF it has not been run yet
#          based on the "step" system of keeping track
#
# Usage: f_runStep <step #> <script or function>
#
# Where: <step #>    indicates the step number
#        <script or function> is the name of the script
#                             function or executable
#                             that will be run as step #
#
# Returns:  0 for success
#          -1 for invalid argument count
#          -2 for non-numeric step
#          -3 for invalid script/function/exe
#
#------------------------------------------------------

f_runStep(){

   unset rRETCODE
   rSTEP=$1
   rCOMM="${@:2}"
   rSCRIPT=`echo $* | awk '{print $2}'`

   # Check for valid number of arguments
   if [[ $# -lt 2 ]]; then
      rRETCODE=-1
   else
      # Set error if step # is not numeric
      if [[ -z `echo $rSTEP | egrep "^[0-9]+$"` ]]; then
         rRETCODE=-2
      fi

      # Set error if SCRIPT is not a valid function or file
      type $rSCRIPT 2>&1 > /dev/null
      SCHECK=$?
      if [[ $SCHECK != 0 ]]; then
         rRETCODE=-3
      fi

   fi

   # If the command syntax looks good, and this step hasn't been completed yet
   # then attempt to run it
   if [[ -z $rRETCODE ]] && [[ `f_getStep` -le $rSTEP ]]; then

      # Declare the start of the step
      f_setStep start $rSTEP

      # Run the command and save the return code
      #$rSCRIPT
      #rRETCODE=$?
      if [[ -n $LOGFILE ]]; then
         $rCOMM 2>&1 | sed "s/^/`$VTS`: /g" | tee -a $LOGFILE
         rRETCODE="${PIPESTATUS[0]}"
      else
         $rCOMM
         rRETCODE=$?
      fi

   fi


   # If there IS a return code then we need to check to see if it's 0 or non-0
   if [[ -n $rRETCODE ]]; then
      if [[ $rRETCODE != 0 ]] ; then
         f_stepMsg failure $rSTEP $rSCRIPT $rRETCODE
         echo $(f_exitScript)
      else
         f_stepMsg success $rSTEP $rSCRIPT $rRETCODE
         f_setStep end $rSTEP
      fi

   else
      # If there is still no return code then we're skipping this step
      f_stepMsg skipped $rSTEP $rSCRIPT

   fi

}

#------------------------------------------------------
# Function f_exitScript
# Purpose: Triggers a trap to exit the script from within
#          a function.  This is used instead of handling
#          the return code of the function to allow for
#          scripts to use STDOUT and STDIN unhindered.
#
# Usage: set a trap with the following syntax:
#        'trap "exit1" TERM'
#
#        export the script's PID as a global variable:
#        'export SPID=$$'
#
#        spring the trap from within a function with:
#        'echo $(f_exitScript)'
#
#------------------------------------------------------

f_exitScript(){
   kill -s TERM $SPID
}

trap "exit 1" TERM
export SPID=$$
#------------------------------------------------------
# Function f_testFailure()
# Purpose: returns non-zero to test failure handling
#
# Returns: 250
#------------------------------------------------------
f_testFailure(){
   return 250
}

#------------------------------------------------------
# Function f_testSuccess()
# Purpose: returns zero to test success handling
#
# Returns: 0
#------------------------------------------------------

f_testSuccess(){
   return 0
}

#------------------------------------------------------
# Function f_InDMZ()
# Purpose: evaluates whether the server is in a recognized
#          DMZ. Network must already be configured for this
#          function to work properly.
#
# Usage: f_InDMZ
#
# Returns: TRUE if in a known DMZ
#          FALSE if not in a known DMZ
#          FAILURE if unable to evaluate.
#------------------------------------------------------

f_InDMZ(){
   ID_PUBIP=`f_FindPubIP`
   if [[ -n $ID_PUBIP ]] && [[ $ID_PUBIP != FAILURE ]]; then
      ANSWER=FALSE
      DMZ_RANGES="192.174.72.0/21 74.126.50.0/24"
      for DMZR in `echo $DMZ_RANGES`; do
         if [[ `f_IsIPInCIDR $DMZR $ID_PUBIP` == 0 ]]; then
            ANSWER=TRUE
         fi
      done
   elif [[ -f /maint/.forceDMZTRUE ]]; then
      ANSWER=TRUE
   else
      ANSWER=FAILURE
   fi

   echo $ANSWER
}

#------------------------------------------------------
# Function f_RHELChangeHostname()
# Purpose: Changes the hostname on a RHEL-based linux server
#
# Usage: f_RHELChangeHostname <old hostname> <new hostname>
#
#
# Returns:  0 for success
#          -1 for invalid argument count
#          -2 for non-RHEL system
#          -3 if old hostname is not found
#          -4 if needed files are not writable
#
#------------------------------------------------------

f_RHELChangeHostname(){

   unset RETCODE
   OLDHN=$1
   NEWHN=$2
   NETCONF=/etc/sysconfig/network
   HOSTS=/etc/hosts


   # Check for valid number of arguments
   if [[ $# -lt 2 ]]; then
      RETCODE=-1
   fi

   # Set error if NETCONF isn't found
   if [[ ! -f $NETCONF ]]; then
      RETCODE=-2
   fi

   # Set error if the old hostname isn't visible
   #if [[ -z `grep -i $OLDHN $NETCONF` ]] && [[ -z `grep -i $OLDHN $HOSTS` ]]; then
   #   RETCODE=-3
   #fi

   # Set error if needed files are not writable
   if [[ ! -w $NETCONF ]] || [[ ! -w $HOSTS ]]; then
      RETCODE=-4
   fi

   # If we've passed all of the checks, then attempt the update
   if [[ -z $RETCODE ]]; then
      TS=`date +%Y%m%d%H%M%S`

      # Change hostname in the network file
      sed -i.${TS} "s/^HOSTNAME=$OLDHN$/HOSTNAME=$NEWHN/I" $NETCONF
      OP1=$?

      # Change hostname in the hosts file
      sed -i.${TS} "s/$OLDHN/$NEWHN/gI" $HOSTS
      OP2=$?

      # In case the system was originally installed as "localhost"
      perl -pi -e "s/^.*localhost.localdomain/127.0.0.1       localhost.localdomain/" $HOSTS

      # Actively set the new hostname
      hostname $NEWHN
      OP3=$?

      # Export the HOSTNAME variable
      export HOSTNAME=$NEWHN

      if [[ $OP1 == 0 ]] && [[ $OP2 == 0 ]] && [[ $OP3 == 0 ]]; then
         RETCODE=0
      else
         RETCODE="${OP1}${OP2}${OP3}"
      fi

   fi

   echo $RETCODE
   exit $RETCODE

}

#------------------------------------------------------
# Function f_WgetProgOnly
# Purpose: Filters WGET output to only show the progress bar
# Note: snatched from the Intarweb
#
# Usage: <wget command> | f_WgetProgOnly
#
#------------------------------------------------------

f_WgetProgOnly ()
{
    local flag=false c count cr=$'\r' nl=$'\n'
    while IFS='' read -d '' -rn 1 c
    do
        if $flag
        then
            printf '%c' "$c"
        else
            if [[ $c != $cr && $c != $nl ]]
            then
                count=0
            else
                ((count++))
                if ((count > 1))
                then
                    flag=true
                fi
            fi
        fi
    done
}
