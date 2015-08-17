import json
import ConfigParser
import subprocess
import time
import os.path

from cm_api.api_client import ApiResource
from cm_api.endpoints.services import ApiServiceSetupInfo
from cm_api.endpoints.role_config_groups import get_role_config_group


# cm info
CONFIG = ConfigParser.ConfigParser()
CONFIG.read("cm_service.ini")
CM_HOST = CONFIG.get("CM", "cm.host")
CM_USERNAME = CONFIG.get("CM", "cm.username")
CM_PASSWORD = CONFIG.get("CM", "cm.password")
ACTIVITYMONITOR_DB_PASSWORD = CONFIG.get("CM", "ACTIVITYMONITOR.db.password")
NAVIGATOR_DB_PASSWORD = CONFIG.get("CM", "NAVIGATOR.db.password")
REPORTSMANAGER_DB_PASSWORD = CONFIG.get("CM", "REPORTSMANAGER.db.password")

# service & role config
HADOOP_DATA_DIR_PREFIX = "/hadoop"
HDFS_SERVICE_CONFIG = {
    'dfs_replication': 3,
    'dfs_permissions': 'false',
    'dfs_block_local_path_access_user': 'impala,hbase,mapred,spark',
}
HDFS_NN_CONFIG = {
    'dfs_name_dir_list': HADOOP_DATA_DIR_PREFIX + '/nn',
}
HDFS_SNN_CONFIG = {
    'fs_checkpoint_dir_list': HADOOP_DATA_DIR_PREFIX + '/snn',
}
HDFS_DN_CONFIG = {
    'dfs_data_dir_list': HADOOP_DATA_DIR_PREFIX + '/dn',
    'dfs_datanode_du_reserved': 1073741824,
    'dfs_datanode_failed_volumes_tolerated': 0,
    'dfs_datanode_data_dir_perm': 755,
}
HDFS_GATEWAY_CONFIG = {
    'dfs_client_use_trash': 'true',
}
YARN_SERVICE_CONFIG = {}
YARN_RM_CONFIG = {}
YARN_JHS_CONFIG = {}
YARN_NM_CONFIG = {
    'yarn_nodemanager_local_dirs': HADOOP_DATA_DIR_PREFIX + '/nm',
}
YARN_GATEWAY_CONFIG = {}
ZOOKEEPER_SERVICE_CONFIG = {
    'zookeeper_datadir_autocreate': 'true',
}
ZOOKEEPER_ROLE_CONFIG = {
    'dataLogDir': '/var/lib/zookeeper',
    'dataDir': '/var/lib/zookeeper',
    'maxClientCnxns': '1024',
}

# service & role type define
CDH_DEFINE = {
    "ZOOKEEPER": { "config": ZOOKEEPER_SERVICE_CONFIG,
                   "cm_define": "ZOOKEEPER",
                   "roles": { "zk": { "cm_define": "SERVER", "config":ZOOKEEPER_ROLE_CONFIG, "hosts":[] } },
                 },
    "HDFS": { "config": HDFS_SERVICE_CONFIG,
              "cm_define" : "HDFS",
              "roles":  { "nn": { "cm_define": "NAMENODE", "config": HDFS_NN_CONFIG, "hosts":[] },
                          "dn": { "cm_define": "DATANODE", "config": HDFS_DN_CONFIG, "hosts":[] },
                          "snn": { "cm_define": "SECONDARYNAMENODE", "config": HDFS_SNN_CONFIG, "hosts":[] },
                          "hdfs-gateway": { "cm_define": "GATEWAY", "config": HDFS_GATEWAY_CONFIG, "hosts": [] }
                        },
            },
    "YARN": { "config": YARN_SERVICE_CONFIG,
              "cm_define" : "YARN",
              "roles": { "rm": { "cm_define": "RESOURCEMANAGER", "config": YARN_RM_CONFIG, "hosts":[] },
                         "nm": { "cm_define": "NODEMANAGER", "config": YARN_NM_CONFIG, "hosts":[] },
                         "jhs": { "cm_define": "JOBHISTORY", "config": YARN_JHS_CONFIG, "hosts":[] },
                         "yarn-gateway": { "cm_define": "GATEWAY", "config": YARN_GATEWAY_CONFIG, "hosts": [] }
                       },
            },
}


