%%% @doc Queue consumer behavior. These will periodically try to flush its
%%% queue via the real mq.
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
-module(safe_bunny_consumer).
-author("marcelog@gmail.com").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").

-behavior(gen_server).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Types.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-record(state, {
  callback = undefined:: module(),
  callback_state = undefined:: term(),
  consumer_poll = undefined:: pos_integer()
}).
-type state():: #state{}.
-type options():: proplists:proplist().

-export_type([options/0, state/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-callback init(options()) -> {ok, state()}|{error, term()}.
-callback next() -> safe_bunny:queue_fetch_result().
-callback delete(safe_bunny:queue_id()) -> ok|term().
-callback terminate(any(), state()) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([start_link/2]).

%%% gen_server callbacks.
-export([
  init/1, terminate/2, code_change/3,
  handle_call/3, handle_cast/2, handle_info/2
]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @doc Starts the gen_server.
-spec start_link(options(), atom()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Config, Module) ->
  gen_server:start_link({local, Module}, ?MODULE, [Config, Module], []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% gen_server API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init([term()]) -> {ok, state()}.
init([Config, Module]) ->
  {ok, CallbackState} = Module:init(Config),
  PollTime = proplists:get_value(consumer_poll, Config),
  erlang:send_after(PollTime, self(), poll),
  {ok, #state{
    callback = Module,
    callback_state = CallbackState,
    consumer_poll = PollTime
  }, hibernate}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(Msg, State) ->
  lager:error("Invalid cast: ~p", [Msg]),
  {noreply, State, hibernate}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(poll, State=#state{callback = Module, consumer_poll = PollTime}) ->
  try
    case Module:next() of
      {ok, {Id, Data}} ->
        {Json} = jiffy:decode(Data),
        Exchange = proplists:get_value(<<"exchange">>, Json),
        Key = proplists:get_value(<<"key">>, Json),
        Payload = base64:decode(proplists:get_value(<<"payload">>, Json)),
        lager:debug("Processing queued item (~p) for: ~p:~p: id: ~p:~p", [Module, Exchange, Key, Id, Payload]),
        case safe_bunny_worker:deliver(true, Exchange, Key, Payload) of
          ok -> Module:delete(Id);
          ErrorMq -> lager:warning("Could not dispatch queued item into mq: ~p", [ErrorMq]), ok
        end;
      none -> ok;
      Error -> lager:error("Could not poll queue (1): ~p: ~p", [Module, Error]), ok
    end
  catch
    _: E ->
      lager:error(
        "Could not poll queue (2): ~p: ~p - Stacktrace: ~p",
        [Module, E, erlang:get_stacktrace()]
      ),
      E
  end,
  erlang:send_after(PollTime, self(), poll),
  {noreply, State, hibernate};

handle_info(Msg, State) ->
  lager:error("Invalid msg: ~p", [Msg]),
  {noreply, State, hibernate}.

-spec handle_call(
  term(), {pid(), reference()}, state()
) -> {reply, term() | {invalid_request, term()}, state()}.
handle_call(Req, _From, State) ->
  lager:error("Invalid request: ~p", [Req]),
  {reply, invalid_request, State, hibernate}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

-spec code_change(string(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
