-module(file_SUITE).

-define(BACKEND, file).

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([
  can_deliver/1,
  can_deliver_eventually/1,
  can_drop_safe_on_max_attempts/1,
  can_drop_unsafe_on_max_attempts/1,
  complete_coverage/1
]).

-spec all() -> [atom()].
all() ->
  helper_backend_tests:all().

-spec init_per_testcase(term(), term()) -> void.
init_per_testcase(TestCase, Config) ->
  helper_backend_tests:init_per_testcase(?BACKEND, TestCase, Config).

-spec end_per_testcase(term(), term()) -> void.
end_per_testcase(TestCase, Config) ->
  helper_backend_tests:end_per_testcase(?BACKEND, TestCase, Config).

-spec can_deliver([term()]) -> ok.
can_deliver(Config) ->
  helper_backend_tests:can_deliver(?BACKEND, Config).

-spec can_deliver_eventually([term()]) -> ok.
can_deliver_eventually(Config) ->
  helper_backend_tests:can_deliver_eventually(?BACKEND, Config).

-spec can_drop_safe_on_max_attempts([term()]) -> ok.
can_drop_safe_on_max_attempts(Config) ->
  helper_backend_tests:can_drop_safe_on_max_attempts(?BACKEND, Config).

-spec can_drop_unsafe_on_max_attempts([term()]) -> ok.
can_drop_unsafe_on_max_attempts(Config) ->
  helper_backend_tests:can_drop_unsafe_on_max_attempts(?BACKEND, Config).

-spec complete_coverage([term()]) -> ok.
complete_coverage(Config) ->
  helper_backend_tests:complete_coverage(?BACKEND, Config).
