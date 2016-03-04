#!/bin/bash


# Script to configure opentTsdb
#


# When called from the master installer, expect to see the following options:
#
# -nodeCount ${otNodesCount} -OT "${otNodesList}" -nodePort ${otPort} 
# -nodeZkCount ${zkNodesCount} -Z "${zkNodesList}" -nodeZkPort ${zkClientPort}
# 
# where the 
#
# -nodeCount    tells you how many openTsdb server configured in the cluster
# -OT           tells you the list of hosts to be configure as opentTsdb servers
#               the format of this list is {hostname[;ipaddress][:port][, ..]}
#
# -nodePort     is the port number openTsdb should be listening on
#
# -nodeZkCount  tells you how many Zookeeper nodes in the cluster
# -Z            tells you the list of Zookeeper nodes
# -nodeZkPort   the port Zookeeper is listening on

# This gets fillled out at package time
PACKAGE_INSTALL_DIR="__INSTALL__"
PACKAGE_CONFIG_FILE="${PACKAGE_INSTALL_DIR}/etc/opentsdb/opentsdb.conf"
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_CONF_DIR="${MAPR_HOME}/conf/conf.d"

# Parse the arguments
while [ $# -gt 0 ]
do
  case "$1" in
  -nodePort) shift;
             OT_PORT=$1;;
  -Z) shift;
      ZK_NODES_LIST=$1;;
  -nodeZkPort) shift;
               ZK_PORT=$1;;
  esac
  shift
done

# TODO -- Use regex to get the correct version number instead of hardcoding it
# copy asynchbase jar
if uname -v | fgrep -q 'Ubuntu' > /dev/null 2>&1 ; then 
    SNAPSHOT=1503
else
    SNAPSHOT=1504
fi
cp  /opt/mapr/asynchbase/asynchbase-1.6.0/asynchbase-1.6.0-mapr-${SNAPSHOT}.jar ${PACKAGE_INSTALL_DIR}/share/opentsdb/lib/asynchbase-1.6.0.jar

# TODO - change owner on /tmp/opentsdb


# The following configuration knobs needs to be set at a minimum:
# opentsdb.conf:tsd.network.port = 4242

if [ ! -z ${OT_PORT} -a -w ${PACKAGE_CONFIG_FILE} ]
  then
  sed -i 's/\(tsd.network.port = \).*/\1'$OT_PORT'/g' $PACKAGE_CONFIG_FILE
fi

# opentsdb.conf:# The IPv4 network address to bind to, defaults to all addresses
# opentsdb.conf:# tsd.network.bind = 0.0.0.0

# A space separated list of Zookeeper hosts to connect to, with or without
# port specifiers, default is "localhost"
# tsd.storage.hbase.zk_quorum = 10.10.88.98:5181
zkNodesList=''
if [ ! -z ${ZK_PORT} -a ! -z ${ZK_NODES_LIST} -a -w ${PACKAGE_CONFIG_FILE} ]
  then
  for zkNode in $(echo ${ZK_NODES_LIST} | tr "," " "); do
    zkNodesList=$zkNodesList,$zkNode
  done
  zkNodesList=${zkNodesList:1}
  zkNodesList=${zkNodesList/,/ }
  sed -i 's/\(tsd.storage.hbase.zk_quorum = \).*/\1'"$zkNodesList"'/g' $PACKAGE_CONFIG_FILE
fi

# Create TSDB tables
timeout -s HUP 30s $MAPR_HOME/bin/maprcli node cldbmaster -noheader 2> /dev/null
if [ $? -eq 0 ]
then 
  HBASE_VERSION=`cat $MAPR_HOME/hbase/hbaseversion`
  export COMPRESSION=NONE; export HBASE_HOME=$MAPR_HOME/hbase/hbase-$HBASE_VERSION; su -c ${PACKAGE_INSTALL_DIR}/share/opentsdb/tools/create_table.sh > ${PACKAGE_INSTALL_DIR}/var/log/opentsdb/opentsdb_install.log mapr
else
  return 1
fi

# make sure conf directory exist
if ! [ -d ${MAPR_CONF_DIR} ]; then
  mkdir -p ${MAPR_CONF_DIR} > /dev/null 2>&1
fi

# Copy warden conf
cp ${PACKAGE_INSTALL_DIR}/etc/conf/warden.opentsdb.conf ${MAPR_CONF_DIR}

true
