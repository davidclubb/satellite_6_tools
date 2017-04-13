#!/bin/bash

echo "Stopping SCOM Agent"
/etc/init.d/scx-cimd stop

echo "Removing Client Key"
/bin/rm /etc/opt/microsoft/scx/ssl/scx-key.pem

echo "Regenerating Client Key"
/opt/microsoft/scx/bin/tools/.scxsslconfig

echo -e "\nClient has been repaired, you can now rediscover it from the SCOM console\n"
