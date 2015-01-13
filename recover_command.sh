#!/bin/sh
sqlconnect="\c -i 00 -n mo-21313196d -u SYSTEM -p MultiT3nant -d SYSTEMDB"

hdbsql <<EOF
$sqlconnect
RECOVER DATA FOR MY_DB0  USING FILE ('/backup/orginal/data/COMPLETE_DATA_BACKUP')  CLEAR LOG
EOF
