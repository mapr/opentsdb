#!/bin/bash
# Copyright (c) 2009 & onwards. MapR Tech, Inc., All rights reserved

#############################################################################
#
# Script to manage opentsdb cluster
# 
# 
#
# __INSTALL_ (double undersoces on both sides) 
# gets expanded to /opt/mapr/opentsdb/opentsdb-<ver> during pakcaging
# set OT_HOME explicitly if running this in a source build env.
#
# This script is used for some simple opentsdb management and monitoring tasks.
#
#############################################################################

MAPR_HOME=${MAPR_HOME:-/opt/mapr}
OT_DEBUG_OPTS=" -S -v -v -v -v "
OT_HOME=${OT_HOME:-/opt/mapr/opentsdb/opentsdb-2.4.0}
OT_LOGDIR="${OT_LOGDIR:-$OT_HOME/var/log/opentsdb}"
OT_LOGFILE="${OT_LOGFILE:-$OT_LOGDIR/ot_purgeData.log}"
OT_SCAN_DAEMON_LOGFILE="${OT_SCAN_DAEMON_LOGFILE:-$OT_LOGDIR/opentsdb_scandaemon.log}"
OT_SCAN_DAEMON_QRYLOGFILE="${OT_SCAN_DAEMON_QRYLOGFILE:-$OT_LOGDIR/opentsdb_scandaemon_query.log}"
OT_OPTS=" -s "
OT_PORT=${OT_PORT:-4242}
OT_PRETTY=${OT_PRETTY:-0}
# This should be expressions parsed by the date command ( see man date), like
# '2 days ago'
# '2 weeks ago'
# '2 months ago'
# '2 years ago'
OT_RETENTION_PERIOD="${OT_RETENTION_PERIOD:-2 weeks ago}"
OT_VERBOSE=${OT_VERBOSE:-0}

# main
#
#
# tsdb_cluster_mgmt.sh
#                       [ -debug ]
#                       [ -getConfig ]
#                       [ -getJvmStats ]
#                       [ -getQueryStats ]
#                       [ -getRegionClientStats ]
#                       [ -getThreadStats ]
#                       [ -logFile <filename> ]
#                       [ -port <port> ]
#                       [ -pretty ]
#                       [ -purgeData ]
#                       [ -retentionPeriod <str> ]
#                       [ -verbose ]
#
#

OPER=""
usage="usage: $0 \n\t\t[-debug] [-getConfig] \n\t\t[-getJvmStats] [-getQueryStats] [-getRegionClientStats] [-getThreadStats]\n\t\t[-logfile <filename> ] [-port <port>] [-pretty] [-purgeData] [-retentionPeriod] [-verbose] [<hostname>]"
if [ ${#} -ge 1 ] ; then
   # we have arguments - run as as standalone - need to get params and
   OPTS=`getopt -a -o h -l debug -l getConfig -l getJvmStats -l getQueryStats -l getRegionClientStats -l getThreadStats -l logFile: -l port: -l pretty -l purgeData -l retentionPeriod: -l verbose -- "$@"`
   if [ $? != 0 ] ; then
      echo -e ${usage}
      return 2 2>/dev/null || exit 2
   fi
   eval set -- "$OPTS"

   for i ; do
      case "$i" in
         --debug)
              OT_OPTS="$OT_DEBUG_OPTS"
              shift 1;;
         --getConfig)
              OT_HEADERS=""
              OT_URL='api/config'
              OT_MISC=""
              OPER="GET"
              SHOW_OUTPUT=1
              shift 1;;
         --getJvmStats)
              OT_HEADERS=""
              OT_URL='api/stats/jvm'
              OT_MISC=""
              OPER="GET"
              SHOW_OUTPUT=1
              shift 1;;
         --getQueryStats)
              OT_HEADERS=""
              OT_URL='api/stats/query'
              OT_MISC=""
              OPER="GET"
              SHOW_OUTPUT=1
              shift 1;;
         --getRegionClientStats)
              OT_HEADERS=""
              OT_URL='api/stats/region_clients'
              OT_MISC=""
              OPER="GET"
              SHOW_OUTPUT=1
              shift 1;;
         --getThreadStats)
              OT_HEADERS=""
              OT_URL='api/stats/threads'
              OT_MISC=""
              OPER="GET"
              SHOW_OUTPUT=1
              shift 1;;
         --logFile)
              OT_LOGFILE=$2
              shift 2;;
         --port)
              OT_PORT=$2
              shift 2;;
         --pretty)
              OT_PRETTY=1
              shift 1;;
         --purgeData)
              OT_HEADERS=""
              OT_URL='api/suggest?type=metrics&max=500'
              OT_MISC=""
              OPER="GET"
              OT_MSG="data successfully purged from $OT_RETENTION_PERIOD"
              SHOW_OUTPUT=0
              EXPECT_ACK=""
              POST_PROCESSING_OP="purgeData"
              shift 1;;
         --retentionPeriod)
              OT_RETENTION_PERIOD="$2"
              shift 2;;
         --verbose)
              OT_VERBOSE=1
              shift 1;;
         -h)
              echo -e ${usage}
              exit 2
              ;;
         --)
              shift;;
      esac
   done

