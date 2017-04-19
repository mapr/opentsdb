#!/bin/bash
# Copyright (c) 2009 & onwards. MapR Tech, Inc., All rights reserved

#############################################################################
#
# Script to configure opentTsdb
#
# __INSTALL_ (double underscore at the end)  gets expanded to __INSTALL__ during pakcaging
# set OTSDB_HOME explicitly if running this in a source built env.
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
OTSDB_HOME="${OTSDB_HOME:-__INSTALL__}"
OT_CONF_FILE="${OT_CONF_FILE:-${OTSDB_HOME}/etc/opentsdb/opentsdb.conf}"
NEW_OT_CONF_FILE=${NEW_OT_CONF_FILE:-${OT_CONF_FILE}.progress}
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_CONF_DIR="${MAPR_HOME}/conf/conf.d"
MAPR_USER=${MAPR_USER:-mapr}
MAPR_GROUP=${MAPR_GROUP:-mapr}
NOW=$(date "+%Y%m%d_%H%M%S")
CLDB_RETRIES=24
CLDB_RETRY_DLY=5
CLDB_RUNNING=0
ASYNCVER="1.7"   # two most significat version number of compatible asynchbase jar
OT_CONF_ASSUME_RUNNING_CORE=${isOnlyRoles:-0}
RC=0
nodeport="4242"
nodecount=0
nodelist=""
streamslist=""
zk_nodecount=0
zk_nodeport=5181
zk_nodelist=""

#############################################################################
# Function to log messages
#
# if $logFile is set the message gets logged there too
#
#############################################################################
function logMsg() {
    local msg
    msg="$(date): $1"
    echo $msg
    if [ -n "$logFile" ] ; then
        echo $msg >> $logFile
    fi
}

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
    cp ${OTSDB_HOME}/etc/conf/warden.opentsdb.conf ${MAPR_CONF_DIR}
    if [ $? -ne 0 ]; then
        logMsg "WARNING: Failed to install Warden conf file for service - service will not start"
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
    if [ ! -z "${zk_nodeport}" -a ! -z "${zk_nodelist}" -a -w ${NEW_OT_CONF_FILE} ]; then
        for zkNode in $(echo ${zk_nodelist} | tr "," " "); do
            zkNodesList=$zkNodesList,$zkNode
        done
        zkNodesList=${zkNodesList:1}
        zkNodesList=${zkNodesList//,/ }
        sed -i 's/\(tsd.storage.hbase.zk_quorum = \).*/\1'"$zkNodesList"'/g' $NEW_OT_CONF_FILE
    fi
}


