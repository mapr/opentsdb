#!/usr/bin/env bash
# Small script to setup the tables used by OpenTSDB.

MONITORING_VOLUME_NAME=${MONITORING_VOLUME_NAME:-"mapr.monitoring"}
MONITORING_TSDB_TABLE=${MONITORING_TSDB_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb"}
MONITORING_UID_TABLE=${MONITORING_UID_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb-uid"}
MONITORING_TREE_TABLE=${MONITORING_TREE_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb-tree"}
MONITORING_META_TABLE=${MONITORING_META_TABLE:-"/var/mapr/$MONITORING_VOLUME_NAME/tsdb-meta"}
LOGFILE="__INSTALL__/var/log/opentsdb/opentsdb_create_table_$$.log"
MONITORING_LOCK_DIR=${MONITORING_LOCK_DIR:-"/tmp/otLockFile"}

function createTSDB() {
  # Create $MONITORING_VOLUME_NAME volume before creating tables
  maprcli volume info -name $MONITORING_VOLUME_NAME > $LOGFILE 2>&1
  RC00=$?
  maprcli volume info -path /var/mapr/$MONITORING_VOLUME_NAME > $LOGFILE 2>&1
  RC01=$?
  if [ $RC00 -ne 0 -a $RC01 -ne 0 ]; then
    echo "Creating volume $MONITORING_VOLUME_NAME"
    maprcli volume create -name $MONITORING_VOLUME_NAME -path /var/mapr/$MONITORING_VOLUME_NAME > $LOGFILE 2>&1
    RC0=$?
    if [ $RC0 -ne 0 ]; then
      echo "Create volume failed for /var/mapr/$MONITORING_VOLUME_NAME"
      return $RC0
    fi
  elif [ $RC00 -ne $RC01 ]; then
    echo "$MONITORING_VOLUME_NAME exists or another volume is already mounted at location /var/mapr/$MONITORING_VOLUME_NAME"
    return $RC00
  fi
  for t in $MONITORING_TSDB_TABLE $MONITORING_UID_TABLE $MONITORING_TREE_TABLE $MONITORING_META_TABLE; do
    maprcli table info -path $t > $LOGFILE 2>&1
    RC1=$?
    if [ $RC1 -ne 0 ]; then
      echo "Creating $t table..."
      maprcli table create -path $t -defaultreadperm p -defaultwriteperm p -defaultappendperm p >> $LOGFILE 2>&1
      RC2=$?
      if [ $RC2 -ne 0 ]; then
        # check if another node beat us too it
	if ! tail -1 $LOGFILE | fgrep $t | fgrep 'File exists' > /dev/null 2>&1 ; then
	  echo "Create table failed for $t"
	  return $RC2
	else
	  continue
	fi
      fi
      COLUMN_FLAG="false"
      if [ "$t" == "$MONITORING_UID_TABLE" ]; then
        OT_COLUMNS="id name"
	COLUMN_FLAG="true"
      elif [ "$t" == "$MONITORING_META_TABLE" ]; then
	OT_COLUMNS="name"
      else
	OT_COLUMNS="t"
      fi
      for columnFamily in $OT_COLUMNS ; do
	echo "Creating CF $columnFamily for Table $t"
	maprcli table cf create -path $t -cfname $columnFamily -maxversions 1 -inmemory $COLUMN_FLAG -compression lzf -ttl 0 >> $LOGFILE 2>&1
	RC2=$?
	if [ $RC2 -ne 0 ]; then
	  echo "Create CF $columnFamily failed for table $t"
	  return $RC2
	fi
      done
    else
      echo "$t exists."
    fi
  done
}



# Try to create lock file - with 5 retries
i=0
while [[ $i -lt 30 ]]; do
  hadoop fs -mkdir $MONITORING_LOCK_DIR
  RC=$?
  if [ $RC -ne 0 ]; then
    #echo "Unable to create lock file $MONITORING_LOCK_DIR"
    sleep 2
  else
    break
  fi
  (( i++ ))
done

# Failed after retries - exit
if [[ $i -eq 30 ]]; then
  echo "Failed to create lock file $MONITORING_LOCK_DIR after $i attempts."
  exit 1 
fi
export MAPR_DAEMON=spyglass
createTSDB
RC1=$?

# Try to remove lock file - with 5 retries
i=0
while [[ $i -lt 30 ]]; do
  hadoop fs -rm -r $MONITORING_LOCK_DIR
  RC=$?
  if [ $RC -ne 0 ]; then
    #echo "Unable to remove lock file $MONITORING_LOCK_DIR"
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
  echo "Failed to remove lock file $MONITORING_LOCK_DIR after $i attempts. Please remove the lock file manually and run this script again"
  exit 1 
fi

echo "Complete!"

true

