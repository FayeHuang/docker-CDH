#!/bin/bash
#
timeout_s=5
time_s=0
while [[ -z "$NTP_SERVER" && -z "$SERF_JOIN_IP" && -z "$CM_SERVER" && $time_s -lt $TIMEOUT_S ]];
do
    echo $time_s
    sleep 1
    time_s=$((time_s+1))
done
#
if [[ -z "$NTP_SERVER" && -z "$SERF_JOIN_IP" && -z "$CM_SERVER" ]];
then
    echo "[ERROR] Timeout, can not get environment variable NTP_SERVER or SERF_JOIN_IP or CM_SERVER"
    exit
fi
echo "[INFO] Environment variables : NTP_SERVER=$NTP_SERVER, SERF_JOIN_IP=$SERF_JOIN_IP, CM_SERVER=$CM_SERVER"
# finish to get Environment variables
#
#
# ===== Begine =====
# Ture off SELINUX
setenforce 0

# Set up NTP
ntpdate $NTP_SERVER
/etc/init.d/ntpd start

# Start CM agent
sed -i.bak s/^.*"server_host=".*/"server_host=$CM_SERVER"/ /etc/cloudera-scm-agent/config.ini
service cloudera-scm-agent start
