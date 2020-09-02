package net.opentsdb.tools;

import com.fasterxml.jackson.core.type.TypeReference;
import com.google.common.base.Strings;
import com.stumbleupon.async.Callback;
import com.stumbleupon.async.Deferred;
import com.stumbleupon.async.TimeoutException;
import net.opentsdb.core.*;
import net.opentsdb.tsd.BadRequestException;
import net.opentsdb.tsd.HttpJsonSerializer;
import net.opentsdb.tsd.PutDataPointRpc;
import net.opentsdb.uid.NoSuchUniqueName;
import net.opentsdb.utils.Config;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.consumer.internals.NoOpConsumerRebalanceListener;
import org.hbase.async.PleaseThrottleException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Properties;
import java.util.regex.Pattern;


/**
 * @author ntirupattur
 */
@SuppressWarnings("CheckStyle")
public class StreamsConsumer2 extends PutDataPointRpc implements Runnable {
    /**
     * Type ref for the histo pojo.
     */
    private static final TypeReference<ArrayList<HistogramPojo>> TYPE_REF = new TypeReference<ArrayList<HistogramPojo>>() {
    };
    /**
     * Type reference for incoming data points
     */
    private static final TypeReference<ArrayList<IncomingDataPoint>> TR_INCOMING = new TypeReference<ArrayList<IncomingDataPoint>>() {
    };
    private static final Pattern BUCKETS_PATTERN = Pattern.compile(".+\"buckets\":.+");
    private final Logger log = LoggerFactory.getLogger(StreamsConsumer2.class);
    private final String streamName;
    private final String consumerGroup;
    private final TSDB tsdb;
    private final long consumerMemory;
    private final long autoCommitInterval;
    private final HttpJsonSerializer serializer = new HttpJsonSerializer();
    private KafkaConsumer<String, String> consumer;
    private StreamsPurger purger;

    public StreamsConsumer2(TSDB tsdb, String streamName, String consumerGroup, Config config, long consumerMemory, long autoCommitInterval) {
        super(config);
        this.tsdb = tsdb;
        this.streamName = streamName;
        this.consumerGroup = consumerGroup;
        this.consumerMemory = consumerMemory;
        this.autoCommitInterval = autoCommitInterval;
        this.purger = new StreamsPurger(tsdb, config, streamName);

        log.info(String.format("Constructed StreamsConsumer2; %s", this));
    }

    Runnable getPurger() {
      return purger;
    }

    private void writeToTSDB(final String message, final long timeStamp) {
        String errmsg = null;
        try {
            // TODO: The pattern should probably be compiled once in a field variable since it is an expensive operation
            // matches tries to match the whole string, not just a piece of it
            // if the json contains a "buckets": key, then it contains histograms
            if (BUCKETS_PATTERN.matcher(message).matches()) {
                List<HistogramPojo> dps = HttpJsonSerializer.parseUtil(message, HistogramPojo.class, TYPE_REF);
                log.debug(String.format("Found %d histogram datapoints", dps.size()));
                processDataPoint(dps, timeStamp);
            }
            else {
                List<IncomingDataPoint> dps = HttpJsonSerializer.parseUtil(message, IncomingDataPoint.class, TR_INCOMING);
                log.debug(String.format("Found %d datapoints", dps.size()));
                processDataPoint(dps, timeStamp);
            }
        }
        catch (NumberFormatException x) {
            errmsg = String.format("put: invalid value: %s\n", x.getMessage());
        }
        catch (IllegalArgumentException x) {
            errmsg = String.format("put: illegal argument: %s\n", x.getMessage());
        }

        if (errmsg != null) {
            log.error(String.format("Failed to write metrics to TSDB with error: %s metrics %s", errmsg, message));
        }
    }

