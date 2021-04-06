#!/bin/bash
# Copyright (c) 2009 & onwards. MapR Tech, Inc., All rights reserved
#############################################################################
#
# Script to configure opentTsdb
#
# __INSTALL_ (double underscore at the end)  gets expanded to
# __INSTALL__ during pakcaging
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
JVM_HEAP_DUMP_PATH="$MAPR_HOME/heapdumps"
NOW=$(date "+%Y%m%d_%H%M%S")
OT_CONF_ASSUME_RUNNING_CORE=${isOnlyRoles:-0}
WARDEN_START_KEY="service.command.start"
WARDEN_HEAPSIZE_MIN_KEY="service.heapsize.min"
WARDEN_HEAPSIZE_MAX_KEY="service.heapsize.max"
WARDEN_HEAPSIZE_PERCENT_KEY="service.heapsize.percent"
WARDEN_RUNSTATE_KEY="service.runstate"
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

INST_WARDEN_FILE="${MAPR_CONF_CONFD_DIR}/warden.opentsdb.conf"
PKG_WARDEN_FILE="${OTSDB_HOME}/etc/conf/warden.opentsdb.conf"

#############################################################################
# Function to extract key from warden config file
#
# Expects the following input:
# $1 = warden file to extract key from
# $2 = the key to extract
#
#############################################################################
function get_warden_value() {
    local f=$1
    local key=$2
    local val=""
    local rc=0
    if [ -f "$f" ] && [ -n "$key" ]; then
        val=$(grep "$key" "$f" | cut -d'=' -f2 | sed -e 's/ //g' )
        rc=$?
    fi
    echo "$val"
    return $rc
}

#############################################################################
# Function to update value for  key in warden config file
#
# Expects the following input:
# $1 = warden file to update key in
# $2 = the key to update
# $3 = the value to update with
#
#############################################################################
function update_warden_value() {
    local f=$1
    local key=$2
    local value=$3

    sed -i 's/\([ ]*'"$key"'=\).*$/\1'"$value"'/' "$f"
}

#############################################################################
# function to adjust ownership
#############################################################################
function adjustOwnership() {
    if [ -f "/etc/logrotate.d/opentsdb" ]; then
        if [ "$MAPR_USER" != "mapr" -o "$MAPR_GROUP" != "mapr" ]; then
            sed -i -e 's/create 640 mapr mapr/create 640 '"$MAPR_USER $MAPR_GROUP/" /etc/logrotate.d/opentsdb
            sed -i -e 's/su mapr mapr/su '"$MAPR_USER $MAPR_GROUP/" /etc/logrotate.d/opentsdb
        fi
    fi
    chown -R "$MAPR_USER":"$MAPR_GROUP" $OTSDB_HOME
    chmod -R o-rwx $OTSDB_HOME
 }

