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
-type callback_state():: term().
-type options():: proplists:proplist().
-type callback_result()::
  {ok, callback_state()}|{error, term(), callback_state()}.

-record(state, {
  callback = undefined:: module(),
  callback_state = undefined:: callback_state(),
  consumer_poll = undefined:: pos_integer(),
  backoff_intervals = []:: [pos_integer()],
  current_intervals = []:: [pos_integer()],
  maximum_retries = undefined:: pos_integer()
}).

-type state():: #state{}.

-export_type([options/0, state/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-callback init(options()) -> {ok, state()}|{error, term()}.

-callback next(callback_state()) ->
  {ok, safe_bunny:queue_fetch_result(), callback_state()}
  |{error, term(), callback_state()}.

-callback failed(safe_bunny:queue_id(), callback_state()) -> callback_result().
-callback success(safe_bunny:queue_id(), callback_state()) -> callback_result().
-callback delete(safe_bunny:queue_id(), callback_state()) -> callback_result().
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
  BackoffIntervals = proplists:get_value(backoff_intervals, Config),
  MaxRetries = proplists:get_value(maximum_retries, Config),
  erlang:send_after(PollTime, self(), poll),
  {ok, #state{
    callback = Module,
    callback_state = CallbackState,
    consumer_poll = PollTime,
    backoff_intervals = BackoffIntervals,
    current_intervals = BackoffIntervals,
    maximum_retries = MaxRetries
  }, hibernate}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(Msg, State) ->
  lager:error("Invalid cast: ~p", [Msg]),
  {noreply, State, hibernate}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info(poll, State=#state{callback = Module}) ->
  {OpResult, NewCallbackState} = case Module:next(State#state.callback_state) of
    {ok, none, NewCallbackState_} -> {ok, NewCallbackState_};
    {ok, QueueId, Message, NewCallbackState_} ->
      Id = safe_bunny_message:id(Message),
      Exchange = safe_bunny_message:exchange(Message),
      Key = safe_bunny_message:key(Message),
      Payload = safe_bunny_message:payload(Message),
      Attempts = safe_bunny_message:attempts(Message),
      lager:debug(
        "~p: Processing queued item for: ~p:~p: id: ~p:~p",
        [Module, Exchange, Key, Id, Payload]
      ),
      case safe_bunny_worker:deliver(true, Exchange, Key, Payload) of
        ok -> Module:success(QueueId, NewCallbackState_);
        PreOpResult ->
          lager:warning("~p: Could not dispatch queued item into mq: ~p", [Module, PreOpResult]),
          Module:failed(QueueId, NewCallbackState_),
          {error, PreOpResult}
      end;        
    Error ->
      lager:error("~p: Could not poll queue (1): ~p", [Module, Error]),
      Error
  end,
  {NextPoll, NewState} = case OpResult of
    ok ->
      {
        State#state.consumer_poll,
        State#state{current_intervals = State#state.backoff_intervals}
      };
    OpError ->
      {NextPoll_, NextIntervals} = case State#state.current_intervals of
        [Last] -> {Last, State#state.current_intervals};
        [N|Rest] -> {N, Rest}
      end,
      lager:warning("~p: Retrying in ~pms due to: ~p", [State#state.callback, NextPoll_, OpError]),
      {NextPoll_, State#state{current_intervals = NextIntervals}}
  end,
  erlang:send_after(NextPoll, self(), poll),
  {noreply, NewState#state{callback_state = NewCallbackState}, hibernate};

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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
