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
-type callback_result():: ok|{error, term()}.

-record(state, {
  callback = undefined:: undefined|module(),
  callback_state = undefined:: undefined|callback_state(),
  poll_intervals = []:: [pos_integer()],
  current_intervals = []:: [pos_integer()],
  maximum_retries = undefined:: undefined|pos_integer(),
  concurrent_deliveries = undefined:: undefined|pos_integer(),
  current_tasks = []:: [binary()],
  poll_timer = undefined:: undefined|term()
}).

-type state():: #state{}.

-export_type([options/0, state/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Behavior definition.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-callback init(options()) -> {ok, state()}|{error, term()}.

%-callback flush(callback_state()) ->
%  {ok, callback_state()}|{error, term(), callback_state()}.
-callback next(pos_integer(), callback_state()) ->
  {ok, safe_bunny:queue_fetch_result(), callback_state()}
  |{error, term(), callback_state()}.

-callback failed(safe_bunny:queue_id()) -> callback_result().
-callback success(safe_bunny:queue_id()) -> callback_result().
-callback delete(safe_bunny:queue_id()) -> callback_result().
-callback terminate(any(), state()) -> ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([start_link/2]).
-export([run_task_task/3]).

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
  PollIntervals = proplists:get_value(poll_intervals, Config),
  MaxRetries = proplists:get_value(maximum_retries, Config),
  ConcurrentDeliveries = proplists:get_value(concurrent_deliveries, Config),
  PollTimer = erlang:send_after(hd(PollIntervals), self(), poll),
  {ok, #state{
    callback = Module,
    callback_state = CallbackState,
    poll_intervals = PollIntervals,
    current_intervals = PollIntervals,
    maximum_retries = MaxRetries,
    concurrent_deliveries = ConcurrentDeliveries,
    poll_timer = PollTimer
  }, hibernate}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(Msg, State) ->
  lager:error("Invalid cast: ~p", [Msg]),
  {noreply, State, hibernate}.

-spec handle_info(any(), state()) -> {noreply, state()}.
handle_info({'DOWN', _MQRef, process, _MQPid, _Reason}, State) ->
  %lager:debug("process finished: ~p", [Reason]),
  {noreply, State, hibernate};

handle_info({task_ended, {QueueId, Task}, Result}, State) ->
  Module = State#state.callback,
  Attempts = safe_bunny_message:attempts(Task) + 1,
  NewState = case Result of
    ok ->
      Module:success(QueueId),
      State;
    Result when Attempts >= State#state.maximum_retries ->
      lager:warning("~p: Dropping item because of max attempts: ~p: ~p", [Module, Result, Task]),
      Module:delete(QueueId),
      State;
    not_available ->
      % Don't blame this ones on the task. Also, try to back off.
      lager:warning("~p: MQ Not available", [Module]),
      erlang:cancel_timer(State#state.poll_timer),
      PollTime = hd(lists:reverse(State#state.poll_intervals)),
      lager:warning(
        "~p: Retrying in ~pms due to mq not available", [State#state.callback, PollTime]
      ),
      PollTimer = erlang:send_after(PollTime, self(), poll),
      State#state{poll_timer = PollTimer};
    never_acked ->
      lager:warning("~p: MQ Did not ack message: ~p", [QueueId, Module]),
      Module:failed(QueueId),
      State;
    Result ->
      lager:warning("~p: MQ Error: ~p", [Module, Result]),
      Module:failed(QueueId),
      State
  end,
  NewCurrentTasks = State#state.current_tasks -- [QueueId],
  {noreply, NewState#state{current_tasks = NewCurrentTasks}, hibernate};

handle_info(poll, State=#state{
  callback = Module,
  callback_state = CallbackState
}) ->
  TotalNextTasks = State#state.concurrent_deliveries - length(State#state.current_tasks),
  {OpResult, NewCallbackState} = case Module:next(TotalNextTasks, CallbackState) of
    {ok, NextTasks_, NewCallbackState_} -> {NextTasks_, NewCallbackState_};
    {error, Error, NewCallbackState_} ->
      lager:error("~p: Could not poll queue (1): ~p", [Module, Error]),
      {error, NewCallbackState_}
  end,
  {NextPoll, NewState} = try
    case OpResult of
      NextTasks when is_list(NextTasks) ->
        case run_tasks(NextTasks, State#state{callback_state = NewCallbackState}) of
          {ok, NewState_} -> {
            hd(NewState_#state.poll_intervals),
            NewState_#state{current_intervals = NewState_#state.poll_intervals}
          };
          Error1 -> throw(Error1)
        end;
      Error2 -> throw(Error2)
    end
  catch
    _:OpError ->
        {NextPoll_, NextIntervals} = case State#state.current_intervals of
          [Last] -> {Last, State#state.current_intervals};
          [N|Rest] -> {N, Rest}
        end,
        lager:warning(
          "~p: Retrying in ~pms due to: ~p (~p)",
          [State#state.callback, NextPoll_, OpError, erlang:get_stacktrace()]
        ),
        {NextPoll_, State#state{current_intervals = NextIntervals}}
  end,
  PollTimer = erlang:send_after(NextPoll, self(), poll),
  {noreply, NewState#state{
    callback_state = NewCallbackState,
    poll_timer = PollTimer
  }, hibernate};

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
run_tasks([], State) ->
  {ok, State};

run_tasks(
  [{QueueId, Task}|Rest],
  State=#state{
    callback = Module,
    current_tasks = CurrentTasks
  }
) ->
  {Result, NewCurrentTasks} = case lists:member(QueueId, CurrentTasks) of
    false -> case cxy_ctl:maybe_execute_pid_monitor(
      Module, ?MODULE, run_task_task, [self(), Module, {QueueId, Task}]
    ) of
      {max_pids, _MaxCount} ->
        {max_pids, CurrentTasks};
      {Pid, Reference} when is_pid(Pid) andalso is_reference(Reference) ->
        {ok, [QueueId|CurrentTasks]}
    end;
    true -> {ok, CurrentTasks}
  end,
  case Result of
    max_pids -> {max_pids, State};
    _ -> run_tasks(Rest, State#state{current_tasks = NewCurrentTasks})
  end.

%% @doc Will actually send a message to Controller to yield the result.
-spec run_task_task(
  pid(), atom(), {safe_bunny:queue_id(), safe_bunny:queue_payload()}
) -> ok.
run_task_task(Controller, Module, {QueueId, Task}) ->
  Id = safe_bunny_message:id(Task),
  Exchange = safe_bunny_message:exchange(Task),
  Key = safe_bunny_message:key(Task),
  Payload = safe_bunny_message:payload(Task),
  Attempts = safe_bunny_message:attempts(Task),
  lager:debug(
    "~p: Processing queued item for: ~p:~p: id: ~p:~p / ~p attempts",
    [Module, Exchange, Key, Id, Payload, Attempts]
  ),
  Result = safe_bunny_worker:deliver(true, Exchange, Key, Payload),
  Controller ! {task_ended, {QueueId, Task}, Result},
  ok.
