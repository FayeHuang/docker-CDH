#!/bin/bash
echo -n "input amount of slave(datanode, nodemanager ...) : "
read nodeAmount

declare -A role_array
role_array+=( ["HDFS-NAMENODE"]=1 ["HDFS-SECONDARYNAMENODE"]=1 ["HDFS-DATANODE"]=$nodeAmount ["HDFS-GATEWAY"]=1 )
role_array+=( ["YARN-RESOURCEMANAGER"]=1 ["YARN-NODEMANAGER"]=$nodeAmount ["YARN-JOBHISTORY"]=1 ["YARN-GATEWAY"]=1 )
role_array+=( ["ZOOKEEPER-SERVER"]=1 )

NODE_NUMBER=0
for key in ${!role_array[@]};
do
    echo ${key} ${role_array[${key}]}
    NODE_NUMBER=$(( $NODE_NUMBER + ${role_array[${key}]} ))
done
NODE_NUMBER=$(( $NODE_NUMBER + 1 ))

CM_IMAGE=qp/cm:0.4
AGENT_HADOOP_IMAGE=qp/cm-agent:0.4
NTP_SERVER=tick.stdtime.gov.tw
#
user=faye
domain=$user.local
c_hostname=cm
c_fqdn=$c_hostname.$domain
c_name=$c_hostname-$(date "+%m%d%H%M%S")
#
c_id=$(docker run -d \
                  -p 443:22 -p 80:7180 \
                  -e NTP_SERVER=$NTP_SERVER \
                  -e NODE_NUMBER=$NODE_NUMBER \
                  --privileged=true \
                  --hostname=$c_fqdn \
                  --name=$c_name \
                  --dns=127.0.0.1 --dns=8.8.8.8 \
       $CM_IMAGE)
c_ip=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' $c_id)
cm_ip=$c_ip
printf 'CONTAINER IP HOSTNAME FQDN ID \n' > cluster.info
printf '%s\t %s\t %s\t %s\t %s\t\n' $c_name $c_ip $c_hostname $c_fqdn $c_id >> cluster.info

echo "====> CM ok!"

node_index=1
for key in ${!role_array[@]};
do
    role_type=${key}
    role_count=${role_array[${key}]}
    for i in `seq 1 1 $role_count`
    do
        c_hostname=node$node_index
        c_fqdn=$c_hostname.$domain
        c_name=$c_hostname-$(date "+%m%d%H%M%S")
        c_id=$(docker run -d \
                          -e SERF_JOIN_IP=$cm_ip \
                          -e NTP_SERVER=$NTP_SERVER \
                          -e NODE_NUMBER=$NODE_NUMBER \
                          -e ROLE_INSTALL=$role_type \
                          --privileged=true \
                          --hostname=$c_fqdn \
                          --name=$c_name \
                          --dns=127.0.0.1 --dns=8.8.8.8 \
               $AGENT_HADOOP_IMAGE)
        c_ip=$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' $c_id)
        printf '%s\t %s\t %s\t %s\t %s\t\n' $c_name $c_ip $c_hostname $c_fqdn $c_id >> cluster.info
        node_index=$(( $node_index + 1 ))
    done
done
