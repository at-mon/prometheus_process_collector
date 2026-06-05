-module(prometheus_process_collector_tests).

-include_lib("eunit/include/eunit.hrl").

prometheus_format_test_() ->
    {foreach, fun prometheus_eunit_common:start/0, fun prometheus_eunit_common:stop/1, [
        fun test_process_collector/1
    ]}.

darwin_process_open_fds_test_() ->
    case os:type() of
        {unix, darwin} ->
            {"process_open_fds reports the current fd count after the fd table shrinks",
                fun test_darwin_process_open_fds_after_fd_table_shrinks/0};
        _ ->
            []
    end.

test_process_collector(_) ->
    prometheus_registry:register_collector(prometheus_process_collector),
    Metrics = prometheus_text_format:format(),
    [
        ?_assertMatch({match, _}, re:run(Metrics, "process_open_fds [1-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_max_fds [1-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_start_time_seconds [0-9.]{10,}")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_uptime_seconds [1-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_threads_total [1-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_virtual_memory_bytes [1-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_resident_memory_bytes [1-9]")),
        ?_assertMatch(
            {match, _}, re:run(Metrics, "process_cpu_seconds_total{kind=\"(utime|stime)\"} [0-9.]")
        ),
        ?_assertMatch({match, _}, re:run(Metrics, "process_max_resident_memory_bytes [1-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_noio_pagefaults_total [0-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_io_pagefaults_total [0-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_swaps_total [0-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_disk_reads_total [0-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_disk_writes_total [0-9]")),
        ?_assertMatch({match, _}, re:run(Metrics, "process_signals_delivered_total [0-9]")),
        ?_assertMatch(
            {match, _}, re:run(Metrics, "process_voluntary_context_switches_total [0-9]")
        ),
        ?_assertMatch(
            {match, _}, re:run(Metrics, "process_involuntary_context_switches_total [0-9]")
        )
    ].

test_darwin_process_open_fds_after_fd_table_shrinks() ->
    Handles = open_dev_null_files(128),
    try
        OpenFdsWithHandles = process_open_fds(),
        ?assert(OpenFdsWithHandles >= 128)
    after
        [file:close(Handle) || Handle <- Handles]
    end,
    OpenFds = process_open_fds(),
    LsofOpenFds = lsof_open_fd_count(),
    ?assert(
        abs(OpenFds - LsofOpenFds) =< 16,
        #{collector_open_fds => OpenFds, lsof_open_fds => LsofOpenFds}
    ).

open_dev_null_files(Count) ->
    [
        begin
            {ok, Handle} = file:open("/dev/null", [read]),
            Handle
        end
      || _ <- lists:seq(1, Count)
    ].

process_open_fds() ->
    proplists:get_value(process_open_fds, prometheus_process_collector:get_process_info()).

lsof_open_fd_count() ->
    Output = os:cmd("lsof -nP -p " ++ os:getpid() ++ " | tail -n +2 | wc -l"),
    {Count, _Rest} = string:to_integer(string:trim(Output)),
    Count.

parse_status_test_() ->
    Sample =
        <<
            "Name:\tbeam.smp\n"
            "State:\tS (sleeping)\n"
            "Tgid:\t1234\n"
            "VmPeak:\t  234567 kB\n"
            "VmSize:\t  234567 kB\n"
            "VmRSS:\t   12345 kB\n"
            "VmHWM:\t   15000 kB\n"
            "Threads:\t    32\n"
            "voluntary_ctxt_switches:\t100\n"
            "nonvoluntary_ctxt_switches:\t  5\n"
        >>,
    Parsed = prometheus_process_collector:parse_status(Sample),
    [
        ?_assertEqual(<<"beam.smp">>, maps:get(<<"Name">>, Parsed)),
        ?_assertEqual(<<"234567 kB">>, maps:get(<<"VmSize">>, Parsed)),
        ?_assertEqual(<<"12345 kB">>, maps:get(<<"VmRSS">>, Parsed)),
        ?_assertEqual(<<"32">>, maps:get(<<"Threads">>, Parsed)),
        ?_assertEqual(<<"100">>, maps:get(<<"voluntary_ctxt_switches">>, Parsed)),
        ?_assertEqual(error, maps:find(<<"NonExistentField">>, Parsed))
    ].

parse_limits_normal_test() ->
    Sample =
        <<
            "Limit                     Soft Limit           Hard Limit           Units     \n"
            "Max cpu time              unlimited            unlimited            seconds   \n"
            "Max file size             unlimited            unlimited            bytes     \n"
            "Max open files            1024                 524288               files     \n"
            "Max stack size            8388608              unlimited            bytes     \n"
        >>,
    ?assertEqual(1024, prometheus_process_collector:parse_limits(Sample)).

parse_limits_unlimited_test() ->
    Sample =
        <<
            "Limit                     Soft Limit           Hard Limit           Units     \n"
            "Max open files            unlimited            unlimited            files     \n"
        >>,
    ?assertEqual(unlimited, prometheus_process_collector:parse_limits(Sample)).

parse_limits_missing_test() ->
    %% No "Max open files" line at all.
    Sample = <<"Limit Soft Hard Units\nMax cpu time unlimited unlimited seconds\n">>,
    ?assertEqual(unlimited, prometheus_process_collector:parse_limits(Sample)).

parse_kb_test_() ->
    [
        ?_assertEqual(12345 * 1024, prometheus_process_collector:parse_kb(<<"12345 kB">>)),
        ?_assertEqual(12345 * 1024, prometheus_process_collector:parse_kb(<<"  12345 kB">>)),
        ?_assertEqual(undefined, prometheus_process_collector:parse_kb(<<>>)),
        ?_assertEqual(undefined, prometheus_process_collector:parse_kb(<<"not a number">>))
    ].

parse_int_test_() ->
    [
        ?_assertEqual(32, prometheus_process_collector:parse_int(<<"32">>)),
        ?_assertEqual(32, prometheus_process_collector:parse_int(<<"  32  ">>)),
        ?_assertEqual(undefined, prometheus_process_collector:parse_int(<<>>)),
        ?_assertEqual(undefined, prometheus_process_collector:parse_int(<<"abc">>))
    ].