#############################################################################
# Function to install Warden conf file
#
#############################################################################
function installWardenConfFile() {
    local rc=0
    local curr_start_cmd
    local curr_heapsize_min
    local curr_heapsize_max
    local curr_heapsize_percent
    local curr_runstate
    local pkg_start_cmd
    local pkg_heapsize_min
    local pkg_heapsize_max
    local pkg_heapsize_percent
    local newestPrevVersionFile
    local tmpWardenFile

    tmpWardenFile=$(basename $PKG_WARDEN_FILE)
    tmpWardenFile="/tmp/${tmpWardenFile}$$"

    if [ -f "$INST_WARDEN_FILE" ]; then
        curr_start_cmd=$(get_warden_value "$INST_WARDEN_FILE" "$WARDEN_START_KEY")
        curr_heapsize_min=$(get_warden_value "$INST_WARDEN_FILE" "$WARDEN_HEAPSIZE_MIN_KEY")
        curr_heapsize_max=$(get_warden_value "$INST_WARDEN_FILE" "$WARDEN_HEAPSIZE_MAX_KEY")
        curr_heapsize_percent=$(get_warden_value "$INST_WARDEN_FILE" "$WARDEN_HEAPSIZE_PERCENT_KEY")
        curr_runstate=$(get_warden_value "$INST_WARDEN_FILE" "$WARDEN_RUNSTATE_KEY")
        pkg_start_cmd=$(get_warden_value "$PKG_WARDEN_FILE" "$WARDEN_START_KEY")
        pkg_heapsize_min=$(get_warden_value "$PKG_WARDEN_FILE" "$WARDEN_HEAPSIZE_MIN_KEY")
        pkg_heapsize_max=$(get_warden_value "$PKG_WARDEN_FILE" "$WARDEN_HEAPSIZE_MAX_KEY")
        pkg_heapsize_percent=$(get_warden_value "$PKG_WARDEN_FILE" "$WARDEN_HEAPSIZE_PERCENT_KEY")

        if [ "$curr_start_cmd" != "$pkg_start_cmd" ]; then
            cp "$PKG_WARDEN_FILE" "${tmpWardenFile}"
            if [ -n "$curr_runstate" ]; then
                echo "service.runstate=$curr_runstate" >> "${tmpWardenFile}"
            fi
            if [ -n "$curr_heapsize_min" ] && [ "$curr_heapsize_min" -gt "$pkg_heapsize_min" ]; then
                update_warden_value "${tmpWardenFile}" "$WARDEN_HEAPSIZE_MIN_KEY" "$curr_heapsize_min"
            fi
            if [ -n "$curr_heapsize_max" ] && [ "$curr_heapsize_max" -gt "$pkg_heapsize_max" ]; then
                update_warden_value "${tmpWardenFile}" "$WARDEN_HEAPSIZE_MAX_KEY" "$curr_heapsize_max"
            fi
            if [ -n "$curr_heapsize_percent" ] && [ "$curr_heapsize_percent" -gt "$pkg_heapsize_percent" ]; then
                update_warden_value "${tmpWardenFile}" "$WARDEN_HEAPSIZE_PERCENT_KEY" "$curr_heapsize_percent"
            fi
            cp "${tmpWardenFile}" "$INST_WARDEN_FILE"
            rc=$?
            rm -f "${tmpWardenFile}"
        fi
    else
        if  ! [ -d "${MAPR_CONF_CONFD_DIR}" ]; then
            mkdir -p "${MAPR_CONF_CONFD_DIR}" > /dev/null 2>&1
        fi
        newestPrevVersionFile=$(ls -t1 "$PKG_WARDEN_FILE"-[0-9]* 2> /dev/null | head -n 1)
        if [ -n "$newestPrevVersionFile" ] && [ -f "$newestPrevVersionFile" ]; then
            curr_runstate=$(get_warden_value "$newestPrevVersionFile" "$WARDEN_RUNSTATE_KEY")
            cp "$PKG_WARDEN_FILE" "${tmpWardenFile}"
            if [ -n "$curr_runstate" ]; then
                echo "service.runstate=$curr_runstate" >> "${tmpWardenFile}"
            fi
            cp "${tmpWardenFile}" "$INST_WARDEN_FILE"
            rc=$?
            rm -f "${tmpWardenFile}"
        else
            cp "$PKG_WARDEN_FILE" "$INST_WARDEN_FILE"
            rc=$?
        fi
    fi
    if [ $rc -ne 0 ]; then
        logWarn "opentsdb - Failed to install Warden conf file for service - service will not start"
    fi
    chown $MAPR_USER:$MAPR_GROUP "$INST_WARDEN_FILE"
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
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.count = 3\).*/\2/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.consumer.memory = 4194304\).*/\2/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.autocommit.interval = 60000\).*/\2/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.default.consumergroup = \).*/\2'"metrics"'/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.path = \).*/\2'"\/var\/mapr\/mapr.monitoring\/streams"'/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.streams.new.path = \).*/\2'"\/var\/mapr\/mapr.monitoring\/metricstreams"'/g' $NEW_OT_CONF_FILE
    else
        sed -i -e 's/\(^\s*#*\s*\)\(tsd.default.usestreams = \).*/\2'"false"'/g' $NEW_OT_CONF_FILE
        sed -i -e 's/\(^tsd.mode = ro\).*/#\1/g' $NEW_OT_CONF_FILE
    fi
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
        redhat|ol)
            CRONTAB="/var/spool/cron/$MAPR_USER"
            ;;
        suse)
            CRONTAB="/var/spool/cron/tabs/$MAPR_USER"
            ;;
        ubuntu)
            CRONTAB="/var/spool/cron/crontabs/$MAPR_USER"
            ;;
        *)
            echo "ERROR: Do not recognize OS=$OS - not installing crontab"
            return 0;;
    esac

    if ! cat $CRONTAB 2> /dev/null | fgrep -q 'tsdb_cluster_mgmt.sh -purgeData' > /dev/null 2>&1 ; then
        if ! cat $CRONTAB 2> /dev/null | fgrep -q SHELL && [ ! -s $CRONTAB ]; then
            echo "SHELL=/bin/bash" >> "$CRONTAB"
        fi
        # We disable it for now due to what appears to be a signal racecondition in java that
        # cause the OT scan process to not exit occationally - see OTSDB-25
        echo "$min $hour * * *      $OTSDB_HOME/bin/tsdb_cluster_mgmt.sh -purgeData -retentionPeriod '2 weeks ago'" >> "$CRONTAB"
        chown $MAPR_USER:$MAPR_GROUP "$CRONTAB"
    fi
    return 0
}

