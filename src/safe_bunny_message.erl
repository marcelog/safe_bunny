%%% @doc Helper module to work with messages.
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
-module(safe_bunny_message).
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
-record(safe_bunny_message, {
  id = undefined:: string(),
  exchange = undefined:: string(),
  key = undefined:: string(),
  payload = undefined:: string(),
  attempts = undefined:: pos_integer()
}).
-type message():: #safe_bunny_message{}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-export_type([message/0]).
-export([new/3, new/5]).
-export([id/1, exchange/1, key/1, payload/1, attempts/1]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec new(binary(), binary(), binary()) -> message().
new(Exchange, Key, Payload) ->
  new(new_id(), Exchange, Key, Payload, 0).

-spec new(binary(), binary(), binary(), binary(), pos_integer()) -> message().
new(Id, Exchange, Key, Payload, Attempts)
  when is_binary(Id)
  andalso is_binary(Exchange)
  andalso is_binary(Key)
  andalso is_binary(Payload)
  andalso is_integer(Attempts) ->
  #safe_bunny_message{
    id = Id,
    exchange = Exchange,
    key = Key,
    payload = Payload,
    attempts = Attempts
  }.

-spec id(message()) -> binary().
id(#safe_bunny_message{id = Id}) ->
  Id.

-spec exchange(message()) -> binary().
exchange(#safe_bunny_message{exchange = Exchange}) ->
  Exchange.

-spec key(message()) -> binary().
key(#safe_bunny_message{key = Key}) ->
  Key.

-spec payload(message()) -> binary().
payload(#safe_bunny_message{payload = Payload}) ->
  Payload.

-spec attempts(message()) -> binary().
attempts(#safe_bunny_message{attempts = Attempts}) ->
  Attempts.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec new_id() -> binary().
new_id() ->
  list_to_binary(uuid:to_string(uuid:uuid4())).
