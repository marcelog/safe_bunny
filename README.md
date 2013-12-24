# About

RabbitMQ delivery with local queuing on failure. It's a bit of boiler plate code
that can be useful in lots of projects, and it's basically a small wrapper around
the publish function of the [rabbitmq erlang client](http://www.rabbitmq.com/erlang-client-user-guide.html).

Let's say you have rabbitmq as your main event/commands bus for your project. Most
of the time, rabbitmq will be there (available), but sometimes, you might experience
connectivity issues, or maybe the server is down, or something else went wrong, 
and you want to be as sure as possible that you will be able to send some important
messages, even if that means that they will *eventually* be sent, and not right away.

safe_bunny gives you a couple of queue alternatives to use when rabbitmq is
not available for whatever reason, while still allowing you to **fire-and-forget**
messages, and it will handle this automagically for you (or at least do its best
effort).

safe_bunny includes the needed producers and consumers for the fallback queues.

## Jenkins Job
Be sure to checkout the [jenkins job page](http://ci.marcelog.name/job/safe_bunny/)
to see metrics, tests, and documentation.

## Example

 - safe_bunny is configured with queues mysql, redis, file, ets (in that order).
 - A publish fails with a **NO_ROUTE** error.
 - The first fallback queue is tried (in this case, mysql).
 - If the fallback queue fails or is not available, the next one is tried, until
 one succeeds or no more queues are available.
 - You get to choose which queues will be available and the order of preference.

## Disclaimer
Nothing is safe. But this might give you a safer solution when using rabbitmq
to send messages to your workers (meaning that will try to make the best possible
effort to ensure an eventual delivery).

# How it works
Uses [worker_pool](https://github.com/tigertext/worker_pool) to create a pool
of connections to rabbitmq, all channels use [confirms](http://www.rabbitmq.com/confirms.html), so we are *pretty sure* that a given message could or could not be published.

For *safe* deliveries, the **mandatory** flag is set in the published messages, so
on failure these messages can be saved in one of the fallback queues for
retrying the operation later.

## Delivery "modes"
For delivering messages, you can choose between 3 different options.

### Direct to MQ, no local queuing on failure.
Use **safe_bunny:deliver_unsafe/3**. This will try to publish a message to the
given exchange and routing key, and will not try to queue the message on failure.

### Direct to MQ, local queueing on failure.
Use **safe_bunny:deliver_safe/3**. Like the above, but will queue the message
in the fallback queues on failure. Fallback queues are tryed in order, according
to the **producers** option of the safe_bunny application.

### Local queuing only. Consumers will try to send the messages to the MQ.
"Safest" option (because you queue first). Use **safe_bunny:queue/3**. One of
the queue consumers should pick the new message and try to publish it via rabbitmq.

## Available Queuing backends

 * mysql
 * redis
 * file
 * ets

## Concurrency

[Duomark's concurrency tools](https://github.com/duomark/dk_cxy) is used to
impose concurrency limits on the number of processes spawned for deliveries (either
to local queues and rabbitmq). Each delivery will be handled by a separate process
that can be monitored until the limit is reached. Everything will be done 'inline'
(i.e: the caller's process space) when exceeded.

## Configuring it

Check out the [example configuration file](https://github.com/marcelog/safe_bunny/blob/master/priv/example.config).

## Running it

    application:start(safe_bunny).
