-module(safe_bunny_helper_utils).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Exports.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
-export([start/2, stop/0]).
-export([start_needed_deps/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Public API.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start_needed_deps() -> ok.
start_needed_deps() ->
  Apps = [
    compiler,
    syntax_tools,
    lager,
    crypto,
    emysql
	],
  [application:start(App) || App <- Apps],
  ok.

-spec start(atom(), term()) -> proplists:proplist().
start(TestCase, _Config) ->
  start_needed_deps(),
  ok = safe_bunny:start(),
  lager:debug("Starting testcase: ~p", [TestCase]),
  [].

-spec stop() -> ok.
stop() ->
  safe_bunny:stop(),
  {ok, [ConfigFile|_]} = init:get_argument(config),
  {ok, Terms} = file:consult(ConfigFile ++ ".config"),
  Config = proplists:get_value(safe_bunny, hd(Terms)),
  [ok = application:set_env(safe_bunny, K, V) || {K, V} <- Config],
  timer:sleep(50),
  ok.
