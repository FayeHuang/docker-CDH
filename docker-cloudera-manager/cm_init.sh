#!/bin/bash
#
mysql_password=changeme
timeout_s=5
time_s=0
while [[ -z "$NTP_SERVER" && -z "$HIVE_DB_CREATE" && -z "$OOZIE_DB_CREATE" && -z "$CM_SERVER" && $time_s -lt $TIMEOUT_S ]];
do
    echo $time_s
    sleep 1
    time_s=$((time_s+1))
done
#
if [[ -z "$NTP_SERVER" && -z "$HIVE_DB_CREATE" && -z "$OOZIE_DB_CREATE" && -z "$CM_SERVER" ]];
then
    echo "[ERROR] Timeout, can not get environment variable NTP_SERVER or HIVE_DB_CREATE or OOZIE_DB_CREATE or CM_SERVER"
    exit
fi
echo "[INFO] Environment variables : NTP_SERVER=$NTP_SERVER, HIVE_DB_CREATE=$HIVE_DB_CREATE, OOZIE_DB_CREATE=$OOZIE_DB_CREATE"
#
if [[ "$HIVE_DB_CREATE" == "true" ]];
then
    time_s=0
    while [[ -z "$HIVE_METASTORE_HOST" && -z "$HIVE_DB_PASSWORD" && $time_s -lt $TIMEOUT_S ]];
    do
        echo $time_s
        sleep 1
        time_s=$((time_s+1))
    done
    #
    if [[ -z "$HIVE_METASTORE_HOST" && -z "$HIVE_DB_PASSWORD" ]];
    then
        echo "[Error] Timeout, can not get environment variable HIVE_METASTORE_HOST or HIVE_DB_PASSWORD"
        exit
    fi
fi
echo "[INFO] Environment variables : HIVE_METASTORE_HOST=$HIVE_METASTORE_HOST, HIVE_DB_PASSWORD=$HIVE_DB_PASSWORD"
#
if [[ "$OOZIE_DB_CREATE" == "true" ]];
then
    time_s=0
    while [[ -z "$OOZIE_DB_PASSWORD" && $time_s -lt $TIMEOUT_S ]];
    do
        echo $time_s
        sleep 1
        time_s=$((time_s+1))
    done
    #
    if [[ -n "$HIVE_DB_PASSWORD" ]];
    then
        echo "[Error] Timeout, can not get environment variable OOZIE_DB_PASSWORD"
        exit
    fi
fi
echo "[INFO] Environment variables : OOZIE_DB_PASSWORD=$OOZIE_DB_PASSWORD"
# finish to get Environment variables
#
#
# ===== Begine =====
# Ture off SELINUX
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

# Create DB for Hive & Oozie if necessary
if [[ "$HIVE_DB_CREATE" == "true" ]];
then
    mysql --user=root --password=$mysql_password --execute="CREATE DATABASE metastore;"
    mysql --user=root --password=$mysql_password --execute="USE metastore; SOURCE /usr/lib/hive/scripts/metastore/upgrade/mysql/hive-schema-1.1.0.mysql.sql;"
    mysql --user=root --password=$mysql_password --execute="CREATE USER 'hive'@'$HIVE_METASTORE_HOST' IDENTIFIED BY '$HIVE_DB_PASSWORD';"
    mysql --user=root --password=$mysql_password --execute="REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'hive'@'$HIVE_METASTORE_HOST';"
    mysql --user=root --password=$mysql_password --execute="GRANT ALL PRIVILEGES ON metastore.* TO 'hive'@'$HIVE_METASTORE_HOST';"
    mysql --user=root --password=$mysql_password --execute="FLUSH PRIVILEGES;"
fi
#
if [[ "$OOZIE_DB_CREATE" == "true" ]];
then
    mysql --user=root --password=$hive_metastore_password --execute="create database oozie; grant all privileges on oozie.* to 'oozie'@'localhost' identified by '$OOZIE_DB_PASSWORD'; grant all privileges on oozie.* to 'oozie'@'%' identified by '$OOZIE_DB_PASSWORD';"
fi

# Start CM
service cloudera-scm-server-db start
service cloudera-scm-server start
#
sleep 5
sed -i.bak s/^.*"server_host=".*/"server_host=$CM_SERVER"/ /etc/cloudera-scm-agent/config.ini
service cloudera-scm-agent start
#
firehostdbpassword=`grep com.cloudera.cmf.ACTIVITYMONITOR.db.password /etc/cloudera-scm-server/db.mgmt.properties | awk -F'=' '{print $2}'`
navigatordbpassword=`grep com.cloudera.cmf.NAVIGATOR.db.password /etc/cloudera-scm-server/db.mgmt.properties | awk -F'=' '{print $2}'`
headlampdbpassword=`grep com.cloudera.cmf.REPORTSMANAGER.db.password /etc/cloudera-scm-server/db.mgmt.properties | awk -F'=' '{print $2}'`
#
cm_service_config=cm_service.ini
echo "[CM]" > $cm_service_config
echo "cm.host=$CM_SERVER" >> $cm_service_config
echo "cm.username=admin" >> $cm_service_config
echo "cm.password=admin" >> $cm_service_config
echo "ACTIVITYMONITOR.db.password=$firehostdbpassword" >> $cm_service_config
echo "NAVIGATOR.db.password=$navigatordbpassword" >> $cm_service_config
echo "REPORTSMANAGER.db.password=$headlampdbpassword" >> $cm_service_config
#
echo "[INFO] finish setting up CM"

# Python print statement does not automatically flush output to STDOUT.
# One solution is using sys.stdout.flush()
# Python 3.3, print(msg, flush=True) is another solution
# a better solution is to run python with -u parameter (unbuffered mode). Alternatively, you can set PYTHONUNBUFFERED environment variable for this.
python -u deployCDH.py
