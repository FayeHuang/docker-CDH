#!/bin/bash

SERF_BIN=$SERF_HOME/bin/serf
SERF_CONFIG_DIR=$SERF_HOME/etc
SERF_LOG_FILE=/var/log/serf.log

# if SERF_JOIN_IP env variable set generate a config json for serf
timeout_s=5
time_s=0
while [[ -z "$SERF_JOIN_IP" && -z "$ROLE_INSTALL" && $time_s -lt $timeout_s ]];
do
    sleep 1
    time_s=$(( time_s+1 ))
done
#
if [[ -z "$SERF_JOIN_IP" || -z "$ROLE_INSTALL" ]];
then
    echo "[ERROR] Timeout, can not get environment variable SERF_JOIN_IP or ROLE_INSTALL"
    exit
fi
echo "[INFO] Environment variables : SERF_JOIN_IP=$SERF_JOIN_IP, ROLE_INSTALL=$ROLE_INSTALL"


cat > $SERF_CONFIG_DIR/join.json <<EOF
{
  "retry_join" : ["$SERF_JOIN_IP"],
  "retry_interval" : "5s"
}
EOF

$SERF_BIN agent -config-dir $SERF_CONFIG_DIR -tag role=$ROLE_INSTALL $@ | tee -a $SERF_LOG_FILE
