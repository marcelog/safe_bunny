-module(safe_bunny_helper_mq).
-behavior(gen_server).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include_lib("amqp_client/include/amqp_client.hrl").
-include("safe_bunny.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-define(EXCHANGE_TEST, <<"safe_bunny_test">>).

-record(state, {
  channel = undefined:: pid(),
  connection = undefined:: pid(),
  messages_received = []:: [term()],
  notify_when = []:: [{binary(), pid()}]
}).
-type state():: #state{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([start/1, start_listening/2, stop/1]).
-export([exchange/0]).
-export([notify_when/3, queue/2, deliver_unsafe/2, deliver_safe/2, messages/1]).

%%% gen_server callbacks.
-export([
  init/1, terminate/2, code_change/3,
  handle_call/3, handle_cast/2, handle_info/2
]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start(binary()) -> {ok, pid()}|{error, term()}.
start(RoutingKey) ->
  gen_server:start(?MODULE, [RoutingKey, []], []).

-spec start_listening(binary(), [term()]) -> {ok, pid()}|{error, term()}.
start_listening(RoutingKey, Listeners) ->
  gen_server:start(?MODULE, [RoutingKey, Listeners], []).

-spec stop(pid()) -> ok.
stop(Server) ->
  gen_server:call(Server, {stop}).

-spec messages(pid()) -> [term()].
messages(Server) ->
  gen_server:call(Server, {messages}).

-spec exchange() -> binary().
exchange() ->
  ?EXCHANGE_TEST.

-spec queue(binary(), binary()) -> {pid(), reference()}.
queue(Key, Payload) ->
  safe_bunny:queue(exchange(), Key, Payload).

-spec deliver_unsafe(binary(), binary()) -> {pid(), reference()}.
deliver_unsafe(Key, Payload) ->
  safe_bunny:deliver_unsafe(exchange(), Key, Payload).

-spec deliver_safe(binary(), binary()) -> {pid(), reference()}.
deliver_safe(Key, Payload) ->
  safe_bunny:deliver_safe(exchange(), Key, Payload).

-spec notify_when(pid(), binary(), binary()) -> ok.
notify_when(Server, Payload, Pid) ->
  gen_server:call(Server, {notify_when, Payload, Pid}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% gen_server API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init([term()]) -> {ok, state()}.
init([RoutingKey, Listeners]) ->
  Config = ?SB_CFG:mq(),
  Get = fun
    ({s, X}) ->
      list_to_binary(proplists:get_value(X, Config));
    (X) ->
      proplists:get_value(X, Config) end,
  {ok, Connection} = amqp_connection:start(#amqp_params_network{
    username = Get({s, user}),
    password = Get({s, pass}),
    virtual_host = Get({s, vhost}),
    port = Get(port),
    host = Get(host)
  }),
  {ok, Channel} = amqp_connection:open_channel(Connection),
  true = erlang:link(Channel),
  #'exchange.declare_ok'{} = amqp_channel:call(
    Channel, #'exchange.declare'{
      exchange = exchange(),
      type = <<"direct">>,
      durable = false,
      auto_delete = true
    }
  ),
  #'queue.declare_ok'{queue = Queue} = amqp_channel:call(Channel, #'queue.declare'{
    durable = false,
    auto_delete = true  
  }),
  Binding = #'queue.bind'{
    queue = Queue,
    exchange = exchange(),
    routing_key = RoutingKey
  },
  #'queue.bind_ok'{} = amqp_channel:call(Channel, Binding),
  #'basic.consume_ok'{consumer_tag = _Tag} = amqp_channel:subscribe(
    Channel, #'basic.consume'{queue = Queue}, self()
  ),
  {ok, #state{channel = Channel, connection = Connection, notify_when = Listeners}}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(Msg, State) ->
  lager:error("Invalid cast: ~p", [Msg]),
  {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(#'basic.consume_ok'{}, State) ->
  {noreply, State};

handle_info(#'basic.cancel_ok'{}, State) ->
  {noreply, State};

handle_info(
  {#'basic.deliver'{delivery_tag = Tag}, #'amqp_msg'{payload = Content}},
  State
) ->
  lager:debug("Got message: ~p: ~p", [Tag, Content]),
  _ = [Pid ! {message, C} || {C, Pid} <- State#state.notify_when],
  amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag = Tag}),
  Messages = [Content|State#state.messages_received],
  {noreply, State#state{messages_received = Messages}};

handle_info(Msg, State) ->
  lager:error("Invalid msg: ~p", [Msg]),
  {noreply, State}.

-spec handle_call(
  term(), {pid(), reference()}, state()
) -> {reply, term() | {invalid_request, term()}, state()}.
handle_call({notify_when, Payload, Pid}, _From, State) ->
  NewNotifees = lists:keystore(Payload, 1, State#state.notify_when, {Payload, Pid}),
  {reply, ok, State#state{notify_when = NewNotifees}};

handle_call({messages}, _From, State=#state{messages_received = Messages}) ->
  {reply, lists:reverse(Messages), State};

handle_call({stop}, _From, State=#state{channel = Channel, connection = Connection}) ->
  amqp_channel:close(Channel),
  amqp_connection:close(Connection),
  {stop, normal, ok, State};

handle_call(Req, _From, State) ->
  lager:error("Invalid request: ~p", [Req]),
  {reply, invalid_request, State}.

-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

-spec code_change(string(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
