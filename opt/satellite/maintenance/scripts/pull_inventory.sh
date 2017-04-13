#!/bin/bash

#################FUNCTION DEFINITIONS########################

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

cd `f_PathOfScript`

# Include common_functions.h
if [[ -s /opt/sa/scripts/common_functions.sh ]]; then
   source /opt/sa/scripts/common_functions.sh
elif [[ -s common_functions.sh ]]; then
   source common_functions.sh
else
   echo "Critical dependency failure: unable to locate common_functions.h"
   exit 1
fi


#### SETTINGS ####

# If VERBOSE is 0, output is suppressed, if it is non-zero output is displayed
VERBOSE=0

# Environment
. .sat.env

# Commands and arguments
HAMMER="/bin/hammer -u $USER -p $PASS"


# Generate a list of managed systems
# Format: <hostname>,<IP>
MSYSTEM_LIST=`$HAMMER host list | egrep -v '^-|^ID' | awk -F'|' '{print $2","$5}' | sed 's/ //g'`


# Override for testing
#MSYSTEM_LIST="kneoraolt002,10.252.12.184
#kneoraolt001,10.252.12.164"

# Begin main loop

# echo "$OS_HOSTNAME,$HW_CPU_CORES,$HW_CPU_THREADS,$HW_CPU_SOCKETS,$HW_CPU_VEND,$HW_CPU_NAME,$HW_CPU_SPEED,$NET_PUBIP,,$HW_MANU,$HW_PRODUCT,$OS_NAME $OS_RELEASE,Update $OS_UPDATE,$OS_VERSION,$HW_MEM_MB"

for MSYSTEM in $MSYSTEM_LIST; do

   OS_HOSTNAME=`echo $MSYSTEM | awk -F',' '{print $1}'`
   NET_PUBIP=`echo $MSYSTEM | awk -F',' '{print $2}'`

   if [[ -n `echo $MSYSTEM | grep '^virt-who-'` ]]; then
      continue
   fi

   FACTS=/tmp/.rsf
   if [[ -f $FACTS ]]; then /bin/rm $FACTS; fi
   curl -X GET -s -k -u ${USER}:${PASS}  https://${SATELLITE}/api/v2/hosts/$OS_HOSTNAME | python -mjson.tool > $FACTS

   if [[ ! -s $FACTS ]]; then
      echo "Error retrieving facts for $MSYSTEM"
   else

      # Get a physical core count by looking at how many unique core ids we have per physical id
      HW_CPU_SOCKETS=`grep "cpu::socket(s)" $FACTS | awk -F': ' '{print $2}' | sed 's/^"//;s/",$//'`
      if [[ -z $HW_CPU_SOCKETS ]] || [[ $HW_CPU_SOCKETS == 0 ]]; then
         HW_CPU_SOCKETS=1
      fi

      HW_CPU_CORES_PER_SOCKET=`grep "cpu::core(s)_per_socket" $FACTS | awk -F': ' '{print $2}' | sed 's/^"//;s/",$//'`
      if [[ -z $HW_CPU_CORES_PER_SOCKET ]] || [[ $HW_CPU_CORES_PER_SOCKET == 0 ]]; then
         HW_CPU_CORES_PER_SOCKET=1
      fi
 
      let HW_CPU_CORES=${HW_CPU_SOCKETS}*${HW_CPU_CORES_PER_SOCKET}
      
      if [[ $HW_CPU_CORES == 0 ]]; then
         HW_CPU_CORES=1
      fi

      HW_CPU_THREADS_PER_CORE=`grep "cpu::thread(s)_per_core" $FACTS | awk -F': ' '{print $2}' | sed 's/^"//;s/",$//'`
      if [[ -z $HW_CPU_THREADS_PER_CORE ]] || [[ $HW_CPU_THREADS_PER_CORE == 0 ]]; then
         HW_CPU_THREADS_PER_CORE=1
      fi

      let HW_CPU_THREADS=${HW_CPU_CORES}*${HW_CPU_THREADS_PER_CORE} 

   
      HW_CPU_NAME=$( grep -m1 "processor0" $FACTS | awk -F': ' '{print $2}' | tr -d '",' | sed 's/  */ /g' )
      if [[ -z $HW_CPU_NAME ]]; then
         HW_CPU_NAME=$( grep -m1 "lscpu::model_name" $FACTS | awk -F': ' '{print $2}' | tr -d '",' | sed 's/  */ /g' )
      fi
      HW_CPU_SPEED=$( grep -m1 "lscpu::cpu_mhz" $FACTS | awk -F': ' '{print $2}' | tr -d '",' | awk -F'.' '{print $1}')

      HW_CPU_VEND=$( grep -m1 "lscpu::vendor_id" $FACTS | awk -F': ' '{print $2}' | tr -d '",' )
      if [[ -z $HW_CPU_VEND ]]; then
         HW_CPU_VEND=`echo $HW_CPU_NAME | awk '{print $1}' | sed 's/(R)//'`
      fi
   
      ## Chipset info
      HW_MANU=$( grep '"manufacturer": ' $FACTS | awk -F': ' '{print $2}' | tr -d '",' )
      HW_PRODUCT=$( grep '"productname": ' $FACTS | awk -F': ' '{print $2}' | tr -d '",' )
      HW_SERIAL=$( grep 'dmi::system::serial_number' $FACTS | awk -F': ' '{print $2}' | sed 's/^"//g;s/",//g' )
      HW_MEM_MB=$( grep 'dmi::memory::size' $FACTS | egrep -v "No" | tr -d '",' | awk '{sum+=$2} END {print sum}' )
   
      ## OS Software Details
      OS_NAME=$( grep "distribution::name" $FACTS | awk -F': ' '{print $2}' | sed 's/^"//g;s/",//g' )
      OS_VERSION=$( grep 'distribution::version"' $FACTS | awk -F': ' '{print $2}' | sed 's/^"//g;s/",//g' )
      OS_RELEASE=$( echo $OS_VERSION | awk -F'.' '{print $1}' )
      OS_UPDATE=$( echo $OS_VERSION | awk -F'.' '{print $2}' )
   
      MISC_LOCATION=$( grep '"comment":' $FACTS | awk -F': ' '{print $2}' | sed 's/^"//g;s/",//g' | awk -F':' '{print $1}' | grep -v "null" )
      MISC_APPLICATION=$( grep '"comment":' $FACTS | awk -F': ' '{print $2}' | sed 's/^"//g;s/",//g' | awk -F':' '{print $2}' | grep -v "null" )

      echo "$OS_HOSTNAME,$HW_CPU_CORES,$HW_CPU_THREADS,$HW_CPU_SOCKETS,$HW_CPU_VEND,$HW_CPU_NAME,$HW_CPU_SPEED,$NET_PUBIP,$MISC_LOCATION,$HW_MANU,$HW_PRODUCT,$OS_NAME $OS_RELEASE,Update $OS_UPDATE,,$OS_VERSION,$HW_MEM_MB,$HW_SERIAL,$MISC_APPLICATION"
   fi
done

exit

