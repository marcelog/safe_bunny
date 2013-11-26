%%% @doc File to RabbitMQ.
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
-module(safe_bunny_consumer_file).
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
-export([next/1, delete/2]).
-export([failed/2, success/2]).
-export([init/1, terminate/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(safe_bunny_consumer:options()) -> {ok, state()}|{error, term()}.
init(_Options) ->
  {ok, []}.

-spec next(?SBC:callback_state()) -> ?SB:queue_fetch_result().
next(State) ->
  try
  	case filelib:fold_files(
      ?SB_CFG:file_directory(), ".*", false, fun(Filename, _Acc) ->
        {ok, Payload} = file:read_file(Filename),
        throw({got_one, Filename, Payload})
      end, []) of
      [] -> {ok, none, State};
      ErrorInDir -> {error, ErrorInDir, State}
    end
  catch
    _:{got_one, Filename, Payload} ->
      [_Ts, Id, Exchange, Key, Attempts] = string:tokens(filename:basename(Filename), "."),
      {ok, Filename, safe_bunny_message:new(
        list_to_binary(Id),
        list_to_binary(Exchange),
        list_to_binary(Key),
        Payload,
        list_to_integer(Attempts)
      ), State};
    _:Error -> {error, Error}
  end.

-spec failed(?SB:queue_id(), ?SBC:callback_state()) -> ?SBC:callback_result().
failed(Id, State) ->
  Basename = filename:basename(Id),
  [Ts, Hash, Attempts] = string:tokens(Basename, "-"),
  NewAttempts = integer_to_list(list_to_integer(Attempts) + 1),
  NewName = filename:dirname(Id) ++ "/" ++ Ts ++ "-" ++ Hash ++ "-" ++ NewAttempts,
  case file:rename(Id, NewName) of
    ok -> {ok, State};
    Error -> {error, Error, State}
  end.

-spec success(?SB:queue_id(), ?SBC:callback_state()) -> ?SBC:callback_result().
success(Id, State) ->
  delete(Id, State).

-spec delete(?SB:queue_id(), ?SBC:callback_state()) -> ?SBC:callback_result().
delete(Id, State) ->
  case file:delete(Id) of
    ok -> {ok, State};
    Error -> {error, Error, State}
  end.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.
