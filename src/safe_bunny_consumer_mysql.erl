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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-export([next/0, delete/1]).

%%% safe_bunny_consumer behavior.
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
    "SELECT `id`, `data` FROM `", Table, "` ORDER BY `id` ASC LIMIT 0,1"
  ])),
  ok = emysql:prepare(delete_item, lists:flatten([
    "DELETE FROM `", Table, "` WHERE `id`=?"
  ])),
  {ok, #state{}}.

-spec next() -> safe_bunny:queue_fetch_result().
next() ->
  case emysql:execute(?MODULE, fetch_item, []) of
    #result_packet{rows=[]} -> none;
    #result_packet{rows=[[Id, Payload]]} -> {ok, {Id, Payload}};
    Error -> Error
  end.

-spec delete(safe_bunny:queue_id()) -> ok|term().
delete(Id) ->
  case emysql:execute(?MODULE, delete_item, [Id]) of
    #result_packet{rows=[]} -> none;
    #result_packet{rows=[[Id, Payload]]} -> {ok, {Id, Payload}};
    Error -> Error
  end.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.