def init_cluster(api, cluster_name, cluster_full_version):
    cluster = api.create_cluster(cluster_name, fullVersion=cluster_full_version)
    cluster_hosts = list()
    for host in api.get_all_hosts():
        cluster_hosts.append(host.hostname)
    cluster.add_hosts(cluster_hosts)
    return cluster


def assign_roles(api, cluster):
    blueprint = {}
    for host in api.get_all_hosts():
        hostname = host.hostname
        for service_type, service_define in CDH_DEFINE.items():
            for role_type, role_define in service_define['roles'].items():
                if hostname.startswith(role_type):

                    if not blueprint.has_key(service_type):
                        blueprint[service_type] = { 'roles': {} }
                        cm_service_type = CDH_DEFINE[service_type]['cm_define']
                        service = cluster.create_service(service_type, cm_service_type)
                    else:
                        service = cluster.get_service(service_type)
                    #
                    if not blueprint[service_type]['roles'].has_key(role_type):
                        blueprint[service_type]['roles'][role_type] = { 'hosts': [] }
                    blueprint[service_type]['roles'][role_type]['hosts'].append(hostname)
                    cm_role_type = CDH_DEFINE[service_type]['roles'][role_type]['cm_define']
                    # hostanem = dn1.lab.com
                    role_name = hostname.split('.')[0]
                    service.create_role(role_name, cm_role_type, hostname)
    return blueprint


def update_custom_config(api, cluster, blueprint):
    for service in cluster.get_all_services():
        service_type = service.type
        service_config = CDH_DEFINE[service_type]['config']
        if service.type == "HDFS":
            dn_amount = len(service.get_all_roles())
            if dn_amount > 5:
                replications = 3
            elif dn_amount <= 5 and dn_amount >= 3:
                replications = 2
            else:
                replications = 1
            service_config['dfs_replication'] = replications
        service.update_config(service_config)
        for role_type in blueprint[service_type]['roles'].keys():
            cm_role_type = CDH_DEFINE[service_type]['roles'][role_type]['cm_define']
            role = service.get_roles_by_type(cm_role_type)[0]
            role_config = CDH_DEFINE[service_type]['roles'][role_type]['config']
            role_group = role.roleConfigGroupRef
            role_group_config = get_role_config_group(api, service_type, role_group.roleConfigGroupName, cluster.name)
            role_group_config.update_config(role_config)
    return True


# Deploys management services. Not all of these are currently turned on because some require a license.
# This function also starts the services.
def deploy_management(manager, mgmt_servicename, amon_role_name, apub_role_name, eserv_role_name, hmon_role_name, smon_role_name, nav_role_name, navms_role_name, rman_role_name):
   mgmt_service_conf = {
       'zookeeper_datadir_autocreate': 'true',
   }
   mgmt_role_conf = {
       'quorumPort': 2888,
   }
   amon_role_conf = {
       'firehose_database_host': CM_HOST + ":7432",
       'firehose_database_user': 'amon',
       'firehose_database_password': ACTIVITYMONITOR_DB_PASSWORD,
       'firehose_database_type': 'postgresql',
       'firehose_database_name': 'amon',
       'firehose_heapsize': '268435456',
   }
   apub_role_conf = {}
   eserv_role_conf = {
       'event_server_heapsize': '215964392'
   }
   hmon_role_conf = {}
   smon_role_conf = {}
   nav_role_conf = {
       'navigator_database_host': CM_HOST + ":7432",
       'navigator_database_user': 'nav',
       'navigator_database_password': NAVIGATOR_DB_PASSWORD,
       'navigator_database_type': 'postgresql',
       'navigator_database_name': 'nav',
       'navigator_heapsize': '215964392',
   }
   navms_role_conf = {}
   rman_role_conf = {
       'headlamp_database_host': CM_HOST + ":7432",
       'headlamp_database_user': 'rman',
       'headlamp_database_password': REPORTSMANAGER_DB_PASSWORD,
       'headlamp_database_type': 'postgresql',
       'headlamp_database_name': 'rman',
       'headlamp_heapsize': '215964392',
   }

   mgmt = manager.create_mgmt_service(ApiServiceSetupInfo())

   # create roles. Note that host id may be different from host name (especially in CM 5). Look it it up in /api/v5/hosts
   mgmt.create_role(amon_role_name + "-1", "ACTIVITYMONITOR", CM_HOST)
   mgmt.create_role(apub_role_name + "-1", "ALERTPUBLISHER", CM_HOST)
   mgmt.create_role(eserv_role_name + "-1", "EVENTSERVER", CM_HOST)
   mgmt.create_role(hmon_role_name + "-1", "HOSTMONITOR", CM_HOST)
   mgmt.create_role(smon_role_name + "-1", "SERVICEMONITOR", CM_HOST)
   #mgmt.create_role(nav_role_name + "-1", "NAVIGATOR", CM_HOST)
   #mgmt.create_role(navms_role_name + "-1", "NAVIGATORMETADATASERVER", CM_HOST)
   #mgmt.create_role(rman_role_name + "-1", "REPORTSMANAGER", CM_HOST)

   # now configure each role
   for group in mgmt.get_all_role_config_groups():
       if group.roleType == "ACTIVITYMONITOR":
           group.update_config(amon_role_conf)
       elif group.roleType == "ALERTPUBLISHER":
           group.update_config(apub_role_conf)
       elif group.roleType == "EVENTSERVER":
           group.update_config(eserv_role_conf)
       elif group.roleType == "HOSTMONITOR":
           group.update_config(hmon_role_conf)
       elif group.roleType == "SERVICEMONITOR":
           group.update_config(smon_role_conf)
       #elif group.roleType == "NAVIGATOR":
       #    group.update_config(nav_role_conf)
       #elif group.roleType == "NAVIGATORMETADATASERVER":
       #    group.update_config(navms_role_conf)
       #elif group.roleType == "REPORTSMANAGER":
       #    group.update_config(rman_role_conf)

   # now start the management service
   mgmt.start().wait()

   return mgmt


