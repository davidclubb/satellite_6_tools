#!/bin/bash

FS=$1

if [[ -z $FS ]]; then
   echo "Please provide a filesystem path to check for open file descriptors to deleted files"
   exit 1
fi

echo "WARNING: This is super-dangerous.  Please don't use it in Prod without a "
echo "         really good reason and a change request/blackout"
read -p "Type 'C' and Enter to continue, anything else to abort: " CHECK

if [[ "$CHECK" != "C" ]]; then
   echo "Aborted by user.  No changes made."
   exit 0
fi

# Get a list of processes with open file handles to the given directory
PIDLIST=`lsof $FS | egrep -v 'PID' | awk '{print $2}' | sort -u`


for PID in $PIDLIST; do

  unset DESCLIST

  # Get a list of file descriptors for that PID that refer to deleted files
  DESCLIST=`ls -l /proc/${PID}/fd | grep deleted | awk '{print $9}'`

  # Display the list
  echo "The Process $PID has open file descriptors for deleted files:"
  echo "${DESCLIST}" | sed 's/^/  /g'

  # Create a name for the script for gdb 
  DEBUGSCRIPT=/tmp/.$PID

  # Remove any previous version of the script
  if [[ -f $DEBUGSCRIPT ]]; then /bin/rm $DEBUGSCRIPT; fi

  # Write a close command for each deleted file descriptor
  for DFD in $DESCLIST; do
     echo "p close(${DFD})" >> $DEBUGSCRIPT
  done

  # Detach and close the debugger
  echo "detach" >> $DEBUGSCRIPT
  echo "quit" >> $DEBUGSCRIPT

  echo "Forcibly closing handles for deleted files on process $PID"

  # Run the debugger in batch mode to execute the script and close the handles
  /usr/bin/gdb --pid $PID --batch -x $DEBUGSCRIPT

  # Wait before deleting the script
  sleep 1

  # Clean up the script
  /bin/rm $DEBUGSCRIPT

done

