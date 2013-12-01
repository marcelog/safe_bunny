%%% @doc Uses worker_pool to start a bunch of eredis connections so multiple
%%% items can be pushed into the queue concurrently.
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
-module(safe_bunny_producer_redis).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

-behavior(safe_bunny_producer).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {
  eredis = undefined:: pid()
}).
-type state():: #state{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% safe_bunny_producer behavior.
-export([start_link/1, queue/1]).

%%% worker_pool callbacks.
-export([
  init/1, terminate/2, code_change/3,
  handle_call/3, handle_cast/2, handle_info/2
]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start_link(safe_bunny_producer:options()) -> {ok, pid()}|ignore|{error, term()}.
start_link(Options) ->
  Get = fun(Key) -> proplists:get_value(Key, Options) end,
  PoolSize = Get(producer_connections),
  wpool:start_pool(?MODULE, [
    {overrun_warning, 5000},
    {workers, PoolSize},
    {worker, {?MODULE, Options}}
  ]).

-spec init(safe_bunny_producer:options()) -> {ok, state()}|ignore|{error, term()}.
init(Options) ->
  Host = proplists:get_value(host, Options),
  Port = proplists:get_value(port, Options),
  Db = proplists:get_value(db, Options),
  {ok, Pid} = eredis:start_link(Host, Port),
  {ok, <<"OK">>} = eredis:q(Pid, [<<"select">>, Db]),
  {ok, #state{eredis=Pid}}.

-spec queue(safe_bunny_message:queue_payload()) -> ok|term().
queue(Message) ->
  wpool:call(?MODULE, {queue, Message}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% worker_pool API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(Unknown, State) ->
  lager:error("Unknown cast: ~p", [Unknown]),
  {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(Unknown, State) ->
  lager:error("Unknown message: ~p", [Unknown]),
  {noreply, State}.

-spec handle_call(
  term(), {pid(), reference()}, state()
) -> {reply, term() | {invalid_request, term()}, state()}.
handle_call({queue, Message}, _From, #state{eredis=C} = State) ->
  Id = safe_bunny_message:id(Message),
  Key = safe_bunny_common_redis:key_message(Id),
  Ret = safe_bunny_common_redis:assert_transaction_result(eredis:qp(C, [
    [<<"MULTI">>],
    [<<"HSET">>, Key, "id", safe_bunny_message:id(Message)],
    [<<"HSET">>, Key, "exchange", safe_bunny_message:exchange(Message)],
    [<<"HSET">>, Key, "key", safe_bunny_message:key(Message)],
    [<<"HSET">>, Key, "payload", safe_bunny_message:payload(Message)],
    [<<"HSET">>, Key, "attempts", safe_bunny_message:attempts(Message)],
    [<<"SADD">>, safe_bunny_common_redis:key_queue(), Id],
    [<<"EXEC">>]
  ])),
  {reply, Ret, State};

handle_call(Unknown, _From, State) ->
  lager:error("Unknown request: ~p", [Unknown]),
  {reply, {invalid_request, Unknown}, State}.

-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

-spec code_change(string(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
