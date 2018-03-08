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

import net.opentsdb.uid.NoSuchUniqueName;
import net.opentsdb.tsd.PutDataPointRpc;
import net.opentsdb.core.TSDB;
import net.opentsdb.utils.Config;


/**
 * @author ntirupattur
 *
 */
public class StreamsConsumer extends PutDataPointRpc implements Runnable {

  private String streamName;
  private String consumerGroup;
  private TSDB tsdb;
  private long consumerMemory;
  private long autoCommitInterval;
  private KafkaConsumer<String,String> consumer;
  private Logger log;

  public StreamsConsumer(TSDB tsdb, String streamName, String topicName, Config config, long consumerMemory, long autoCommitInterval) {
    super(config);
    this.tsdb = tsdb;
    this.streamName = streamName;
    this.consumerGroup = topicName;
    this.consumerMemory = consumerMemory;
    this.autoCommitInterval = autoCommitInterval;
    this.log = LoggerFactory.getLogger(StreamsConsumer.class);
  }

  private Deferred<Object> writeToTSDB(final StringBuffer message) {
    String errmsg = null;
    final String[] metricTokens = message.toString().split(" ");
    try {
      final class PutErrback implements Callback<Exception, Exception> {
        public Exception call(final Exception arg) {
          // we handle the storage exceptions here so as to avoid creating yet
          // another callback object on every data point.
          PutDataPointRpc.handleStorageException(tsdb, getDataPointFromString(tsdb, metricTokens), arg);
          return null;
        }
        public String toString() {
          return "report error to caller";
        }
      }
      return importDataPoint(this.tsdb, metricTokens).addErrback(new PutErrback());
    } catch (NumberFormatException x) {
      errmsg = "put: invalid value: " + x.getMessage() + '\n';
    } catch (IllegalArgumentException x) {
      errmsg = "put: illegal argument: " + x.getMessage() + '\n';
    } catch (NoSuchUniqueName x) {
      errmsg = "put: unknown metric: " + x.getMessage() + '\n';
    }
    if (errmsg != null) {
      log.error("Failed to write metrics to TSDB with error: "+errmsg+" metrics "+Arrays.toString(metricTokens));
    }
    return Deferred.fromResult(null);
  }

  @Override
  public void run() {
    Thread.currentThread().setName("StreamsConsumer-"+this.consumerGroup);
    Properties props = new Properties();
    props.put("key.deserializer",
        "org.apache.kafka.common.serialization.StringDeserializer");
    props.put("value.deserializer",
        "org.apache.kafka.common.serialization.StringDeserializer");
    props.put("group.id", this.consumerGroup);
    props.put("streams.consumer.buffer.memory", consumerMemory); // Defaul to 4 MB
    props.put("auto.offset.reset", "earliest");
    props.put("auto.commit.interval.ms", autoCommitInterval);
    while (true) {
      if (consumer == null) {
		    try {
		      this.consumer = new KafkaConsumer<String, String>(props);
		      // Subscribe to all topics in this stream
		      this.consumer.subscribe(Pattern.compile(this.streamName+":.+"), new NoOpConsumerRebalanceListener());
		      //this.consumer.subscribe(Arrays.asList(this.streamName+":"+this.topicName));
		      long pollTimeOut = 10000;
		      log.info("Started Thread: "+this.consumerGroup);
		      while (true) {
		        // Request unread messages from the topic.
		        ConsumerRecords<String, String> consumerRecords = consumer.poll(pollTimeOut);
		        Iterator<ConsumerRecord<String, String>> iterator = consumerRecords.iterator();
		        if (iterator.hasNext()) {
		          while (iterator.hasNext()) {
		            ConsumerRecord<String, String> record = iterator.next();
		            // Iterate through returned records, extract the value
		            // of each message, and print the value to standard output.
		            //log.info(" Consumed Record Key: " + record.value());
		            //log.info(" Consumed Record Value: " + record.value());
		            //log.info("Consumer Record: "+record.toString());
		            String[] words = record.value().toString().trim().replaceAll(":","").split(" ");
		            //Metric metric = mapper.readValue(record.value(), Metric.class);
		            //String[] metricTokens = new String[] { "put", "streams."+metric.getPlugin()+"."+metric.getType(), String.valueOf(metric.getTimeStamp()), 
		            //                                        String.valueOf(metric.getValues().get(0)),"fqdn="+metric.getHostName()
		            //                                     };
		            StringBuffer metricTokens = new StringBuffer();
		            metricTokens.append("put ");
		            metricTokens.append(words[0]+" ");
		            metricTokens.append(String.valueOf(record.timestamp())+" ");
		            for (int i=1;i<words.length;i++) { metricTokens.append(words[i]+" "); }
		            Deferred<Object> result = writeToTSDB(metricTokens);
		            record = null;
		            words = null;
		            metricTokens = null;
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
