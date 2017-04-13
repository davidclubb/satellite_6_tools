#!/bin/bash

# This script *fixes* the SCOM installation so it matches the final hostname no matter what

/bin/rm /etc/opt/microsoft/scx/ssl/scx-key.pem
/opt/microsoft/scx/bin/tools/.scxsslconfig
