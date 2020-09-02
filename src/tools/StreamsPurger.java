package net.opentsdb.tools;

import java.io.BufferedReader;
import java.io.InputStreamReader;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Properties;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.regex.Pattern;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.clients.consumer.internals.NoOpConsumerRebalanceListener;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.PartitionInfo;

import com.stumbleupon.async.Callback;
import com.stumbleupon.async.Deferred;

import net.opentsdb.uid.NoSuchUniqueName;
import net.opentsdb.utils.Config;
import net.opentsdb.tsd.PutDataPointRpc;
import net.opentsdb.core.TSDB;


/**
 * @author sergeiv
 *
 */
public class StreamsPurger implements Runnable {

  private String streamName;
  private String consumerGroup;
  private TSDB tsdb;
  private KafkaConsumer<String,String> consumer;
  private Logger log;
  private Properties props;
  private int initialSleepInterval;
  private int sleepBetweenPurges;
  private final int defaultSleepBetweenPurges = 1 * 24 * 60 * 60 * 1000;
  private final int defaultInitialSleep = 12345;

  public StreamsPurger(TSDB tsdb, Config config, String streamName) {
    this.tsdb = tsdb;
    this.streamName = streamName;
    this.log = LoggerFactory.getLogger(StreamsPurger.class);

    this.props = new Properties();
    this.props.put("key.deserializer",
        "org.apache.kafka.common.serialization.StringDeserializer");
    this.props.put("value.deserializer",
        "org.apache.kafka.common.serialization.StringDeserializer");
    this.props.put("group.id", "HARDCODED_PURGER_GROUP_ID");
    this.props.put("enable.auto.commit", "false");
    this.props.put("auto.offset.reset", "earliest");

    initialSleepInterval = defaultInitialSleep;
    try {
      initialSleepInterval = Integer.parseInt(config.getString("tsd.streams.initial_sleep_interval"));
    } catch (Throwable ignored) {}

    sleepBetweenPurges = defaultSleepBetweenPurges;
    try {
      sleepBetweenPurges = Integer.parseInt(config.getString("tsd.streams.sleep_interval_between_purges"));
    } catch (Throwable ignored) {}
  }


  ///
  /// On a healthy running system where the consumers are keeping up with
  /// production of metrics, we are never touching records that can be
  /// purged away due to TTL, as consumers are touching records that are
  /// temporally (therefore physically, due to key design). Since this never
  /// happens, tablets that contain those records won't ever be brought into
  /// tablet caches on noded, therefore nooone will notice that they have TTLed
  /// away. If metrics production rate is more then one tablet per (TTL plus
  /// tablet cache timeouts) this will cause an entire tablet with TTLed
  /// to be dropped from cache, to be never touched, therefore they will
  /// just sit there and use space forever until someone kicks off a new
  /// consumer or purges the stream.
  ///
  /// see SPYG-994, INFO-1492
  ///
  /// this nasty behavior is a design limitation of our system. We don't have
  /// a catalogue of streams, and streams themselves are nothing more then DB
  /// tables to MFS (logic is client-side)

  /// We document the solution to be like run `maprcli stream purge`, so
  /// let's do that. Also, if we create a new streams consumer and consume a
  /// message, this necessarily makes us to search for the oldest unexpired
  /// message, causing nice side effects: tablets with expired messages get
  /// loaded

  /// pokes a stream by creating a consumer and polling once
  private void poke() {
    try {
      // just poke the oldest messages, once
      consumer = new KafkaConsumer<String, String>(props);
      consumer.subscribe(Pattern.compile(streamName + ":.+"), new NoOpConsumerRebalanceListener());
      ConsumerRecords<String, String> consumerRecords = consumer.poll(10000);
    } catch (Throwable e) {
      log.error("Thread for purger group failed with Throwable: ", e);
    }
    finally {
      log.info("Closing the purger group");
      consumer.unsubscribe();
      consumer.close();
    }
  }

  private void purge() {
    try {
      Runtime rt = Runtime.getRuntime();
      Process proc = rt.exec("maprcli stream purge -path " + this.streamName);
      BufferedReader br = new BufferedReader(new InputStreamReader(proc.getErrorStream()));
      String line = null;
      while ((line = br.readLine()) != null) {
        log.info(line);
      }
      int retval = proc.waitFor();
      log.info("maprcli stream purge returned [{}]", retval);

    } catch (Throwable e) {
      log.error("maprcli stream purge -path " + this.streamName + " failed with Throwable: ", e);
    }
  }

  @Override
  public void run() {


    if (initialSleepInterval != defaultInitialSleep) {
      log.info("Initial sleep interval for Purger is [{}]", initialSleepInterval);
    }
    // delay before the first purge and poke:
    try {
      Thread.sleep(initialSleepInterval);
    } catch (Throwable e) {
      log.error("Thread::sleep() failed with Throwable: ", e);
    }

    for (;;) {
      purge();
      poke();
      // we normally run purger once a day
      if (sleepBetweenPurges != defaultSleepBetweenPurges) {
        log.info("Next purge in {} seconds ({} days)", sleepBetweenPurges / 1000, sleepBetweenPurges / defaultSleepBetweenPurges);
      }

      try {
        Thread.sleep(sleepBetweenPurges);
      } catch (Throwable e) {
        log.error("Thread::sleep() failed with Throwable: ", e);
      }
    }
  }
}
