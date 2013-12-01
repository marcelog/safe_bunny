%%% @doc ETS to RabbitMQ.
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
-module(safe_bunny_consumer_ets).
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
-record(state, {}).
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
-export([init/1, terminate/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(?SBC:options()) -> {ok, state()}|{error, term()}.
init(_Options) ->
  {ok, []}.

-spec next(pos_integer(), ?SBC:callback_state()) -> ?SB:queue_fetch_result().
next(Total, State) ->
  next(Total, State, 0, []).

next(Total, State, Total, Acc) ->
  {ok, lists:reverse(Acc), State};

next(Total, State, 0, Acc) ->
  case ets:first(?SB_CFG:ets_name()) of
    '$end_of_table' -> next(Total, State, Total, Acc);
    Id ->
      % No concurrent consumers
      [{_Ts, Message}] = ets:lookup(?SB_CFG:ets_name(), Id),
      next(Total, State, 1, [{Id, Message}])
  end;

next(Total, State, SoFar, [Last|_] = Acc) ->
  case ets:next(?SB_CFG:ets_name(), Last) of
    '$end_of_table' -> next(Total, State, Total, Acc);
    Id ->
      % No concurrent consumers
      [{_Ts, Message}] = ets:lookup(?SB_CFG:ets_name(), Id),
      next(Total, State, SoFar + 1, [{Id, Message}|Acc])
  end.

-spec delete(?SB:queue_id()) -> ?SBC:callback_result().
delete(Id) ->
  ets:delete(?SB_CFG:ets_name(), Id),
  ok.

-spec success(?SB:queue_id()) -> ?SBC:callback_result().
success(Id) ->
  delete(Id).

-spec failed(?SB:queue_id()) -> ?SBC:callback_result().
failed(_Id) ->
  ok.

%-spec flush(callback_state()) ->
%  {ok, callback_state()}|{error, term(), callback_state()}.
%flush(State) ->
%  case ets:delete_all_objects(?SB_CFG:ets_name()) of
%    true -> {ok, State};
%    Error -> {error, Error, State}
%  end.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.
