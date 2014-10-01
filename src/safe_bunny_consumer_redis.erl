%%% @doc Redis to RabbitMQ.
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
-module(safe_bunny_consumer_redis).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

-behavior(safe_bunny_consumer).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Required Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-include("safe_bunny.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {
  eredis = undefined:: pid(),
  options = []:: proplists:proplist(),
  ready = false:: boolean()
}).
-type state():: #state{}.
-define(SB, safe_bunny).
-define(SBC, safe_bunny_consumer).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% safe_bunny_consumer behavior.
-export([next/2]).
-export([delete/1]).
%-export([flush/1]).
-export([failed/1, success/1]).
-export([init/1, info/2, terminate/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(safe_bunny_consumer:options()) -> {ok, state()}|{error, term()}.
init(Options) ->
  process_flag(trap_exit, true),
  self() ! {connect},
  {ok, #state{options = Options}}.

-spec next(pos_integer(), ?SBC:callback_state()) ->
  {ok, ?SB:queue_fetch_result(), ?SBC:callback_state()}
  | {error, term(), ?SBC:callback_state()}.
next(_Total, State = #state{ready = false}) ->
  lager:warning("~p not ready", [?MODULE]),
  {ok, [], State};

next(Total, State) ->
  case exec(
    <<"SRANDMEMBER">>,
    [safe_bunny_common_redis:key_queue(), list_to_binary(integer_to_list(Total))]
  ) of
    {ok, undefined} -> {ok, [], State};
    {ok, MessageIds} when is_list(MessageIds) ->
      {ok, lists:map(
        fun(MessageId) ->
          case get_task(MessageId) of
            {error, Error} -> throw({error, Error});
            {ok, Message} -> {MessageId, Message}
          end
        end,
        MessageIds
      ), State};
    Error -> {error, Error, State}
  end.

-spec delete(?SB:queue_id()) -> ?SBC:callback_result().
delete(Id) ->
  case exec(<<"SREM">>, [safe_bunny_common_redis:key_queue(), Id]) of
    {ok, _MessageId} -> exec(<<"DEL">>, [safe_bunny_common_redis:key_message(Id)]);
    Error -> {error, Error}
  end.

-spec failed(?SB:queue_id()) -> ?SBC:callback_result().
failed(Id) ->
  case exec([
    [<<"MULTI">>],
    [<<"HINCRBY">>, safe_bunny_common_redis:key_message(Id), <<"attempts">>, <<"1">>],
    [<<"EXEC">>]
  ]) of
    Results when is_list(Results) -> safe_bunny_common_redis:assert_transaction_result(Results);
    Error -> {error, Error}
  end.

%-spec flush(callback_state()) ->
%  {ok, callback_state()}|{error, term(), callback_state()}.
%flush(State) ->
%  case exec([<<"DEL">>, safe_bunny_common_redis:key_queue()]) of
%    {ok, _} -> {ok, State};
%    {error, Error} -> {error, Error, State}
%  end.

-spec info(any(), ?SBC:callback_state()) -> ?SBC:callback_result().
info({'EXIT', Redis, Reason}, State = #state{eredis = Redis}) ->
  lager:warning("Lost connection: ~p", [Reason]),
  {ok, _} = timer:send_after(5000, self(), {connect}),
  {ok, State#state{ready = false}};

info({'EXIT', Pid, Reason}, State) ->
  lager:warning("Dying because of: ~p with ~p", [Pid, Reason]),
  {stop, State};

info({connect}, State = #state{options = Options}) ->
  lager:debug("Connecting to: ~p", [Options]),
  Host = proplists:get_value(host, Options),
  Port = proplists:get_value(port, Options),
  Db = proplists:get_value(db, Options),
  try
    case eredis:start_link(Host, Port) of
      {ok, Pid} ->
        erlang:register(redis_name(), Pid),
        {ok, _} = exec(<<"select">>, [Db]),
        {ok, State#state{ready = true, eredis=Pid}};
      Error -> receive _X -> ok after 500 -> ok end, throw(Error)
    end
  catch 
    _:HardError ->
      lager:error(
        "Could not connect to ~p: ~p: ~p",
        [Options, HardError, erlang:get_stacktrace()]
      ),
      {ok, _} = timer:send_after(5000, self(), {connect}),
      {ok, State#state{ready = false}}
  end;

info(Msg, State) ->
  lager:error("Invalid msg: ~p", [Msg]),
  {ok, State, hibernate}.

-spec success(?SB:queue_id()) -> ?SBC:callback_result().
success(Id) ->
  delete(Id).

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
redis_name() ->
  list_to_atom(atom_to_list(?MODULE) ++ "_redis" ).

exec(Cmd, Args) ->
  eredis:q(redis_name(), [Cmd|Args]).

exec(Cmds) ->
  eredis:qp(redis_name(), Cmds).

kvs_to_proplist(KVs) ->
  kvs_to_proplist(KVs, []).

kvs_to_proplist([], Acc) ->
  Acc;

kvs_to_proplist([K, V|Rest], Acc) ->
  kvs_to_proplist(Rest, [{K, V}|Acc]).

-spec get_task(binary()) -> not_found|{ok, term()}|{error, term()}.
get_task(Id) ->
  case exec(<<"HGETALL">>, [safe_bunny_common_redis:key_message(Id)]) of
    {ok, []} -> not_found;
    {ok, KVs} ->
      Message = kvs_to_proplist(KVs),
      {ok, safe_bunny_message:new(
        proplists:get_value(<<"id">>, Message),
        proplists:get_value(<<"exchange">>, Message),
        proplists:get_value(<<"key">>, Message),
        proplists:get_value(<<"payload">>, Message),
        list_to_integer(binary_to_list(proplists:get_value(<<"attempts">>, Message)))
      )};
    Error -> {error, Error}
  end.
