-module(prometheus_process_collector).
-moduledoc "Prometheus OS process collector API".

-on_load(init/0).
-nifs([get_process_info/0]).
-export([deregister_cleanup/1, collect_mf/2, collect_metrics/2]).
-export([get_process_info/0]).

-ifdef(TEST).
-export([parse_status/1, parse_limits/1, parse_kb/1, parse_int/1]).
-endif.

-behaviour(prometheus_collector).

-define(APPNAME, prometheus_process_collector).
-define(LIBNAME, prometheus_process_collector).
-define(START_TIME_KEY, {?MODULE, start_time_seconds}).

-define(METRICS, [
    {process_open_fds, gauge, "Number of open file descriptors."},
    {process_max_fds, gauge, "Maximum number of open file descriptors."},
    {process_start_time_seconds, gauge, "Start time of the process since unix epoch in seconds."},
    {process_uptime_seconds, counter, "Process uptime in seconds."},
    {process_threads_total, gauge, "Process Threads count."},
    {process_virtual_memory_bytes, gauge, "Virtual memory size in bytes."},
    {process_resident_memory_bytes, gauge, "Resident memory size in bytes."},
    {process_cpu_seconds_total, counter, "Process CPU seconds total.", fun(Info) ->
        prometheus_model_helpers:counter_metrics([
            {[{kind, utime}], proplists:get_value(process_utime_seconds, Info)},
            {[{kind, stime}], proplists:get_value(process_stime_seconds, Info)}
        ])
    end},
    {process_max_resident_memory_bytes, gauge, "Maximum resident set size used."},
    {process_noio_pagefaults_total, counter,
        "Number of page faules serviced without any I/O activity."},
    {process_io_pagefaults_total, counter,
        "Number of page faults serviced that required I/O activity."},
    {process_swaps_total, counter, "Number of times a process was \"swapped\" out of main memory."},
    {process_disk_reads_total, counter, "Number of times the file system had to perform input."},
    {process_disk_writes_total, counter, "Number of times the file system had to perform output."},
    {process_signals_delivered_total, counter, "Number of signals delivered."},
    {process_voluntary_context_switches_total, counter,
        "Number of times a context switch resulted due to a "
        "process voluntarily giving up the processor."},
    {process_involuntary_context_switches_total, counter,
        "Number of times a context switch resulted due to a "
        "higher priority process becoming runnable or because the "
        "current process exceeded its time slice."}
]).

%%====================================================================
%% Collector API
%%====================================================================

-doc "Deregister collector. No cleanup logic needed.".
-spec deregister_cleanup(Registry) -> ok when
    Registry :: prometheus_registry:registry().
deregister_cleanup(_) ->
    ok.

-doc "Calls `Callback` for each `MetricFamily` of this collector".
-spec collect_mf(Registry, Callback) -> ok when
    Registry :: prometheus_registry:registry(),
    Callback :: prometheus_collector:collect_mf_callback().
collect_mf(_Registry, Callback) ->
    case os:type() of
        {unix, linux} -> collect_mf_linux(Callback);
        {unix, _} -> collect_mf_nif(Callback)
    end.

-doc "Returns Metric list for each MetricFamily identified by `Name`.".
-spec collect_metrics(Name, Data) -> Metrics when
    Name :: prometheus_metric:name(),
    Data :: prometheus_collector:data(),
    Metrics :: prometheus_model:'Metric'() | [prometheus_model:'Metric'()].
collect_metrics(_, {Fun, Proplist}) ->
    Fun(Proplist).

-doc "NIF-backed callback. Returns rusage data on Linux, full process info on BSD/macOS.".
-spec get_process_info() -> {ok, proplists:proplist()} | {error, atom()}.
get_process_info() ->
    erlang:nif_error("NIF library not loaded").

%%====================================================================
%% Private Parts
%%====================================================================

collect_mf_linux(Callback) ->
    Rusage =
        case get_process_info() of
            {ok, R} ->
                R;
            {error, Reason} ->
                logger:warning(
                    "prometheus_process_collector: getrusage NIF failed: ~p", [Reason]
                ),
                []
        end,
    emit_metrics(Callback, read_proc_metrics() ++ Rusage).

collect_mf_nif(Callback) ->
    case get_process_info() of
        {ok, Sources} ->
            emit_metrics(Callback, Sources);
        {error, Reason} ->
            logger:warning(
                "prometheus_process_collector: NIF failed: ~p", [Reason]
            ),
            ok
    end.

