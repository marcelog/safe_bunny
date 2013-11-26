%%% @doc Mysql to RabbitMQ.
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
-module(safe_bunny_consumer_mysql).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

-behavior(safe_bunny_consumer).

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
-define(SB, safe_bunny).
-define(SBC, safe_bunny_consumer).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% safe_bunny_consumer behavior.
-export([next/1, delete/2]).
-export([failed/2, success/2]).
-export([init/1, terminate/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(safe_bunny_consumer:options()) -> {ok, state()}|{error, term()}.
init(Options) ->
  crypto:start(),
  application:start(emysql),
  Get = fun(Key) -> proplists:get_value(Key, Options) end,
  User = Get(user),
  Pass = Get(pass),
  Host = Get(host),
  Port = Get(port),
  Db = Get(db),
  Table = Get(table),
	ok = emysql:add_pool(?MODULE, 1, User, Pass, Host, Port, Db, utf8),
  #ok_packet{} = emysql:execute(?MODULE, ?CREATE_TABLE_SQL(Table)),
  ok = emysql:prepare(fetch_item, lists:flatten([
    "SELECT `uuid`, `exchange`, `key`, `payload`, `attempts` FROM `", Table,
    "` ORDER BY `id` ASC LIMIT 0,1"
  ])),
  ok = emysql:prepare(delete_item, lists:flatten([
    "DELETE FROM `", Table, "` WHERE `uuid`=? ORDER BY `id` ASC LIMIT 1"
  ])),
  ok = emysql:prepare(requeue_item, lists:flatten([
    "INSERT INTO `", Table, "` ("
      "`uuid`, `exchange`, `key`, `payload`, `attempts`"
    ") ("
    "  SELECT `uuid`, `exchange`, `key`, `payload`, `attempts`+1 FROM `items` WHERE uuid=?"
    ")"
  ])),
  {ok, #state{}}.

-spec next(?SBC:callback_state()) -> ?SB:queue_fetch_result().
next(State) ->
  case emysql:execute(?MODULE, fetch_item, []) of
    #result_packet{rows=[]} ->
      {ok, none, State};
    #result_packet{rows=[[Id, Exchange, Key, Payload, Attempts]]} ->
      {ok, Id, safe_bunny_message:new(Id, Exchange, Key, base64:decode(Payload), Attempts), State};
    Error -> {error, Error, State}
  end.

-spec delete(?SB:queue_id(), ?SBC:callback_state()) -> ?SBC:callback_result().
delete(Id, State) ->
  case emysql:execute(?MODULE, delete_item, [Id]) of
    #ok_packet{affected_rows=1} -> {ok, State};
    #ok_packet{affected_rows=0} -> lager:warning("Item disappeared? ~p", [Id]), {ok, State};
    Error -> {error, Error, State}
  end.

-spec failed(?SB:queue_id(), ?SBC:callback_state()) -> ?SBC:callback_result().
failed(Id, State) ->
  case emysql:execute(?MODULE, requeue_item, [Id]) of
    #ok_packet{} -> delete(Id, State);
    Error -> {error, Error, State}
  end.

-spec success(?SB:queue_id(), ?SBC:callback_state()) -> ?SBC:callback_result().
success(Id, State) ->
  delete(Id, State).

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.
