# About
RabbitMQ delivery with local queuing on failure. It's a bit of boiler plate code
that can be useful in lots of projects.

Let's say you have rabbitmq as your main event/commands bus for your project. Most
of the time, rabbitmq will be there (available), but sometimes, you might experience
connectivity issues, or maybe the server is down, or something else went wrong, 
and you want to be as sure as possible that you will be able to at least, send
these tasks in the future. 

safe_bunny will give you a couple of queue alternatives to use when rabbitmq is
not available for whatever reason.

## Disclaimer
Nothing is safe. But this might give you a safer solution when using rabbitmq
to send messages to your workers.

# How it works
Check out the [example configuration file](https://github.com/marcelog/safe_bunny/blob/master/priv/example.config).

## Delivery "modes"

### Direct to MQ, no local queuing on failure.
Use **safe_bunny:deliver_unsafe/3**. This will try to publish a message to the
given exchange and routing key, and will not try to queue the message on failure.

### Direct to MQ, local queueing on failure.
Use **safe_bunny:deliver_save/3**. It will try to publish a message, and queue
to one of the fallback queues on failure.

### Local queuing only. Consumers will try to send the messages to the MQ.
Use **safe_bunny:queue/3**. One of the queue consumers should pick the new
message and try to publish it via rabbitmq.

## Available Queuing backends

 * mysql
 * redis
 * file
 * ets

## Concurrency

