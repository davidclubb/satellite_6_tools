#!/bin/bash

source .satapi.env

hammer -u $USER -p $PASS $@
