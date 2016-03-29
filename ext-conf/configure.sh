#!/bin/bash
# Copyright (c) 2009 & onwards. MapR Tech, Inc., All rights reserved

#############################################################################
#
# Script to configure opentTsdb
#
# __INSTALL_ (double underscore at the end)  gets expanded to __INSTALL__ during pakcaging
# set OT_HOME explicitly if running this in a source built env.
#
# This script is sourced from the master configure.sh, this way any variables
# we need are available to us.
#
# It also means that this script should never do an exit in the case of failure
# since that would cause the master configure.sh to exit too. Simply return
# an return value if needed. Sould be 0 for the most part.
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
OT_HOME="__INSTALL__"
OT_CONF_FILE="${OT_HOME}/etc/opentsdb/opentsdb.conf"
NEW_OT_CONF_FILE=${NEW_OT_CONF_FILE:-${OT_CONF_FILE}.progress}
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_CONF_DIR="${MAPR_HOME}/conf/conf.d"
MAPR_USER=${MAPR_USER:-mapr}
NOW=`date "+%Y%m%d_%H%M%S"`
CLDB_RETRIES=24
CLDB_RETRY_DLY=5
CLDB_RUNNING=0
ASYNCVER="1.7"   # two most significat version number of compatible asynchbase jar
OT_CONF_ASSUME_RUNNING_CORE=${isOnlyRoles:-0}
RC=0

#############################################################################
# Function to install Warden conf file
#
#############################################################################
function installWardenConfFile() {
    # make sure conf directory exist
    if ! [ -d ${MAPR_CONF_DIR} ]; then
        mkdir -p ${MAPR_CONF_DIR} > /dev/null 2>&1
    fi

    # Copy warden conf
    cp ${OT_HOME}/etc/conf/warden.opentsdb.conf ${MAPR_CONF_DIR}
    if [ $? -ne 0 ]; then
        echo "WARNING: Failed to install Warden conf file for service - service will not start"
    fi
}