### Main function ###
def main():
    # # wait for cm api ready ...
    print("[INFO] wait for cm api ready")
    connect_ok = False
    while not connect_ok:
         cmd = "curl -u "+CM_USERNAME+":"+CM_PASSWORD+" 'http://"+CM_HOST+":7180/api/v10/clusters'"
         p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
         ( stdout, stderr ) = p.communicate()
         if stdout:
             connect_ok = True
         else:
             print("sleep 5s")
             time.sleep(5)
    # connect cm api
    api = ApiResource(CM_HOST, 7180, username=CM_USERNAME, password=CM_PASSWORD)
    print(len(api.get_all_hosts()))
    manager = api.get_cloudera_manager()
    # no need to update cm config
    #manager.update_config(cm_host)
    print("[INFO] Connected to CM host on " + CM_HOST)

    # create cluster object
    cluster_name = "TTT"
    cluster_full_version = "5.4.4"
    try:
        cluster = api.get_cluster(name=cluster_name)
    except:
        cluster = init_cluster(api, cluster_name, cluster_full_version)
    print("[INFO] Initialized cluster " + cluster_name + " which uses CDH version " + cluster_full_version)

    #
    mgmt_servicename = "MGMT"
    amon_role_name = "ACTIVITYMONITOR"
    apub_role_name = "ALERTPUBLISHER"
    eserv_role_name = "EVENTSERVER"
    hmon_role_name = "HOSTMONITOR"
    smon_role_name = "SERVICEMONITOR"
    nav_role_name = "NAVIGATOR"
    navms_role_name = "NAVIGATORMETADATASERVER"
    rman_role_name = "REPORTMANAGER"
    deploy_management(manager, mgmt_servicename, amon_role_name, apub_role_name, eserv_role_name, hmon_role_name, smon_role_name, nav_role_name, navms_role_name, rman_role_name)
    print("[INFO] Deployed CM management service " + mgmt_servicename + " to run on " + CM_HOST)

    #
    blueprint = assign_roles(api, cluster)
    print(json.dumps(blueprint))
    print("[INFO] all roles have assigned.")

    #
    # Custom role config groups cannot be automatically configured: Gateway Group 1 (error 400)
    try:
        cluster.auto_configure()
    except:
        pass
    update_custom_config(api, cluster, blueprint)
    print("[INFO] all servies and roles have configured.")
    #
    cmd = cluster.first_run()
    while cmd.success == None:
        cmd = cmd.fetch()
    if not cmd.success:
        print("[ERROR] The first run command failed: " + cmd.resultMessage())
    else:
        print("[INFO] First run successfully executed. Your cluster has been set up!")
    #


if __name__ == "__main__":
    main()
