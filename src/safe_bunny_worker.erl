%%% @doc MQ worker.
%%%
%%% Copyright 2012 Marcelo Gornstein &lt;marcelog@@gmail.com&gt;
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% @end
%%% @copyright Marcelo Gornstein <marcelog@gmail.com>
%%% @author Marcelo Gornstein <marcelog@gmail.com>
%%%
-module(safe_bunny_worker).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include_lib("amqp_client/include/amqp_client.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {
  channel = undefined:: undefined|pid(),
  channel_ref = undefined:: undefined|reference(),
  spawned_tasks = []:: [{pid(), reference()}],
  config = []:: proplists:proplist(),
  available = false:: boolean()
}).
-type state():: #state{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([deliver/4]).

%%% gen_server/worker_pool callbacks.
-export([
  init/1, terminate/2, code_change/3,
  handle_call/3, handle_cast/2, handle_info/2
]).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Safe implies mandatory, and confirmation required from the mq.
-spec deliver(boolean(), binary(), binary(), binary()) -> ok|term().
deliver(Safe, Exchange, Key, Payload) ->
  wpool:call(?MODULE, {deliver, {Safe, Exchange, Key, Payload}}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% gen_server API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(proplists:proplist()) -> {ok, state()}.
init(Config) ->
  erlang:send_after(0, self(), connect),
  {ok, #state{config = Config}}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(Msg, State) ->
  lager:error("Invalid cast: ~p", [Msg]),
  {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(connect, State) ->
  Connect = fun() ->
    case connect(State#state.config) of
      {ok, Pid} -> Pid;
      Error -> lager:alert("MQ NOT available: ~p", [Error]), not_available
    end
  end,
  Channel = case State#state.channel of
    Pid when is_pid(Pid) -> case is_process_alive(Pid) of
      true -> Pid;
      false -> Connect()
    end;
    _ -> Connect()
  end,
  ChannelRef = case Channel of
    _ when is_pid(Channel) -> erlang:monitor(process, Channel);
    _ -> erlang:send_after(
      proplists:get_value(reconnect_timeout, State#state.config), self(), connect
    ),
    undefined
  end,
  Available = is_pid(Channel) andalso ChannelRef =/= undefined,
  {noreply, State#state{
    channel = Channel,
    channel_ref = ChannelRef,
    available = Available
  }};

handle_info(
  {'DOWN', MQRef, process, MQPid, Reason},
  State=#state{channel = MQPid, channel_ref = MQRef}
) ->
  lager:warning("MQ channel is down: ~p", [Reason]),
  erlang:send_after(0, self(), connect),
  {noreply, State#state{
    channel = undefined,
    channel_ref = undefined,
    available = false
  }};

%% @doc If this one is reached, we were not expecting this ack (an unsafe
%% delivery to an acked queue probably).
handle_info(#'basic.ack'{}, State) ->
  {noreply, State};

handle_info(Msg, State) ->
  lager:error("Invalid msg: ~p", [Msg]),
  {noreply, State}.

-spec handle_call(
  term(), {pid(), reference()}, state()
) -> {reply, term() | {invalid_request, term()}, state()}.
handle_call(
  {deliver, _}, _From, State=#state{available = false}) ->
  {reply, not_available, State};

handle_call({deliver, {Safe, Exchange, Key, Payload}}, _From, State=#state{channel = Channel}) ->
  {Pid, Ref} = spawn_monitor(fun() ->
    exit(publish(Channel, Safe, Exchange, Key, Payload))
  end),
  Ret = receive
    {'DOWN', Ref, process, Pid, Reason} -> case Reason of
      ok -> ok;
      Error -> Error
    end
  end,
  lager:debug("Delivery ended with: ~p", [Ret]),
  {reply, Ret, State};

handle_call(Req, _From, State) ->
  lager:error("Invalid request: ~p", [Req]),
  {reply, invalid_request, State}.

-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

-spec code_change(string(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
publish(Channel, Safe, Exchange, Key, Payload) ->
  ok = amqp_channel:register_confirm_handler(Channel, self()),
  ok = amqp_channel:register_return_handler(Channel, self()),
  ConfirmTimeout = ?SB_CFG:mq_confirm_timeout(),
  Publish = #'basic.publish'{mandatory = Safe, exchange = Exchange, routing_key = Key},
  Ret = case amqp_channel:call(Channel, Publish, #amqp_msg{payload = Payload}) of
    ok ->
      receive
        #'basic.ack'{} -> ok;
        Reason={#'basic.return'{}, _} -> Reason
      after ConfirmTimeout ->
        never_acked
      end;
    Error -> Error
  end,
  ok = amqp_channel:unregister_confirm_handler(Channel),
  ok = amqp_channel:unregister_return_handler(Channel),
  Ret.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% MQ Connection functions.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
connect(Config) ->
  Get = fun
    ({s, X}) ->
      list_to_binary(proplists:get_value(X, Config));
    (X) ->
      proplists:get_value(X, Config) end,
  new_channel(amqp_connection:start(#amqp_params_network{
    username = Get({s, user}),
    password = Get({s, pass}),
    virtual_host = Get({s, vhost}),
    port = Get(port),
    host = Get(host)
  })).

new_channel({ok, Connection}) ->
  configure_channel(amqp_connection:open_channel(Connection));

new_channel(Error) ->
  Error.

configure_channel({ok, Channel}) ->
  case amqp_channel:call(Channel, #'confirm.select'{}) of
    {'confirm.select_ok'} -> {ok, Channel};
    Error -> lager:warning("Could not configure channel: ~p", [Error]), Error
  end;

configure_channel(Error) ->
  Error.

