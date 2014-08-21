%%% @doc Main module.
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
-module(safe_bunny).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-define(APPS, [
  compiler,
  syntax_tools,
  lager,
  crypto,
  worker_pool,
  emysql,
  eredis,
  asn1,
  crypto,
  public_key,
  ssl,
  safe_bunny
]).

-type queue_id():: term().
-type queue_message():: term().
-type queue_element():: {queue_id(), queue_message()}.
-type queue_fetch_result():: {
  ok, queue_element(), safe_bunny_consumer:callback_state()
}.

-export_type([
  queue_id/0,
  queue_message/0,
  queue_element/0,
  queue_fetch_result/0
]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-export([start/0, stop/0]).
-export([producer_module/1, consumer_module/1]).
-export([queue/3, deliver_safe/3, deliver_unsafe/3]).
-export([queue_task/3, deliver_task/4]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Queue functions.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Will put an item into a backup queue, iterating the available 
%% producers. Should fail only when all backends failed to save the message.
-spec queue(binary(), binary(), binary()) -> ok|term().
queue(Exchange, Key, Payload) ->
  cxy_ctl:execute_pid_monitor(
    ?SAFE_BUNNY_MQ_DELIVER_TASK, ?MODULE, queue_task, [Exchange, Key, Payload]
  ).

%% @doc Tries MQ first, then local queuing system. Technically speaking it would
%% be safer to actually deliver directly to the local queuing backends instead
%% of trying the remote mq, but it could be accepted that if the mq system is
%% up 99.999% of the time, you might not want to hit your db (mysql, redis)
%% that much during normal operations.
-spec deliver_safe(binary(), binary(), binary()) -> {reference(), pid()}.
deliver_safe(Exchange, Key, Payload) ->
  cxy_ctl:execute_pid_monitor(
    ?SAFE_BUNNY_MQ_DELIVER_TASK, ?MODULE, deliver_task, [true, Exchange, Key, Payload]
  ).

%% @doc Tries MQ. Confirmation is not required from the server, and messages will
%% not be saved in the fallback queues on failure.
-spec deliver_unsafe(binary(), binary(), binary()) -> {reference(), pid()}.
deliver_unsafe(Exchange, Key, Payload) ->
  cxy_ctl:execute_pid_monitor(
    ?SAFE_BUNNY_MQ_DELIVER_TASK, ?MODULE, deliver_task, [false, Exchange, Key, Payload]
  ).

%% @doc Returns the module name for the given producer backend module.
-spec producer_module(atom()) -> atom().
producer_module(Name) ->
  list_to_atom("safe_bunny_producer_" ++ atom_to_list(Name)).

%% @doc Returns the module name for the given consumer backend module.
-spec consumer_module(atom()) -> atom().
consumer_module(Name) ->
  list_to_atom("safe_bunny_consumer_" ++ atom_to_list(Name)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Called by cxy tools.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Called by cxy tools, tries mq first, then queue backends.
-spec deliver_task(boolean(), binary(), binary(), binary()) -> ok|term().
deliver_task(Safe, Exchange, Key, Payload) ->
  case safe_bunny_worker:deliver(Safe, Exchange, Key, Payload) of
    ok -> ok;
    Error -> case Safe of
      true ->
        lager:warning("Failed MQ delivering (~p), queuing", [Error]),
        ok = queue_task(Exchange, Key, Payload);
      false ->
        lager:warning("Dropping message since MQ failed (~p)", [Error])
    end
  end.

%% @doc Will put an item into a backup queue, iterating the available 
%% producers. Should fail only when all backends failed to save the message.
-spec queue_task(binary(), binary(), binary()) -> ok|term().
queue_task(Exchange, Key, Payload) ->
  Message = safe_bunny_message:new(Exchange, Key, Payload),
  ok = queue(Message, ?SB_CFG:producers()).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Application helper functions.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Starts the application.
-spec start() -> ok.
start() ->
  [application:start(App) || App <- ?APPS],
  ok.

%% @doc Stops the application.
-spec stop() -> ok.
stop() ->
  [application:stop(App) || App <- lists:reverse(?APPS)],
  ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec queue(binary(), [atom()]) -> ok|term().
queue(Item, []) ->
  lager:critical("Could not queue message: ~p", [Item]),
  {error, out_of_backends};

queue(Item, [Backend|Rest]) ->
  lager:info("Trying backend queue: ~p", [Backend]),
  try
    Module = producer_module(Backend),
    case Module:queue(Item) of
      ok -> ok;
      Error ->
        lager:warning(
          "Backend ~p failed (1: ~p) for storing message: ~p", [Backend, Error, Item]
        ),
        queue(Item, Rest)
    end
  catch
    _:E ->
      lager:warning(
        "Backend ~p failed (2: ~p) for storing message: ~p: Stacktrace: ~p",
        [Backend, E, Item, erlang:get_stacktrace()]
      ),
      queue(Item, Rest)
  end.
