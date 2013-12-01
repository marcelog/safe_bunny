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
-export([next/2]).
-export([delete/1]).
%-export([flush/1]).
-export([failed/1, success/1]).
-export([init/1, terminate/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(safe_bunny_consumer:options()) -> {ok, state()}|{error, term()}.
init(_Options) ->
  {ok, []}.

-spec next(pos_integer(), ?SBC:callback_state()) -> ?SB:queue_fetch_result().
next(Total, State) ->
  try
    case filelib:fold_files(
      ?SB_CFG:file_directory(), ".*", false, fun(Filename, Acc) ->
        case length(Acc) of
          Len when Len =:= Total -> throw({done, Acc});
          _ ->
            {ok, Payload} = file:read_file(Filename),
            [_Ts, Id, Exchange, Key, Attempts] = string:tokens(filename:basename(Filename), "."),
            Message = safe_bunny_message:new(
              list_to_binary(Id),
              list_to_binary(Exchange),
              list_to_binary(Key),
              Payload,
              list_to_integer(Attempts)
            ),
            [{Filename, Message}|Acc]
        end
      end, []) of
      Files when is_list(Files) -> {ok, lists:reverse(Files), State};
      ErrorInDir -> {error, ErrorInDir, State}
    end
  catch
    _:{done, Ret} -> {ok, lists:reverse(Ret), State};
    _:Error -> {error, Error}
  end.

-spec failed(?SB:queue_id()) -> ?SBC:callback_result().
failed(Filename) ->
  Basename = filename:basename(Filename),
  [Ts, Id, Exchange, Key, Attempts] = string:tokens(filename:basename(Basename), "."),
  NewAttempts = integer_to_list(list_to_integer(Attempts) + 1),
  Directory = ?SB_CFG:file_directory(),
  NewName = Directory ++ "/" ++ string:join([Ts, Id, Exchange, Key, NewAttempts], "."),
  file:rename(Filename, NewName).

-spec success(?SB:queue_id()) -> ?SBC:callback_result().
success(Id) ->
  delete(Id).

-spec delete(?SB:queue_id()) -> ?SBC:callback_result().
delete(Id) ->
  file:delete(Id).

%-spec flush(callback_state()) ->
%  {ok, callback_state()}|{error, term(), callback_state()}.
%flush(State) ->
%  {error, not_supported, State};

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.