emit_metrics(Callback, Sources) ->
    StartTime = persistent_term:get(?START_TIME_KEY),
    ProcessInfo =
        [
            {process_start_time_seconds, StartTime},
            {process_uptime_seconds, os:system_time(second) - StartTime}
            | Sources
        ],
    [mf(Callback, M, ProcessInfo) || M <- ?METRICS, has_required_keys(M, ProcessInfo)],
    ok.

has_required_keys({process_cpu_seconds_total, _, _, _}, Info) ->
    proplists:get_value(process_utime_seconds, Info) =/= undefined andalso
        proplists:get_value(process_stime_seconds, Info) =/= undefined;
has_required_keys({Key, _, _}, Info) ->
    proplists:get_value(Key, Info) =/= undefined.

mf(Callback, Metric, Proplist) ->
    {Name, Type, Help, Fun} =
        case Metric of
            {Key, Type1, Help1} ->
                {Key, Type1, Help1, fun(Proplist1) ->
                    metric(Type1, [], proplists:get_value(Key, Proplist1))
                end};
            {Key, Type1, Help1, Fun1} ->
                {Key, Type1, Help1, Fun1}
        end,
    Callback(prometheus_model_helpers:create_mf(Name, Help, Type, ?MODULE, {Fun, Proplist})).

metric(counter, Labels, Value) ->
    prometheus_model_helpers:counter_metric(Labels, Value);
metric(gauge, Labels, Value) ->
    prometheus_model_helpers:gauge_metric(Labels, Value).

%%--------------------------------------------------------------------
%% Linux /proc readers
%%--------------------------------------------------------------------

read_proc_metrics() ->
    {ok, StatusBin} = file:read_file("/proc/self/status"),
    {ok, LimitsBin} = file:read_file("/proc/self/limits"),
    {ok, FdList} = file:list_dir("/proc/self/fd"),
    Status = parse_status(StatusBin),
    MaxFds =
        case parse_limits(LimitsBin) of
            unlimited -> undefined;
            N when is_integer(N) -> N
        end,
    [
        {process_open_fds, length(FdList)},
        {process_max_fds, MaxFds},
        {process_threads_total, parse_int(maps:get(<<"Threads">>, Status, <<>>))},
        {process_virtual_memory_bytes, parse_kb(maps:get(<<"VmSize">>, Status, <<>>))},
        {process_resident_memory_bytes, parse_kb(maps:get(<<"VmRSS">>, Status, <<>>))}
    ].

parse_status(Bin) ->
    Lines = binary:split(Bin, <<"\n">>, [global, trim_all]),
    lists:foldl(
        fun(Line, Acc) ->
            case binary:split(Line, <<":">>) of
                [K, V] ->
                    Acc#{string:trim(K) => string:trim(V)};
                _ ->
                    Acc
            end
        end,
        #{},
        Lines
    ).

parse_limits(Bin) ->
    case
        re:run(Bin, <<"^Max open files\\s+(\\S+)\\s">>, [
            multiline, {capture, [1], binary}
        ])
    of
        {match, [<<"unlimited">>]} ->
            unlimited;
        {match, [SoftStr]} ->
            binary_to_integer(SoftStr);
        nomatch ->
            unlimited
    end.

parse_kb(<<>>) ->
    undefined;
parse_kb(Bin) ->
    case re:run(Bin, <<"^\\s*(\\d+)\\s*kB">>, [{capture, [1], binary}]) of
        {match, [N]} -> binary_to_integer(N) * 1024;
        nomatch -> undefined
    end.

parse_int(<<>>) ->
    undefined;
parse_int(Bin) ->
    case string:to_integer(string:trim(Bin)) of
        {N, _} when is_integer(N) -> N;
        {error, _} -> undefined
    end.

%%--------------------------------------------------------------------
%% NIF loader; caches BEAM start time before load.
%%--------------------------------------------------------------------

init() ->
    StartNative = erlang:system_info(start_time) + erlang:time_offset(),
    StartSec = erlang:convert_time_unit(StartNative, native, second),
    persistent_term:put(?START_TIME_KEY, StartSec),
    SoName =
        case code:priv_dir(?APPNAME) of
            {error, bad_name} ->
                case filelib:is_dir(filename:join(["..", priv])) of
                    true ->
                        filename:join(["..", priv, ?LIBNAME]);
                    _ ->
                        filename:join([priv, ?LIBNAME])
                end;
            Dir ->
                filename:join(Dir, ?LIBNAME)
        end,
    erlang:load_nif(SoName, 0).
