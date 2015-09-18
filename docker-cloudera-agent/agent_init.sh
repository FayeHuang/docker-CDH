#!/bin/bash
#
timeout_s=5
time_s=0
while [[ -z "$NTP_SERVER" && -z "$NODE_NUMBER" && -z "$ROLE_INSTALL" && $time_s -lt $timeout_s ]];
do
    echo $time_s
    sleep 1
    time_s=$((time_s+1))
done
#
if [[ -z "$NTP_SERVER" || -z "$NODE_NUMBER" || -z "$ROLE_INSTALL" ]];
then
    echo "[ERROR] Timeout, can not get environment variable NTP_SERVER or NODE_NUMBER or ROLE_INSTALL"
    exit
fi
echo "[INFO] Environment variables : NTP_SERVER=$NTP_SERVER, NODE_NUMBER=$NODE_NUMBER, ROLE_INSTALL=$ROLE_INSTALL"
# finish to get Environment variables
#
#
# ===== Begine =====
# turn off SELINUX
setenforce 0

# Set up NTP
echo "server $NTP_SERVER iburst" >> /etc/ntp.conf
ntpdate $NTP_SERVER
/etc/init.d/ntpd start

# 
while [[ $(serf members -status=alive |wc -l) -lt $NODE_NUMBER ]];
do
    echo $(serf members -status=alive |wc -l)
    sleep 1
done
echo "[INFO] total serf agent = $(serf members -status=alive |wc -l)"
#
CM_SERVER=$(serf members -tag role=CM-SERVER |awk '{ print $1}')
#
while [[ "$(curl -sS --fail -u admin:admin http://$CM_SERVER:7180/api/version)" != "v10" ]];
do
    echo "wait for cm api ready. sleep 1s."
    sleep 1
done
#
# Start CM agent
sed -i.bak s/^.*"server_host=".*/"server_host=$CM_SERVER"/ /etc/cloudera-scm-agent/config.ini
service cloudera-scm-agent start
#
#
config=install.ini
echo "[Cluster]" > $config
echo "cluster.name=MyCluster" >> $config
echo "cluster.node.count=$NODE_NUMBER" >> $config
echo "cluster.version=5.4.4" >> $config
echo "[Service]" >> $config
echo "service.type=$(echo $ROLE_INSTALL | awk -F'-' '{print $1}')" >> $config
echo "[Role]" >> $config
echo "role.type=$(echo $ROLE_INSTALL | awk -F'-' '{print $2}')" >> $config
echo "[CM]" >> $config
echo "cm.host=$CM_SERVER" >> $config
echo "cm.username=admin" >> $config
echo "cm.password=admin" >> $config
#
#
echo "[INFO] finish setting up CM-agent"