else
   echo -e "${usage}"
   exit 2
fi

if [ $# -gt 1 -o -z "$OPER" ]; then
    echo "Missing operation, or too many arguments"
    echo -e "${usage}"
    exit 1
fi

if [ $# -eq 1 ]; then
    OT_HOST=$1
else
    OT_HOST=$(hostname)
fi

SUCCESS=0
RESP=$(curl $OT_OPTS -X$OPER $OT_HEADERS ${OT_HOST}:${OT_PORT}/${OT_URL} ${OT_MISC})
RC=$?
if [ ${RC} -eq 0 ] ; then
   if [ -n "$EXPECT_ACK" ] ; then
       echo $RESP | grep -q $EXPECT_ACK && SUCCESS=1
   else
       SUCCESS=1
   fi
fi

if [ $SUCCESS -eq 1 ] ; then
   if [ $SHOW_OUTPUT -eq 1 ] ; then 
       if [ $OT_PRETTY -eq 1 ]; then
           echo "$RESP" | python -m json.tool
       else
           echo "$RESP"
       fi
   else
       SUCCESS=1
       case "$POST_PROCESSING_OP" in
           "purgeData")
               export JVMARGS="-enableassertions -enablesystemassertions -DLOG_FILE=$OT_SCAN_DAEMON_LOGFILE -DQUERY_LOG=$OT_SCAN_DAEMON_QRYLOGFILE"
               export MAPR_TICKETFILE_LOCATION=${MAPR_HOME}/conf/mapruserticket
               if [ "$OT_VERBOSE" -eq 1 ]; then
                   OT_SCAN_LOGFILE=$OT_LOGFILE
               else
                   mkdir -p "$OT_LOGDIR/metrics_tmp"
               fi
               OT_LOGFILE_BN=$(basename $OT_LOGFILE)
               echo "$(date) Purging old data - retention period: $OT_RETENTION_PERIOD ">> $OT_LOGFILE
               for metric in $(echo "$RESP" | sed -e 's/\[//;s/\]//;s/\,/ /g;s/"//g' ); do
                   if [ "$OT_VERBOSE" -eq 0 ]; then
                       OT_SCAN_LOGFILE=${OT_LOGDIR}/${OT_LOGFILE_BN}.$metric
                   fi
                   echo "$(date) Purging old data for $metric" >> $OT_LOGFILE
                   $OT_HOME/bin/tsdb scan --delete 2000/01/01 $(date --date="$OT_RETENTION_PERIOD" '+%Y/%m/%d') sum $metric >> $OT_SCAN_LOGFILE 2>> $OT_LOGFILE
                   if [ $? -eq 0 ]; then
                       if [ "$OT_VERBOSE" -eq 0 ]; then

                           cnt=$(wc -l $OT_SCAN_LOGFILE | cut -d' ' -f 1 )
                           echo "$(date) Purged $cnt entries of metric $metric succeded" >> $OT_LOGFILE
                           rm -f "$OT_SCAN_LOGFILE"
                       else
                           echo "$(date) Purging of metric $metric succeeded" >> $OT_LOGFILE
                       fi
                   else
                       echo "$(date) Purging of metric $metric failed" >> $OT_LOGFILE
                       SUCCESS=0
                   fi
               done
               echo "$(date) Purging old data complete - success =  $SUCCESS ">> $OT_LOGFILE
               ;;
       esac
       if [ $SUCCESS -eq 1 ] && [ -n "$OT_MSG" ]; then
           echo "$(date) $OT_MSG"
       fi
   fi
else 
   echo "OT operation failed - rc = ${RC} response = $RESP"
fi

exit ${RC}