    private <T extends IncomingDataPoint> void processDataPoint(final List<T> dps, final long timeStamp) {
        for (final IncomingDataPoint dp : dps) {
            final DataPointType type;

            if (dp instanceof HistogramPojo) {
                type = DataPointType.HISTOGRAM;
            }
            else {
                type = DataPointType.PUT;
            }

            final class PutErrback implements Callback<Boolean, Exception> {
                @Override
                public Boolean call(final Exception arg) {
                    // we handle the storage exceptions here so as to avoid creating yet
                    // another callback object on every data point.
                    log.info(String.format("Failed to process data point: %s", dp));
                    handleStorageException(tsdb, dp, arg);
                    return false;
                }

                public String toString() {
                    return String.format("Put exception with datapoint: %s", dp);
                }
            }

            try {
                final Deferred<Object> deferred;
                log.debug(String.format("Found datapoint: %s", dp));
                if (type == DataPointType.HISTOGRAM) {
                    final HistogramPojo pojo = (HistogramPojo) dp;
                    // validation and/or conversion before storage of histograms by decoding then re-encoding.
                    final Histogram hdp;
                    if (Strings.isNullOrEmpty(dp.getValue())) {
                        hdp = pojo.toSimpleHistogram(tsdb);
                    }
                    else {
                        hdp = tsdb.histogramManager().decode(pojo.getId(), pojo.getBytes(), false);
                    }
                    deferred = tsdb.addHistogramPoint(pojo.getMetric(), timeStamp, tsdb.histogramManager().encode(hdp.getId(), hdp, true), pojo.getTags()).addErrback(new PutErrback());
                }
                else if (Tags.looksLikeInteger(dp.getValue())) {
                    deferred = tsdb.addPoint(dp.getMetric(), timeStamp, Tags.parseLong(dp.getValue()), dp.getTags()).addErrback(new PutErrback());
                }
                else {
                    deferred = tsdb.addPoint(dp.getMetric(), timeStamp, Tags.fitsInFloat(dp.getValue()) ? Float.parseFloat(dp.getValue()) : Double.parseDouble(dp.getValue()), dp.getTags()).addErrback(new PutErrback());
                }
            }
            catch (NumberFormatException x) {
                log.error(String.format("Unable to parse value to a number: %s", dp));
            }
            catch (IllegalArgumentException iae) {
                log.error(String.format("%s: %s", iae.getMessage(), dp));
            }
            catch (NoSuchUniqueName nsu) {
                log.error(String.format("Unknown metric: %s", dp));
            }
            catch (PleaseThrottleException x) {
                handleStorageException(tsdb, dp, x);
            }
            catch (TimeoutException tex) {
                handleStorageException(tsdb, dp, tex);
            }
            catch (RuntimeException e) {
                log.error(String.format("Unexpected exception: %s", dp));
            }
        }
    }

    @SuppressWarnings({"checkstyle:IllegalCatchExtended", "InfiniteLoopStatement"})
    @Override
    public void run() {
        final String threadName = String.format("StreamsConsumer2-%s", consumerGroup);
        final Properties props = new Properties();

        log.info(String.format("Running StreamsConsumer2; %s", this));
        Thread.currentThread().setName(threadName);

        props.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        props.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        props.put("group.id", "StreamsConsumer2/" + consumerGroup);
        props.put("streams.consumer.buffer.memory", consumerMemory); // Defaul to 4 MB
        props.put("auto.offset.reset", "earliest");
        props.put("auto.commit.interval.ms", autoCommitInterval);

        while (true) {
            if (consumer == null) {
                try {
                    log.info(String.format("Starting Kafka consumer on thread: %s", threadName));

                    consumer = new KafkaConsumer<String, String>(props);
                    // Subscribe to all topics in this stream
                    consumer.subscribe(Pattern.compile(streamName + ":.+"), new NoOpConsumerRebalanceListener());
                    long pollTimeOut = 10000;

                    log.info(String.format("Started Kafka consumer on thread: %s", threadName));

                    while (true) {
                        log.debug(String.format("Looking for records on the stream to write on thread: %s", threadName));
                        // Request unread messages from the topic.
                        final ConsumerRecords<String, String> consumerRecords = consumer.poll(pollTimeOut);
                        final Iterator<ConsumerRecord<String, String>> iterator = consumerRecords.iterator();

                        if (iterator.hasNext()) {
                            while (iterator.hasNext()) {
                                ConsumerRecord<String, String> record = iterator.next();
                                log.debug(String.format("Consumed Record Value: %s on thread: %s", record.value(), threadName));
                                try {
                                    writeToTSDB(record.value().trim(), record.timestamp());
                                }
                                catch (BadRequestException be) {
                                    log.error(String.format("Unable to parse metric: %s failed with exception: %s on thread: %s", record.value(), be, threadName));
                                }
                            }
                        }
                    }
                }
                catch (Exception e) {
                    log.error(String.format("Thread for topic: %s failed", consumerGroup), e);
                }
                finally {
                    log.info(String.format("Closing Kafka consumer on thread: %s...", threadName));
                    consumer.close();
                    consumer = null;
                    log.info(String.format("Closed Kafka consumer on thread: %s", threadName));
                }
            }
            else {
                log.debug(String.format("Not starting thread for %s; Already started", threadName));
            }
        }
    }

    @Override
    public String toString() {
        return String.format("StreamName: %s; ConsumerGroup: %s; ConsumerMemory: %d; AutoCommitInterval: %d",
                streamName, consumerGroup, consumerMemory, autoCommitInterval);
    }

    /**
     * The type of data point we're writing.
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
}