check_java_heap_dump_dir() {
    if [ ! -d "$JVM_HEAP_DUMP_PATH" ]; then
        mkdir -m 777 -p ${JVM_HEAP_DUMP_PATH}
    fi
}

removeOldAsyncHbase() {
    #make sure we don't have old asynchbase jar left over due to upgrade
    OTSDB_LIB="$OTSDB_HOME/share/opentsdb/lib"
    if find "$OTSDB_LIB" -name 'asynchbase-*jar' > /dev/null; then
        rm -f "$OTSDB_LIB"/asynchbase-*jar
    fi
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
usage="usage: $0 [-help] [-EC <commonEcoOpts>] [-nodeCount <cnt>] [-nodePort <port>]\n\t[-nodeZkCount <zkCnt>] [-nodeZkPort <zkPort>] [-customSecure] [-secure] [-unsecure]\n\t[-IS] [-noStreams] [-R] -OT \"ip:port,ip1:port..\" -Z \"ip:port,ip1:port..\" "
if [ ${#} -gt 0 ]; then
    # we have arguments - run as as standalone - need to get params and
    OPTS=$(getopt -a -o chn:p:suz:C:INO:P:RZ: -l EC: -l help -l nodeCount: -l nodePort: -l IS -l OT: -l nodeZkCount: -l nodeZkPort: -l Z: -l R -l customSecure -l unsecure -l secure -l noStreams -- "$@")
    if [ $? != 0 ]; then
        echo -e ${usage}
        return 2 2>/dev/null || exit 2
    fi
    eval set -- "$OPTS"

    while (( $# )) ; do
        case "$1" in
            --EC|-C)
                #Parse Common options
                #Ingore ones we don't care about
                ecOpts=($2);
                shift 2
                restOpts="$@"
                eval set -- "${ecOpts[@]} --"
                while (( $# )) ; do
                    case "$1" in
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
                            ;;
                        *)
                            #echo "Ignoring common option $j"
                            shift 1;;
                    esac
                done
                shift 2 
                eval set -- "$restOpts"
                ;;
            --IS|-I)
                useStreams=1;
                shift
                ;;
            --OT|-O) # not used at the moment
                nodelist="$2";
                shift 2
                ;;
            --R|-R)
                OT_CONF_ASSUME_RUNNING_CORE=1
                shift 1
                ;;
            --Z|-Z)
                zk_nodelist="$2";
                shift 2
                ;;
            --noStreams|-N)
                useStreams=0;
                shift
                ;;
            --nodeCount|-n)
                nodecount="$2";
                shift 2
                ;;
            --nodeZkCount|-z)
                zk_nodecount="$2";
                shift 2
                ;;
            --nodePort|-P)
                nodeport="$2";
                shift 2
                ;;
            --nodeZkPort|-p)
                zk_nodeport="$2";
                shift 2
                ;;
            --customSecure|-c)
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
            --secure|-s)
                secureCluster=1;
                shift 1;;
            --unsecure|-u)
                secureCluster=0;
                shift 1;;
            --help|-h)
                echo -e ${usage}
                return 2 2>/dev/null || exit 2
                ;;
            --)
                shift
                ;;
            *)
                echo "Unknown option $1"
                echo -e ${usage}
                return 2 2>/dev/null || exit 2
                ;;
        esac
    done
fi

if [ -z "$zk_nodelist" ]; then
    zk_nodelist=$(getZKServers)
fi

# make sure we have what we need
# we don't really need the OT list at the moment, nor do we use the two counts
if [ \( -z "$nodelist" -a "$useStreams" -eq 0 \) -o -z "$zk_nodelist" ]; then
    echo "-OT is required when not using streams"
    echo -e "${usage}"
    return 2 2>/dev/null || exit 2
fi

check_java_heap_dump_dir

# save off a copy
cp -p ${OT_CONF_FILE} ${OT_CONF_FILE}.${NOW}

#create our new config file
cp ${OT_CONF_FILE} ${NEW_OT_CONF_FILE}
configureOTPort
registerOTPort
configureZKQuorum
configureInputStreams
removeOldAsyncHbase
createCronJob
#install our changes
cp ${NEW_OT_CONF_FILE} ${OT_CONF_FILE}
installWardenConfFile
adjustOwnership
rm -f "${NEW_OT_CONF_FILE}"
# remove state file
if [ -f "$OTSDB_HOME/etc/.not_configured_yet" ]; then
    rm -f "$OTSDB_HOME/etc/.not_configured_yet"
fi

true
