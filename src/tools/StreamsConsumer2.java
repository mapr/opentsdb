/**
 * 
 */
package net.opentsdb.tools;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Properties;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.clients.consumer.internals.NoOpConsumerRebalanceListener;
import org.apache.kafka.common.TopicPartition;

import com.stumbleupon.async.Callback;
import com.stumbleupon.async.Deferred;
import com.google.common.base.Strings;
import org.hbase.async.PleaseThrottleException;
import com.stumbleupon.async.TimeoutException;
import net.opentsdb.tsd.BadRequestException;

import net.opentsdb.uid.NoSuchUniqueName;
import net.opentsdb.tsd.PutDataPointRpc;
import net.opentsdb.core.TSDB;
import net.opentsdb.utils.Config;
import net.opentsdb.core.Histogram;
import net.opentsdb.core.HistogramPojo;
import net.opentsdb.core.IncomingDataPoint;
import net.opentsdb.core.TSDB;
import net.opentsdb.core.Tags;
import net.opentsdb.tsd.HttpJsonSerializer;
import com.fasterxml.jackson.core.type.TypeReference;

/**
 * @author ntirupattur
 *
 */
public class StreamsConsumer2 extends PutDataPointRpc implements Runnable {

  private String streamName;
  private String consumerGroup;
  private TSDB tsdb;
  private long consumerMemory;
  private long autoCommitInterval;
  private KafkaConsumer<String,String> consumer;
  private HttpJsonSerializer serializer = new HttpJsonSerializer();
  private Logger log =  LoggerFactory.getLogger(StreamsConsumer2.class);

  /** The type of data point we're writing.
   */
  private enum DataPointType {
    PUT("put"),
    HISTOGRAM("histogram");

    private final String name;
    DataPointType(final String name) {
      this.name = name;
    }

    @Override
    public String toString() {
      return name;
    }
  }

  /** Type ref for the histo pojo. */
  private static final TypeReference<ArrayList<HistogramPojo>> TYPE_REF = new TypeReference<ArrayList<HistogramPojo>>() {};

  /** Type reference for incoming data points */
  private static TypeReference<ArrayList<IncomingDataPoint>> TR_INCOMING = new TypeReference<ArrayList<IncomingDataPoint>>() {};

  public StreamsConsumer2(TSDB tsdb, String streamName, String consumerGroup, Config config, long consumerMemory, long autoCommitInterval) {
    super(config);
    this.tsdb = tsdb;
    this.streamName = streamName;
    this.consumerGroup = consumerGroup;
    this.consumerMemory = consumerMemory;
    this.autoCommitInterval = autoCommitInterval;
  }

  private void writeToTSDB(final String message, final long timeStamp) {
    String errmsg = null;
    try {

      if (message.matches(".+\\.latency")) {
        List<HistogramPojo> dps = HttpJsonSerializer.parseUtil(message, HistogramPojo.class, TYPE_REF);
        log.debug("Found "+dps.size()+" histogram datapoints");
        processDataPoint(dps, timeStamp);
      } else {
        List<IncomingDataPoint> dps = HttpJsonSerializer.parseUtil(message, IncomingDataPoint.class, TR_INCOMING);
        log.debug("Found "+dps.size()+" datapoints");
        processDataPoint(dps, timeStamp);
      }
    } catch (NumberFormatException x) {
      errmsg = "put: invalid value: " + x.getMessage() + '\n';
    } catch (IllegalArgumentException x) {
      errmsg = "put: illegal argument: " + x.getMessage() + '\n';
    }

    if (errmsg != null) {
      log.error("Failed to write metrics to TSDB with error: "+errmsg+" metrics "+message);
    }
  }