#############################################################################
# Function to configure input Streams
#
#############################################################################
function configureInputStreams() {
    if [ -n "$streamslist" ]; then
        sed -i 's/(^#)?\(tsd.streams = \).*/\2'"$streamslist"'/g' $NEW_OT_CONF_FILE
        sed -i 's/(^#)?\(tsd.default.usestreams = \).*/\2'"true"'/g' $NEW_OT_CONF_FILE
    else
        sed -i 's/(^#)?\(tsd.default.usestreams = \).*/\2'"false"'/g' $NEW_OT_CONF_FILE
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
                cp  "$asyncHbaseJar" ${OTSDB_HOME}/share/opentsdb/lib/asynchbase-"$jar_ver".jar
                rc=$?
            else
                logMsg "ERROR: Incompatible asynchbase jar found"
            fi
        fi
    fi

    if [ $rc -eq 1 ]; then
        logMsg "ERROR: Failed to install asyncHbase Jar file"
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

    if [ ! -z "${nodeport}" -a -w ${NEW_OT_CONF_FILE} ]; then
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
# Function to check to make sure core is running
#
#############################################################################
function checkCoreUp() {
   local rc=0
   local svc=""
   local core_status_scripts="$MAPR_HOME/initscripts/mapr-warden"


   # only add the checks for services configured locally
   if [ -e "$MAPR_HOME/roles/zookeeper" ]; then
       core_status_scripts="$core_status_scripts $MAPR_HOME/initscripts/zookeeper"
   fi

   if [ -e "$MAPR_HOME/roles/cldb" ]; then
       core_status_scripts="$core_status_scripts $MAPR_HOME/initscripts/mapr-cldb"
   fi

   # make sure sercices are up
   for svc in  $core_status_scripts; do
       $svc status
       rc=$?
       [ $rc -ne 0 ] && break
   done
   return $rc
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
       HBASE_VERSION=`cat /opt/mapr/hbase/hbaseversion`
       export COMPRESSION=NONE; export HBASE_HOME=/opt/mapr/hbase/hbase-$HBASE_VERSION; su -c ${OTSDB_HOME}/share/opentsdb/tools/create_table.sh > ${OTSDB_HOME}/var/log/opentsdb/opentsdb_install.log $MAPR_USER
       rc=$?
    fi
    if [ $rc -ne 0 ]; then
        logMsg "WARNING: Failed to create TSDB tables - need to rerun configure.sh -R or run create_table.sh as $MAPR_USER"
    fi
    return $rc
}


#############################################################################
# Function to create cron job for purging old data from tables 
#
#############################################################################
function createCronJob() {
    local CRONTAB
    local OS
    local OSNAME
    local OSVER
    local SUSE_OSVER
    local OSPATCHLVL
    local min
    local hour

    min=$RANDOM
    hour=$RANDOM

    let "min %= 60"
    let "hour %= 6"  # Try to do this at low usage time

    if [ -f /etc/redhat-release ]; then
        OS=redhat
        OSNAME=$(cut -d' ' -f1 < /etc/redhat-release)
        OSVER=$(grep -o -P '[0-9\.]+' /etc/redhat-release | cut -d. -f1,2)
    elif [ -f /etc/SuSE-release ]; then
        OS=suse
        OSVER=$(grep VERSION_ID /etc/os-release | cut -d\" -f2)
        OSPATCHLVL=$(grep PATCHLEVEL /etc/SuSE-release | cut -d' ' -f3)
        if [ -n "$OSPATCHLVL" ]; then
            SUSE_OSVER=$OSVER.$PATCHLVL
        else
            SUSE_OSVER=$OSVER
        fi
    elif [ -f /etc/lsb-release ] && grep -q DISTRIB_ID=Ubuntu /etc/lsb-release; then
        OS=ubuntu
        OSVER=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d= -f2)
    fi
    case "$OS" in
        redhat)
            CRONTAB="/var/spool/cron/$MAPR_USER"
            ;;
        suse)
            CRONTAB="/var/spool/cron/tabs/$MAPR_USER"
            ;;
        ubuntu)
            CRONTAB="/var/spool/cron/crontabs/$MAPR_USER"
            ;;
    esac

    if ! cat $CRONTAB 2> /dev/null | fgrep -q purgeData > /dev/null 2>&1 ; then
        if ! cat $CRONTAB 2> /dev/null | fgrep -q SHELL && [ ! -s $CRONTAB ]; then
            echo "SHELL=/bin/bash" >> "$CRONTAB"
        fi
        echo "$min $hour * * *      $OTSDB_HOME/bin/tsdb_cluster_mgmt.sh -purgeData >> $OTSDB_HOME/var/log/opentsdb/purgeData.log 2>&1 " >> "$CRONTAB"
        chown $MAPR_USER:$MAPR_GROUP "$CRONTAB"
    fi
    return 0
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

usage="usage: $0 [-nodeCount <cnt>] [-nodePort <port> -nodeZkCount <zkCnt>] [-nodeZkPort <zkPort>] [-R] -OT \"ip:port,ip1:port,\" -Z \"ip:port,ip1:port,\" "
if [ ${#} -gt 1 ]; then
    # we have arguments - run as as standalone - need to get params and
    # XXX why do we need the -o to make this work?
    OPTS=`getopt -a -o h -l nodeCount: -l nodePort: -l IS: -l OT: -l nodeZkCount: -l nodeZkPort: -l Z: -l R -- "$@"`
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
            --IS) 
                streamslist="$2";
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
            --R)
                OT_CONF_ASSUME_RUNNING_CORE=1
                shift 1
                ;;
            --h)
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
if [ \( -z "$nodelist" -a -z "$streamslist" \) -o -z "$zk_nodelist" ]; then
    echo "-OT or -IS, and -Z options are required"
    echo "${usage}"
    return 2 2>/dev/null || exit 2
fi

# save off a copy
cp -p ${OT_CONF_FILE} ${OT_CONF_FILE}.${NOW}

#create our new config file
cp ${OT_CONF_FILE} ${NEW_OT_CONF_FILE}

configureOTPort
configureZKQuorum
configureInputStreams
createCronJob
#install our changes
cp ${NEW_OT_CONF_FILE} ${OT_CONF_FILE}
if [ $OT_CONF_ASSUME_RUNNING_CORE -eq 1 ]; then

    installAsyncHbaseJar
    RC=$?
    if [ $RC -ne 0 ]; then
        # If we couldn't install the jar file - report early
        logMsg "WARNING: opentsdb - failed to install asynchbase jar"
        return $RC 2>/dev/null || exit $RC
    fi
    # if warden isn't running, nothing else will - likely uninstall
    if ${MAPR_HOME}/initscripts/mapr-warden status > /dev/null 2>&1 ; then
        waitForCLDB
        export MAPR_TICKETFILE_LOCATION=${MAPR_HOME}/conf/mapruserticket
        createTSDBHbaseTables
        if [ $? -eq 0 ]; then
            installWardenConfFile
        else
            logMsg "WARNING: opentsdb service not enabled - failed to setup hbase tables"
        fi
    fi
fi
true
