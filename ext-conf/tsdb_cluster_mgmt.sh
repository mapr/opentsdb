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

OT_PORT=${OT_PORT:-4242}
OT_OPTS=" -s "
OT_PRETTY=0
DEBUG_OPTS=" -S -v -v -v -v "
OT_HOME=${OT_HOME:-__INSTALL__}


# main
#
#
# tsdb_cluster_mgmt.sh  [ -purgeData ] 
#                       [ -getConfig ]
#                       [ -getJvmStats ]
#                       [ -getQueryStats ]
#                       [ -getRegionClientStats ]
#                       [ -getThreadStats ]
#                       [ -port <port> ]
#                       [ -pretty ]
#                       [ -debug ]
#
#

OPER=""
usage="usage: $0 \n\t\t[-purgeData] [-getConfig] \n\t\t[-getJvmStats] [-getQueryStats] [-getRegionClientStats] [-getThreadStats]\n\t\t[-pretty] [-port <port>] [-debug] [<hostname>]"
if [ ${#} -ge 1 ] ; then
   # we have arguments - run as as standalone - need to get params and
   # XXX why do we need the -o to make this work?
   OPTS=`getopt -a -o h -l purgeData -l getJvmStats -l getQueryStats -l getRegionClientStats -l getThreadStats -l getConfig -l pretty -l port: -l debug -- "$@"`
   if [ $? != 0 ] ; then
      echo -e ${usage}
      return 2 2>/dev/null || exit 2
   fi
   eval set -- "$OPTS"

   for i ; do
      case "$i" in
         --purgeData)
              OT_HEADERS=""
              OT_URL='api/suggest?type=metrics&max=500'
              OT_MISC=""
              OPER="GET"
              OT_MSG="data successfully purged"
              SHOW_OUTPUT=0
              EXPECT_ACK=""
              POST_PROCESSING_OP="purgeData"
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
         --debug)
              OT_OPTS="$DEBUG_OPTS"
              shift 1;;
         --pretty)
              OT_PRETTY=1
              shift 1;;
         --port)
              OT_PORT=$2
              shift 2;;
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
       case "$POST_PROCESSING_OP" in
           "purgeData")
               for metric in $(echo "$RESP" | sed -e 's/\[//;s/\]//;s/\,/ /g;s/"//g' ); do
                   echo "Purging old data for $metric"
                   $OT_HOME/bin/tsdb scan --delete 2000/01/01 $(date --date='2 weeks ago' +'%Y/%m/%d') sum $metric
               done
               ;;
       esac
       if [ $SUCCESS -eq 1 ]; then
           echo "$OT_MSG"
       fi
   fi
else 
   echo "OT operation failed - rc = ${RC} response = $RESP"
fi

exit ${RC}