  private <T extends IncomingDataPoint> void processDataPoint( final List<T> dps, final long timeStamp) {
    for (final IncomingDataPoint dp : dps) {
      final DataPointType type;
      if (dp instanceof HistogramPojo) {
        type = DataPointType.HISTOGRAM;
      } else {
        type = DataPointType.PUT;
      }

      /**
       * Error back callback to handle storage failures
       */
      final class PutErrback implements Callback<Boolean, Exception> {
        public Boolean call(final Exception arg) {
          // we handle the storage exceptions here so as to avoid creating yet
          // another callback object on every data point.
          log.info ("Failed to process data point: "+dp.toString());
          handleStorageException(tsdb, dp, arg);
          return false;
        }

        public String toString() {
          return "Put exception";
        }
      }

      try {
        final Deferred<Object> deferred;
        log.debug("Found datapoint: "+dp.toString());
        if (type == DataPointType.HISTOGRAM) {
          final HistogramPojo pojo = (HistogramPojo) dp;
          // validation and/or conversion before storage of histograms by decoding then re-encoding.
          final Histogram hdp;
          if (Strings.isNullOrEmpty(dp.getValue())) {
            hdp = pojo.toSimpleHistogram(tsdb);
          } else {
            hdp = tsdb.histogramManager().decode(pojo.getId(), pojo.getBytes(), false);
          }
          deferred = tsdb.addHistogramPoint(pojo.getMetric(), timeStamp, tsdb.histogramManager().encode(hdp.getId(), hdp, true), pojo.getTags()).addErrback(new PutErrback());
        } else if (Tags.looksLikeInteger(dp.getValue())) {
          deferred = tsdb.addPoint(dp.getMetric(), timeStamp, Tags.parseLong(dp.getValue()), dp.getTags()).addErrback(new PutErrback());
        } else {
          deferred = tsdb.addPoint(dp.getMetric(), timeStamp, (Tags.fitsInFloat(dp.getValue()) ? Float.parseFloat(dp.getValue()) : Double.parseDouble(dp.getValue())), dp.getTags()).addErrback(new PutErrback());
        }
      } catch (NumberFormatException x) {
        log.error("Unable to parse value to a number: " + dp);
      } catch (IllegalArgumentException iae) {
        log.error(iae.getMessage() + ": " + dp);
      } catch (NoSuchUniqueName nsu) {
        log.error("Unknown metric: " + dp);
      } catch (PleaseThrottleException x) {
        handleStorageException(tsdb, dp, x);
      } catch (TimeoutException tex) {
        handleStorageException(tsdb, dp, tex);
      } catch (RuntimeException e) {
        log.error("Unexpected exception: " + dp);
      }
    }
  }

  @Override
  public void run() {
    Thread.currentThread().setName("StreamsConsumer2-"+this.consumerGroup);
    Properties props = new Properties();
    props.put("key.deserializer",
        "org.apache.kafka.common.serialization.StringDeserializer");
    props.put("value.deserializer",
        "org.apache.kafka.common.serialization.StringDeserializer");
    props.put("group.id", "StreamsConsumer2/"+this.consumerGroup);
    props.put("streams.consumer.buffer.memory", consumerMemory); // Defaul to 4 MB
    props.put("auto.offset.reset", "earliest");
    props.put("auto.commit.interval.ms", autoCommitInterval);
    while (true) {
      if (consumer == null) {
		    try {
		      this.consumer = new KafkaConsumer<String, String>(props);
		      // Subscribe to all topics in this stream
		      this.consumer.subscribe(Pattern.compile(this.streamName+":.+"), new NoOpConsumerRebalanceListener());
		      long pollTimeOut = 10000;
		      log.info("Started Thread: "+"StreamConsumer2/"+this.consumerGroup);
		      while (true) {
		        // Request unread messages from the topic.
		        ConsumerRecords<String, String> consumerRecords = consumer.poll(pollTimeOut);
		        Iterator<ConsumerRecord<String, String>> iterator = consumerRecords.iterator();
		        if (iterator.hasNext()) {
		          while (iterator.hasNext()) {
                            ConsumerRecord<String, String> record = iterator.next();
		            log.debug(" Consumed Record Value: " + record.value());
		            try {
                              writeToTSDB(record.value().trim(), record.timestamp());
		            } catch (BadRequestException be) {
                              log.error("Unable to parse metric: "+record.value()+" failed with exception: "+be);
                            }
		            record = null;
		          }
		        }
		        consumerRecords = null;
		        iterator = null;
		      }
		    } catch (Exception e) {
		      log.error("Thread for topic: "+this.consumerGroup+" failed with exception: "+e);
		    }
		    finally {
		      log.info("Closing this thread: "+this.consumerGroup);
		      consumer.close();
		      consumer = null;
		    }
      }
    }
  }
}
