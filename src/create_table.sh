#!/usr/bin/env bash
# Small script to setup the tables used by OpenTSDB.
LOGFILE_RETENTION="${LOGFILE_RETENTION:-14}" # remove log files older than this (in days)

MONITORING_VOLUME_NAME=${MONITORING_VOLUME_NAME:-"mapr.monitoring"}
MONITORING_TSDB_TABLE=${MONITORING_TSDB_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb"}
MONITORING_UID_TABLE=${MONITORING_UID_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb-uid"}
MONITORING_TREE_TABLE=${MONITORING_TREE_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb-tree"}
MONITORING_META_TABLE=${MONITORING_META_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb-meta"}
LOGDIR="__INSTALL__/var/log/opentsdb/"
LOGFILEBASE="opentsdb_create_table_"
LOGFILE="$LOGDIR/$LOGFILEBASE$$.log"
MONITORING_LOCK_DIR=${MONITORING_LOCK_DIR:-"/tmp/otLockFile"}
BLOOMFILTER=${BLOOMFILTER-'ROW'}
# LZO requires lzo2 64bit to be installed + the hadoop-gpl-compression jar.
COMPRESSION=${COMPRESSION-'LZO'}
# All compression codec names are upper case (NONE, LZO, SNAPPY, etc).
COMPRESSION=`echo "$COMPRESSION" | tr a-z A-Z`
# DIFF encoding is very useful for OpenTSDB's case that many small KVs and common prefix.
# This can save a lot of storage space.
DATA_BLOCK_ENCODING=${DATA_BLOCK_ENCODING-'DIFF'}
DATA_BLOCK_ENCODING=`echo "$DATA_BLOCK_ENCODING" | tr a-z A-Z`
TSDB_TTL=${TSDB_TTL-'FOREVER'}

function cleanLogFiles() {
    oldLogFiles=$(find $LOGDIR -name "$LOGFILEBASE*" -mtime +$LOGFILE_RETENTION -print)
    if [ $? -eq 0 ] && [ -n "$oldLogFiles" ]; then
        echo "Removing log files older than $LOGFILE_RETENTION" | tee -a $LOGFILE
        rm -f "$oldLogFiles" 
    fi
}

function createTSDB() {
  # Create $MONITORING_VOLUME_NAME volume before creating tables
  maprcli volume info -name $MONITORING_VOLUME_NAME -json >> $LOGFILE 2>&1
  RC00=$?
  maprcli volume info -path /var/mapr/$MONITORING_VOLUME_NAME -json >> $LOGFILE 2>&1
  RC01=$?
  if [ $RC00 -ne 0 -a $RC01 -ne 0 ]; then
    echo "Creating volume $MONITORING_VOLUME_NAME" | tee -a $LOGFILE
    maprcli volume create -name $MONITORING_VOLUME_NAME -path /var/mapr/$MONITORING_VOLUME_NAME >> $LOGFILE 2>&1
    RC0=$?
    if [ $RC0 -ne 0 ]; then
      echo "Create volume failed for /var/mapr/$MONITORING_VOLUME_NAME" | tee -a $LOGFILE
      return $RC0
    fi
  elif [ $RC00 -ne $RC01 ]; then
    echo "$MONITORING_VOLUME_NAME exists or another volume is already mounted at location /var/mapr/$MONITORING_VOLUME_NAME" | tee -a $LOGFILE
    return $RC00
  fi


  case $COMPRESSION in
    (NONE|LZO|GZIP|SNAPPY)  :;;  # Known good.
    (*)
      echo >&2 "warning: compression codec '$COMPRESSION' might not be supported."
      ;;
  esac

  case $DATA_BLOCK_ENCODING in
    (NONE|PREFIX|DIFF|FAST_DIFF|ROW_INDEX_V1)  :;; # Know good
    (*)
      echo >&2 "warning: encoding '$DATA_BLOCK_ENCODING' might not be supported."
      ;;
  esac

  RC=0
  RC0=0
  RC1=0
  RC2=0
  RC3=0
  # HBase scripts also use a variable named `HBASE_HOME', and having this
  # variable in the environment with a value somewhat different from what
  # they expect can confuse them in some cases.  So rename the variable.
  hbh=$HBASE_HOME
  unset HBASE_HOME
  if ! hadoop fs -stat $MONITORING_UID_TABLE > /dev/null 2>&1 ; then
    MAPR_DAEMON=spyglass "$hbh/bin/hbase" shell <<EOF_UID!!  >> $LOGFILE 2>&1 
    create '$MONITORING_UID_TABLE',
      {NAME => 'id', COMPRESSION => '$COMPRESSION', BLOOMFILTER => '$BLOOMFILTER', DATA_BLOCK_ENCODING => '$DATA_BLOCK_ENCODING'},
      {NAME => 'name', COMPRESSION => '$COMPRESSION', BLOOMFILTER => '$BLOOMFILTER', DATA_BLOCK_ENCODING => '$DATA_BLOCK_ENCODING'}
EOF_UID!!
    RC0=$?
    if [ $RC0 -ne 0 ]; then
      echo "hbase shell failed to create tables $MONITORING_UID_TABLE  rc = $RC0" | tee -a $LOGFILE
    fi
  else
      echo "Table $MONITORING_UID_TABLE alread exist - skipping" | tee -a $LOGFILE
  fi

  if ! hadoop fs -stat $MONITORING_TSDB_TABLE > /dev/null 2>&1 ; then
    MAPR_DAEMON=spyglass "$hbh/bin/hbase" shell <<EOF_TSDB!!  >> $LOGFILE 2>&1 
    create '$MONITORING_TSDB_TABLE',
      {NAME => 't', VERSIONS => 1, COMPRESSION => '$COMPRESSION', BLOOMFILTER => '$BLOOMFILTER', DATA_BLOCK_ENCODING => '$DATA_BLOCK_ENCODING'}
EOF_TSDB!!
    RC1=$?
    if [ $RC1 -ne 0 ]; then
      echo "hbase shell failed to create tables $MONITORING_TSDB_TABLE  rc = $RC1" | tee -a $LOGFILE
    fi
  else
      echo "Table $MONITORING_TSDB_TABLE alread exist - skipping" | tee -a $LOGFILE
  fi

  if ! hadoop fs -stat $MONITORING_TREE_TABLE > /dev/null 2>&1 ; then
    MAPR_DAEMON=spyglass "$hbh/bin/hbase" shell <<EOF_TREE!!  >> $LOGFILE 2>&1 
    create '$MONITORING_TREE_TABLE',
      {NAME => 't', VERSIONS => 1, COMPRESSION => '$COMPRESSION', BLOOMFILTER => '$BLOOMFILTER', DATA_BLOCK_ENCODING => '$DATA_BLOCK_ENCODING'}
EOF_TREE!!
    RC2=$?
    if [ $RC2 -ne 0 ]; then
      echo "hbase shell failed to create tables $MONITORING_TREE_TABLE  rc = $RC2" | tee -a $LOGFILE
    fi
  else
      echo "Table $MONITORING_TREE_TABLE alread exist - skipping" | tee -a $LOGFILE
  fi

  if ! hadoop fs -stat $MONITORING_META_TABLE > /dev/null 2>&1 ; then
    MAPR_DAEMON=spyglass "$hbh/bin/hbase" shell <<EOF_META!!  >> $LOGFILE 2>&1 
    create '$MONITORING_META_TABLE',
      {NAME => 'name', COMPRESSION => '$COMPRESSION', BLOOMFILTER => '$BLOOMFILTER', DATA_BLOCK_ENCODING => '$DATA_BLOCK_ENCODING'}
EOF_META!!
    RC3=$?
    if [ $RC3 -ne 0 ]; then
      echo "hbase shell failed to create tables $MONITORING_META_TABLE  rc = $RC3" | tee -a $LOGFILE
    fi
  else
      echo "Table $MONITORING_TREE_TABLE alread exist - skipping" | tee -a $LOGFILE
  fi
  if [ $RC0 -ne 0 ] || [ $RC1 -ne 0 ] || [ $RC2 -ne 0 ] || [ $RC2 -ne 0 ]; then
    RC=1
  fi
  return $RC
}

isStaleLockFile() {
    echo "Checking to see if lock directory exist" | tee -a  $LOGFILE
    MOD_TIME="$(hadoop fs -stat $MONITORING_LOCK_DIR) 2>> $LOGFILE"
    if [ $? -ne 0 ]; then
        # the most common error is that the file doesn't exist and we get
        # No such file or directory back.
        return 0
    fi
    if [ -n "$MOD_TIME" ]; then
        echo "MOD_TIME=$MOD_TIME" | tee -a $LOGFILE
        BINDATE=$(which date)
        if [ -n "$BINDATE" ]; then
            EPOC_MOD_TIME=$(/bin/date -u +%s -d"$MOD_TIME")
            NOW_EPOC=$($BINDATE -u +%s)
            if [ -n "$EPOC_MOD_TIME" ] && [ -n "$NOW_EPOC" ]; then
                DIFF_SEC=$(expr "$NOW_EPOC" - "$EPOC_MOD_TIME")
                if [ "$DIFF_SEC" -gt 300 ]; then
                    echo "found stale lock directory ... removing - trying again" | tee -a $LOGFILE
                    hadoop fs -rm -r $MONITORING_LOCK_DIR
                    return $?
                else
                    return 0
                fi
            else
                echo "Failed convert time -  EPOC_MOD_TIME=$EPOC_MOD_TIME, NOW_EPOC=$NOW_EPOC" | tee -a  $LOGFILE
            fi
        else
            echo "Failed to find the date command" | tee -a  $LOGFILE
            return 0
        fi
    else
        echo "Failed to get stat time - but got 0 return code" | tee -a  $LOGFILE
        return 0
    fi
}

# Remove stale lock directory if present
isStaleLockFile
if [ $? -ne 0 ]; then
    echo "Failed to remove stale lock directory $?" | tee -a $LOGFILE
fi

# Try to create lock directory - with 30 retries
i=0
while [[ $i -lt 30 ]]; do
  echo "Creating lock directory" | tee -a $LOGFILE
  hadoop fs -mkdir $MONITORING_LOCK_DIR 2>&1 | tee -a $LOGFILE
  RC=$?
  if [ $RC -ne 0 ]; then
    #echo "Unable to create lock directory $MONITORING_LOCK_DIR"
    sleep 2
  else
    break
  fi
  (( i++ ))
done

# Failed after retries - exit
if [[ $i -eq 30 ]]; then
  echo "Failed to create lock directory $MONITORING_LOCK_DIR after $i attempts." | tee -a $LOGFILE
  exit 1 
fi
cleanLogFiles
createTSDB
RC1=$?

# Try to remove lock directory - with 30 retries
i=0
while [[ $i -lt 30 ]]; do
  hadoop fs -rm -r $MONITORING_LOCK_DIR
  RC=$?
  if [ $RC -ne 0 ]; then
    #echo "Unable to remove lock directory $MONITORING_LOCK_DIR"
    sleep 2
  else
    break
  fi
  (( i++ ))
done

# check return code from creating volumes/tables first
if [ $RC1 -ne 0 ]; then
  return $RC1 2> /dev/null || exit $RC1
fi

# Failed after retries - exit
if [[ $i -eq 30 ]]; then
  echo "Failed to remove lock directory $MONITORING_LOCK_DIR after $i attempts. Please remove the lock directory manually and run this script again"
  exit 1 
fi

echo "Complete!"

true

