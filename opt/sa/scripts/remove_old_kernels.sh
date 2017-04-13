#!/bin/bash

OPT=$1

if [[ -n "$(rpm -qa kernel* | egrep -v $(uname -r | awk -F'.' 'NF{NF-=1};1' | sed 's/ /./g'))" ]]; then

   if [[ -n `echo $OPT | egrep -i "^T"` ]]; then
      echo "Found old kernels."
   else

      yum erase $(rpm -qa kernel* | egrep -v $(uname -r | awk -F'.' 'NF{NF-=1};1' | sed 's/ /./g'))
   fi

else
   if [[ -z `echo $OPT | egrep -i "^T"` ]]; then
      echo "Nothing to do."
   fi

fi
