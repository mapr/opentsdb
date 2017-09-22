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
NOW=$(date "+%Y%m%d_%H%M%S")
ASYNCVER="1.7"   # two most significat version number of compatible asynchbase jar
OT_CONF_ASSUME_RUNNING_CORE=${isOnlyRoles:-0}
RC=0
nodeport="4242"
nodecount=0
nodelist=""
useStreams=1
zk_nodecount=0
zk_nodeport=5181
zk_nodelist=""
secureCluster=0

if [ -e "${MAPR_HOME}/server/common-ecosystem.sh" ]; then
    . "${MAPR_HOME}/server/common-ecosystem.sh"
else
   echo "Failed to source common-ecosystem.sh"
   exit 0
fi

#############################################################################
# Function to change ownership of our files to $MAPR_USER
#
#############################################################################
function adjustOwnerShip() {
    chown -R "$MAPR_USER":"$MAPR_GROUP" $OTSDB_HOME
}

#############################################################################
# Function to install Warden conf file
#
#############################################################################
function installWardenConfFile() {
    # make sure conf directory exist
    if ! [ -d ${MAPR_CONF_DIR}/conf.d ]; then
        mkdir -p ${MAPR_CONF_DIR}/conf.d > /dev/null 2>&1
    fi

    # Copy warden conf
    cp ${OTSDB_HOME}/etc/conf/warden.opentsdb.conf ${MAPR_CONF_DIR}/conf.d/
    if [ $? -ne 0 ]; then
        logWarn "opentsdb - Failed to install Warden conf file for service - service will not start"
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
    if [ $useStreams -eq 1 ]; then
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.default.usestreams = \).*/\2'"true"'/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.mode = ro\).*/\2/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.count = 64\).*/\2/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.consumer.memory = 2097152\).*/\2/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.default.consumergroup = \).*/\2'"metrics"'/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.path = \).*/\2'"\/var\/mapr\/mapr.monitoring\/streams"'/g' $NEW_OT_CONF_FILE
    else
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.default.usestreams = \).*/\2'"false"'/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^tsd.mode = ro\).*/#\1/g' $NEW_OT_CONF_FILE
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
                logErr "Incompatible asynchbase jar found"
            fi
        fi
    fi

    if [ $rc -eq 1 ]; then
        logErr "Failed to install asyncHbase Jar file"
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
# Function to check and register port availablilty
#
#############################################################################
function registerOTPort() {
    if checkNetworkPortAvailability $nodeport ; then
        registerNetworkPort opentsdb $nodeport
        if [ $? -ne 0 ]; then
            logWarn "opentsdb - Failed to register port"
        fi
    else
        service=$(whoHasNetworkPort $nodeport)
        if [ "$service" != "opentsdb" ]; then
            logWarn "opentsdb - port $nodeport in use by $service service"
        fi
    fi
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
# Function to create cron job for purging old data from tables 
#
#############################################################################
function createCronJob() {
    local CRONTAB
    local min
    local hour

    min=$RANDOM
    hour=$RANDOM

    let "min %= 60"
    let "hour %= 6"  # Try to do this at low usage time

    # $OS is set by initCfgEnv
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

#sets MAPR_USER/MAPR_GROUP/logfile
initCfgEnv

# Parse the arguments
usage="usage: $0 [-EC <commonEcoOpts>] [-nodeCount <cnt>] [-nodePort <port>]\n\t[-nodeZkCount <zkCnt>] [-nodeZkPort <zkPort>] [-customSecure] [-secure] [-unsecure]\n\t[-IS] [-noStreams] [-R] -OT \"ip:port,ip1:port..\" -Z \"ip:port,ip1:port..\" "
if [ ${#} -gt 1 ]; then
    # we have arguments - run as as standalone - need to get params and
    # XXX why do we need the -o to make this work?
    OPTS=`getopt -a -o h -l EC: -l nodeCount: -l nodePort: -l IS -l OT: -l nodeZkCount: -l nodeZkPort: -l Z: -l R -l customSecure -l unsecure -l secure -l noStreams -- "$@"`
    if [ $? != 0 ]; then
        echo -e ${usage}
        return 2 2>/dev/null || exit 2
    fi
    eval set -- "$OPTS"

    for i in "$@" ; do
        case "$i" in
            --EC) 
                #Parse Common options
                #Ingore ones we don't care about
                ecOpts=($2);
                shift 2
                restOpts="$@"
                eval set -- "${ecOpts[@]} --"
                for j in "$@" ; do
                    case "$j" in
                        --OT|-OT)
                            nodelist="$2"
                            shift 2;;
                        --R|-R)
                            OT_CONF_ASSUME_RUNNING_CORE=1
                            shift 1
                            ;;
                        --noStreams|-noStreams)
                            useStreams=0;
                            shift
                            ;;
                        --) shift
                            break;;
                        *)
                            #echo "Ignoring common option $j"
                            shift 1;;
                    esac
                done
                shift 2 
                eval set -- "$restOpts"
                ;;
            --IS) 
                useStreams=1;
                shift
                ;;
            --OT) # not used at the moment
                nodelist="$2";
                shift 2
                ;;
            --R)
                OT_CONF_ASSUME_RUNNING_CORE=1
                shift 1
                ;;
            --Z)
                zk_nodelist="$2";
                shift 2
                ;;
            --noStreams)
                useStreams=0;
                shift
                ;;
            --nodeCount)
                nodecount="$2";
                shift 2
                ;;
            --nodeZkCount)
                zk_nodecount="$2";
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
            --customSecure)
                if [ -f "$OTSDB_HOME/etc/.not_configured_yet" ]; then
                    # opentsdb added after secure 5.x cluster upgraded to customSecure
                    # 6.0 cluster. Deal with this by assuming a regular --secure path
                    :
                else 
                    # this is a little tricky. It either means a simpel configure.sh -R run
                    # or it means that opentsdb was part of the 5.x to 6.0 upgrade
                    # At the moment opentsdb knows of no other security settings besides jmx
                    # and port numbers the jmx uses. Since we have no way of detecting what 
                    # these ports are - we assume for now they don't change.
                    :
                fi
                secureCluster=1;
                shift 1;;
            --secure)
                secureCluster=1;
                shift 1;;
            --unsecure)
                secureCluster=0;
                shift 1;;
            --h)
                echo -e ${usage}
                return 2 2>/dev/null || exit 2
                ;;
            --)
                shift
                break
                ;;
        esac
    done
else
    echo -e "${usage}"
    return 2 2>/dev/null || exit 2
fi

if [ -z "$zk_nodelist" ]; then
    zk_nodelist=$(getZKServers)
fi

# make sure we have what we need
# we don't really need the OT list at the moment, nor do we use the two counts
if [ \( -z "$nodelist" -a -z "$useStreams" \) -o -z "$zk_nodelist" ]; then
    echo "-OT or -IS, and -Z options are required"
    echo -e "${usage}"
    return 2 2>/dev/null || exit 2
fi

# save off a copy
cp -p ${OT_CONF_FILE} ${OT_CONF_FILE}.${NOW}

#create our new config file
cp ${OT_CONF_FILE} ${NEW_OT_CONF_FILE}
configureOTPort
registerOTPort
configureZKQuorum
configureInputStreams
createCronJob
#install our changes
cp ${NEW_OT_CONF_FILE} ${OT_CONF_FILE}

installAsyncHbaseJar
RC=$?
if [ $RC -ne 0 ]; then
    # If we couldn't install the jar file - report early
    logWarn "opentsdb - failed to install asynchbase jar"
    return $RC 2>/dev/null || exit $RC
fi
installWardenConfFile
rm -f "${NEW_OT_CONF_FILE}"
true
