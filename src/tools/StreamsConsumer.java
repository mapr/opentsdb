/**
 *
 */
package net.opentsdb.tools;

import com.stumbleupon.async.Callback;
import com.stumbleupon.async.Deferred;
import net.opentsdb.core.TSDB;
import net.opentsdb.tsd.PutDataPointRpc;
import net.opentsdb.uid.NoSuchUniqueName;
import net.opentsdb.utils.Config;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.consumer.internals.NoOpConsumerRebalanceListener;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Arrays;
import java.util.Iterator;
import java.util.Properties;
import java.util.regex.Pattern;


/**
 * @author ntirupattur
 *
 */
public class StreamsConsumer extends PutDataPointRpc implements Runnable {
    private final Logger log = LoggerFactory.getLogger(StreamsConsumer.class);

    private String streamName;
    private String consumerGroup;
    private TSDB tsdb;
    private long consumerMemory;
    private long autoCommitInterval;
    private KafkaConsumer<String, String> consumer;
    private StreamsPurger purger;

    public StreamsConsumer(TSDB tsdb, String streamName, String consumerGroup, Config config, long consumerMemory, long autoCommitInterval) {
        super(config);
        this.tsdb = tsdb;
        this.streamName = streamName;
        this.consumerGroup = consumerGroup;
        this.consumerMemory = consumerMemory;
        this.autoCommitInterval = autoCommitInterval;
        this.purger = new StreamsPurger(tsdb, streamName);

        log.info(String.format("Constructed StreamsConsumer; %s", toString()));
    }

    Runnable getPurger() {
      return purger;
    }

    private Deferred<Object> writeToTSDB(final String[] metricTokens) {
        String errmsg = null;
        try {
            final class PutErrback implements Callback<Exception, Exception> {
                @Override
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
            return importDataPoint(tsdb, metricTokens).addErrback(new PutErrback());
        }
        catch (NumberFormatException x) {
            errmsg = "put: invalid value: " + x.getMessage() + '\n';
        }
        catch (IllegalArgumentException x) {
            errmsg = "put: illegal argument: " + x.getMessage() + '\n';
        }
        catch (NoSuchUniqueName x) {
            errmsg = "put: unknown metric: " + x.getMessage() + '\n';
        }
        if (errmsg != null) {
            log.error("Failed to write metrics to TSDB with error: " + errmsg + " metrics " + Arrays.toString(metricTokens));
        }
        return Deferred.fromResult(null);
    }

    @Override
    public void run() {
        Thread.currentThread().setName("StreamsConsumer-" + consumerGroup);
        Properties props = new Properties();
        props.put("key.deserializer",
                "org.apache.kafka.common.serialization.StringDeserializer");
        props.put("value.deserializer",
                "org.apache.kafka.common.serialization.StringDeserializer");
        props.put("group.id", "StreamsConsumer/" + consumerGroup);
        props.put("streams.consumer.buffer.memory", consumerMemory); // Defaul to 4 MB
        props.put("auto.offset.reset", "earliest");
        props.put("auto.commit.interval.ms", autoCommitInterval);

        while (true) {
            if (consumer == null) {
                try {
                    log.info(String.format("Starting Thread: StreamsConsumer/%s", consumerGroup));

                    consumer = new KafkaConsumer<String, String>(props);
                    // Subscribe to all topics in this stream
                    consumer.subscribe(Pattern.compile(streamName + ":.+"), new NoOpConsumerRebalanceListener());
                    long pollTimeOut = 10000;
                    log.info(String.format("Started Thread: StreamsConsumer/%s", consumerGroup));

                    while (true) {
                        // Request unread messages from the topic.
                        ConsumerRecords<String, String> consumerRecords = consumer.poll(pollTimeOut);
                        Iterator<ConsumerRecord<String, String>> iterator = consumerRecords.iterator();
                        if (iterator.hasNext()) {
                            while (iterator.hasNext()) {
                                ConsumerRecord<String, String> record = iterator.next();
                                //log.info(" Consumed Record Key: " + record.value());
                                //log.info(" Consumed Record Value: " + record.value());
                                String[] metricTokens = record.value().trim().replaceAll(":", "").split(" ");
                                Deferred<Object> result = writeToTSDB(metricTokens);
                                record = null;
                                metricTokens = null;
                            }
                        }
                        consumerRecords = null;
                        iterator = null;
                    }
                }
                catch (Exception e) {
                    log.error(String.format("Thread for topic: %s failed with exception: %s", consumerGroup, e));
                }
                finally {
                    log.info(String.format("Closing this thread: %s", consumerGroup));
                    consumer.close();
                    consumer = null;
                }
            }
            else {
                log.debug(String.format("Not starting thread for StreamsConsumer/%s; Already started", consumerGroup));
            }
        }
    }

    @Override
    public String toString() {
        return String.format("StreamName: %s; ConsumerGroup: %s; ConsumerMemory: %d; AutoCommitInterval: %d",
                streamName, consumerGroup, consumerMemory, autoCommitInterval);
    }
}
