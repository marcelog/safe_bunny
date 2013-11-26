%%% @doc Centralizes configuration access.
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
-module(safe_bunny_config).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-export([get_option/1, get_option/2]).
-export([concurrency_limits/0]).
-export([consumers/0, producers/0]).
-export([mq/0]).
-export([ets/0, file/0, redis/0, mysql/0]).
-export([mysql_table/0, redis_key_prefix/0, ets_name/0, file_directory/0]).
-export([mq_confirm_timeout/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Application concurrency limits.
-spec concurrency_limits() -> proplists:proplist().
concurrency_limits() ->
  get_option(concurrency_limits, [
    {?SAFE_BUNNY_MQ_DELIVER_TASK, 50000, 0}
  ]).

%% @doc Configured consumers.
-spec consumers() -> proplists:proplist().
consumers() ->
  get_option(consumers, []).

%% @doc Configured producers.
-spec producers() -> proplists:proplist().
producers() ->
  get_option(producers).

%% @doc Returns mq options.
-spec mq() -> proplists:proplist().
mq() ->
  get_option(mq, [
    {workers, 1}, % Number of connections,
    {host, "127.0.0.1"},
    {port, 5672},
    {user, "guest"},
    {pass, "guest"},
    {vhost, "/"},
    {confirm_timeout, 10000}
  ]).

%% @doc Shortcut to get mq confirmation timeout.
-spec mq_confirm_timeout() -> pos_integer().
mq_confirm_timeout() ->
  proplists:get_value(confirm_timeout, mq()).

%% @doc Returns ets backend options.
-spec ets() -> proplists:proplist().
ets() ->
  get_option(ets, [
    {name, safe_bunny_queue},
    {consumer_poll, 200},
    {backoff_intervals, [500, 1000, 2000, 4000, 10000, 60000]},
    {in_order, false},
    {maximum_retries, 100}
  ]).

%% @doc Shortcut to get ets name.
-spec ets_name() -> atom().
ets_name() ->
  proplists:get_value(name, ets()).

%% @doc Returns file backend options.
-spec file() -> proplists:proplist().
file() ->
  get_option(file, [
    {directory, "/tmp/safe_bunny_queue"},
    {consumer_poll, 200},
    {backoff_intervals, [500, 1000, 2000, 4000, 10000, 60000]},
    {in_order, false},
    {maximum_retries, 100}
  ]).

%% @doc Shortcut to get queue directory for file backend.
-spec file_directory() -> string().
file_directory() ->
  proplists:get_value(directory, file()).

%% @doc Returns redis backend options.
-spec redis() -> proplists:proplist().
redis() ->
  get_option(redis, [
    {host, "127.0.0.1"},
    {port, 6379},
    {db, 0},
    {key_prefix, "safe_bunny"},
    {producer_connections, 1},
    {consumer_poll, 200},
    {backoff_intervals, [500, 1000, 2000, 4000, 10000, 60000]},
    {in_order, false},
    {maximum_retries, 100}
  ]).

%% @doc Shortcut to get redis key.
-spec redis_key_prefix() -> string().
redis_key_prefix() ->
  proplists:get_value(key_prefix, redis()).

%% @doc Returns mysql backend options.
-spec mysql() -> proplists:proplist().
mysql() ->
  get_option(mysql, [
    {host, "127.0.0.1"},
    {port, 3306},
    {user, "root"},
    {pass, "pass"},
    {db, "safe_bunny_queue"},
    {table, "items"},
    {producer_connections, 1},
    {consumer_poll, 200},
    {backoff_intervals, [500, 1000, 2000, 4000, 10000, 60000]},
    {in_order, false},
    {maximum_retries, 100}
  ]).

%% @doc Shortcut to get mysql table name.
-spec mysql_table() -> string().
mysql_table() ->
  proplists:get_value(table, mysql()).

%% @doc Returns the given option, or undefined if not found.
-spec get_option(atom()) -> term().
get_option(Key) ->
  get_option(Key, undefined).

%% @doc Returns an option or the given default is none is found.
-spec get_option(atom(), term()) -> term().
get_option(Key, Default) ->
  case application:get_env(safe_bunny, Key) of
    undefined -> Default;
    {ok, Value} -> Value
  end.
