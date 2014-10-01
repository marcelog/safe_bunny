%%% @doc Uses an emysql pool to handle multiple connections to mysql for
%%% queuing items in a concurrent fashion.
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
-module(safe_bunny_producer_mysql).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

-behavior(safe_bunny_producer).
-behavior(gen_server).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").
-include_lib("emysql/include/emysql.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {}).
-type state():: #state{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% safe_bunny_producer behavior.
-export([start_link/1, queue/1]).

%%% gen_server callbacks.
-export([
  init/1, terminate/2, code_change/3,
  handle_call/3, handle_cast/2, handle_info/2
]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start_link(safe_bunny_producer:options()) -> {ok, pid()}|ignore|{error, term()}.
start_link(Options) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, Options, []).

-spec init(safe_bunny_producer:options()) -> {ok, state()}|ignore|{error, term()}.
init(Options) ->
  Get = fun(Key) -> proplists:get_value(Key, Options) end,
  User = Get(user),
  Pass = Get(pass),
  Host = Get(host),
  Port = Get(port),
  Db = Get(db),
  Table = Get(table),
  PoolSize = Get(producer_connections),
  ok = try
    ok = emysql:add_pool(?MODULE, 1, User, Pass, Host, Port, Db, utf8)
  catch
    _:pool_already_exists -> ok;
    _:Error -> Error
  end,
  #ok_packet{} = emysql:execute(?MODULE, ?CREATE_TABLE_SQL(Table)),
  ok = emysql:prepare(new_item, lists:flatten([
    "INSERT INTO `", Table, "` (`uuid`, `exchange`, `key`, `payload`) VALUES(?,?,?,?)"
  ])),
  {ok, #state{}}.

-spec queue(safe_bunny_message:queue_payload()) -> ok|term().
queue(Message) ->
  #ok_packet{} = emysql:execute(?MODULE, new_item, [
    safe_bunny_message:id(Message),
    safe_bunny_message:exchange(Message),
    safe_bunny_message:key(Message),
    base64:encode(safe_bunny_message:payload(Message))
  ]),
  ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% gen_server API.
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
handle_call(Unknown, _From, State) ->
  lager:error("Unknown request: ~p", [Unknown]),
  {reply, {invalid_request, Unknown}, State}.

-spec terminate(atom(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

-spec code_change(string(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