#############################################################################
# Function to configure ZooKeeper quorum
#
#############################################################################
function configureZKQuorum() {
    # A space separated list of Zookeeper hosts to connect to, with or without
    # port specifiers, default is "localhost"
    # tsd.storage.hbase.zk_quorum = 10.10.88.98:5181
    zkNodesList=''
    if [ ! -z ${zk_nodeport} -a ! -z ${zk_nodelist} -a -w ${NEW_OT_CONF_FILE} ]; then
        for zkNode in $(echo ${zk_nodelist} | tr "," " "); do
            zkNodesList=$zkNodesList,$zkNode
        done
        zkNodesList=${zkNodesList:1}
        zkNodesList=${zkNodesList//,/ }
        sed -i 's/\(tsd.storage.hbase.zk_quorum = \).*/\1'"$zkNodesList"'/g' $NEW_OT_CONF_FILE
    fi
}


#############################################################################
# Function to install AsyncHbaseJar
#
#############################################################################
function installAsyncHbaseJar() {
    # copy asynchbase jar
    local asyncHbaseJar=""
    local jar_ver=""
    local rc=1
    asyncHbaseJar=$(find ${MAPR_HOME}/asynchbase -name 'asynchbase*mapr*.jar' | fgrep -v javadoc|fgrep -v sources)
    if [ -n "$asyncHbaseJar" ]; then
        jar_ver=$(basename $asyncHbaseJar)
        jar_ver=$(echo $jar_ver | cut -d- -f2) # should look like 1.7.0
        if [ -n "$jar_ver" ]; then
            verify_ver=$(echo $jar_ver | cut -d. -f1,2)
            # verify the two most significant
            if [ -n "$verify_ver" -a "$verify_ver" = "$ASYNCVER" ]; then
                cp  "$asyncHbaseJar" ${OT_HOME}/share/opentsdb/lib/asynchbase-"$jar_ver".jar
                rc=$?
            else
                echo "ERROR: Incompatible asynchbase jar found"
            fi
        fi
    fi

    if [ $rc -eq 1 ]; then
        echo "ERROR: Failed to install asyncHbase Jar file"
    fi
    return $rc
}


#############################################################################
# Function to configure OT port
#
#############################################################################
function configureOTPort() {
    # The following configuration knobs needs to be set at a minimum:
    # opentsdb.conf:tsd.network.port = 4242

    if [ ! -z ${nodeport} -a -w ${NEW_OT_CONF_FILE} ]; then
        sed -i 's/\(tsd.network.port = \).*/\1'$nodeport'/g' $NEW_OT_CONF_FILE
    fi
}


#############################################################################
# Function to configure OT interface
#
#############################################################################
function configureOTIp() {
    # opentsdb.conf:# The IPv4 network address to bind to, defaults to all addresses
    # opentsdb.conf:# tsd.network.bind = 0.0.0.0
    # XXX Need to decide if we ant 0.0.0.0 or specific Interface
    :
}

#############################################################################
# Function to wait for cldb to come up
#
#############################################################################
function waitForCLDB() {
    local cldbretries
    cldbretries=$CLDB_RETRIES   # give it two minutes
    until [ $CLDB_RUNNING -eq 1 -o $cldbretries -lt 0 ]; do
        $MAPR_HOME/bin/maprcli node cldbmaster > /dev/null 2>&1
        [ $? -eq 0 ] && CLDB_RUNNING=1
        [ $CLDB_RUNNING -ne 0 ] &&  sleep $CLDB_RETRY_DLY
        let cldbretries=cldbretries-1
    done
    return $CLDB_RUNNING
}



#############################################################################
# Function to create TSDB tables in Hbase as the $MAPR_USER user
#
#############################################################################
function createTSDBHbaseTables() {
    local rc=1
    # Create TSDB tables
    if [ $CLDB_RUNNING -eq 1 ]; then
        HBASE_VERSION=`cat $MAPR_HOME/hbase/hbaseversion`
        export COMPRESSION=NONE; export HBASE_HOME=$MAPR_HOME/hbase/hbase-$HBASE_VERSION; su -c ${OT_HOME}/share/opentsdb/tools/create_table.sh > ${OT_HOME}/var/log/opentsdb/opentsdb_install.log $MAPR_USER
        rc=$?
    fi
    if [ $rc -ne 0 ]; then
        echo "WARNING: Failed to create Hbase TSDB tables"
    fi
    return $rc
}


# typically called from master configure.sh with the following arguments
#
# configure.sh  -nodeCount ${otNodesCount} -OT "${otNodesList}" -nodePort ${otPort}
#               -Z ${zkNodesList} -nodeZkPort ${zkPort}
#
# we need will use the roles file to know if this node is a RM. If this RM
# is not the active one, we will be getting 0s for the stats.
#
# Parse the arguments

usage="usage: $0 -nodeCount <cnt> -OT \"ip:port,ip1:port,\" -nodePort <port> -nodeZkCount <zkCnt> -Z \"ip:port,ip1:port,\" -nodeZkPort <zkPort>"
if [ ${#} -gt 1 ]; then
    # we have arguments - run as as standalone - need to get params and
    # XXX why do we need the -o to make this work?
    OPTS=`getopt -a -o h -l nodeCount: -l nodePort: -l OT: -l nodeZkCount: -l nodeZkPort: -l Z: -- "$@"`
    if [ $? != 0 ]; then
        echo ${usage}
        return 2 2>/dev/null || exit 2
    fi
    eval set -- "$OPTS"

    for i ; do
        case "$i" in
            --nodeCount)
                nodecount="$2";
                shift 2
                ;;
            --nodeZkCount)
                zk_nodecount="$2";
                shift 2
                ;;
            --OT) # not used at the moment
                nodelist="$2";
                shift 2
                ;;
            --Z)
                zk_nodelist="$2";
                shift 2
                ;;
            --nodePort)
                nodeport="$2";
                shift 2
                ;;
            --nodeZkPort)
                zk_nodeport="$2";
                shift 2
                ;;
            -h)
                echo ${usage}
                return 2 2>/dev/null || exit 2
                ;;
            --)
                shift
                ;;
        esac
    done
else
    echo "${usage}"
    return 2 2>/dev/null || exit 2
fi

# make sure we have what we need
# we don't really need the OT list at the moment, nor do we use the two counts
if [ -z "$nodeport" -o -z "$zk_nodelist" -o -z "$zk_nodeport" ]; then
    echo "${usage}"
    return 2 2>/dev/null || exit 2
fi

# TODO - change owner on /tmp/opentsdb

# save off a copy
cp -p ${OT_CONF_FILE} ${OT_CONF_FILE}.${NOW}

#create our new config file
cp ${OT_CONF_FILE} ${NEW_OT_CONF_FILE}

configureOTPort
configureZKQuorum
installAsyncHbaseJar
RC=$?
if [ $RC -ne 0 ]; then
    # If we couldn't install the jar file - report early
    return $RC 2>/dev/null || exit $RC
else
    true
fi

#install our changes
cp ${NEW_OT_CONF_FILE} ${OT_CONF_FILE}
if [ $OT_CONF_ASSUME_RUNNING_CORE -eq 1 ]; then
    waitForCLDB
    createTSDBHbaseTables
    if [ $? -eq 0 ]; then
        installWardenConfFile
    else
        echo "WARNING: opentsdb service not enabled - failed to setup hbase tables"
    fi
fi
true
