#!/bin/bash
#
mysql_password=changeme
timeout_s=5
time_s=0
while [[ -z "$NTP_SERVER" && -z "$NODE_NUMBER" && $time_s -lt $timeout_s ]];
do
    echo $time_s
    sleep 1
    time_s=$((time_s+1))
done
#
if [[ -z "$NTP_SERVER" || -z "$NODE_NUMBER" ]];
then
    echo "[ERROR] Timeout, can not get environment variable NTP_SERVER or CM_SERVER"
    exit
fi
echo "[INFO] Environment variables : NTP_SERVER=$NTP_SERVER, NODE_NUMBER=$NODE_NUMBER"
#
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

# Start mysql
service mysqld start
sleep 1
mysql_secure_installation < mysql_secure_install_answer
rm -f mysql_secure_install_answer

# Start CM
service cloudera-scm-server-db start
service cloudera-scm-server start
#
firehostdbpassword=`grep com.cloudera.cmf.ACTIVITYMONITOR.db.password /etc/cloudera-scm-server/db.mgmt.properties | awk -F'=' '{print $2}'`
navigatordbpassword=`grep com.cloudera.cmf.NAVIGATOR.db.password /etc/cloudera-scm-server/db.mgmt.properties | awk -F'=' '{print $2}'`
headlampdbpassword=`grep com.cloudera.cmf.REPORTSMANAGER.db.password /etc/cloudera-scm-server/db.mgmt.properties | awk -F'=' '{print $2}'`
#
#
while [[ $(serf members -status=alive |wc -l) -lt $NODE_NUMBER ]];
do
    echo $(serf members -status=alive |wc -l)
    sleep 1
done
echo "[INFO] total serf agent = $(serf members -status=alive |wc -l)"
#
CM_SERVER=$(hostname -f)
#
while [[ "$(curl -sS --fail -u admin:admin http://$CM_SERVER:7180/api/version)" != "v10" ]];
do
    echo "wait for cm api ready. sleep 1s."
    sleep 1
done
#
sed -i.bak s/^.*"server_host=".*/"server_host=$CM_SERVER"/ /etc/cloudera-scm-agent/config.ini
service cloudera-scm-agent start
#
#
config=install.ini
echo "[CM]" > $config
echo "cm.host=$CM_SERVER" >> $config
echo "cm.username=admin" >> $config
echo "cm.password=admin" >> $config
echo "ACTIVITYMONITOR.db.password=$firehostdbpassword" >> $config
echo "NAVIGATOR.db.password=$navigatordbpassword" >> $config
echo "REPORTSMANAGER.db.password=$headlampdbpassword" >> $config
echo "mysql.password=$mysql_password" >> $config
echo "[Cluster]" >> $config
echo "cluster.name=MyCluster" >> $config
echo "cluster.node.count=$NODE_NUMBER" >> $config
echo "cluster.version=5.4.4" >> $config
#

# Python print statement does not automatically flush output to STDOUT.
# One solution is using sys.stdout.flush()
# Python 3.3, print(msg, flush=True) is another solution
# a better solution is to run python with -u parameter (unbuffered mode). Alternatively, you can set PYTHONUNBUFFERED environment variable for this.
python -u deployCDH.py

echo "[INFO] finish setting up CM"
