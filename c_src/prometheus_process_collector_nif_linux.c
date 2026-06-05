#include "erl_nif.h"
#include <errno.h>
#include <sys/resource.h>
#include <sys/time.h>

static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_efault;
static ERL_NIF_TERM atom_einval;
static ERL_NIF_TERM atom_unknown;
static ERL_NIF_TERM atom_process_utime_seconds;
static ERL_NIF_TERM atom_process_stime_seconds;
static ERL_NIF_TERM atom_process_max_resident_memory_bytes;
static ERL_NIF_TERM atom_process_noio_pagefaults_total;
static ERL_NIF_TERM atom_process_io_pagefaults_total;
static ERL_NIF_TERM atom_process_swaps_total;
static ERL_NIF_TERM atom_process_disk_reads_total;
static ERL_NIF_TERM atom_process_disk_writes_total;
static ERL_NIF_TERM atom_process_signals_delivered_total;
static ERL_NIF_TERM atom_process_voluntary_context_switches_total;
static ERL_NIF_TERM atom_process_involuntary_context_switches_total;

static ERL_NIF_TERM errno_to_atom(int e)
{
    switch (e) {
        case EFAULT: return atom_efault;
        case EINVAL: return atom_einval;
        default:     return atom_unknown;
    }
}

static ERL_NIF_TERM get_process_info(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    struct rusage ru;
    ERL_NIF_TERM plist[11];
    double utime, stime;

    (void)argc;
    (void)argv;

    if (getrusage(RUSAGE_SELF, &ru) != 0) {
        return enif_make_tuple2(env, atom_error, errno_to_atom(errno));
    }

    utime = (double)ru.ru_utime.tv_sec + (double)ru.ru_utime.tv_usec / 1000000.0;
    stime = (double)ru.ru_stime.tv_sec + (double)ru.ru_stime.tv_usec / 1000000.0;

    plist[0]  = enif_make_tuple2(env, atom_process_utime_seconds,
                                 enif_make_double(env, utime));
    plist[1]  = enif_make_tuple2(env, atom_process_stime_seconds,
                                 enif_make_double(env, stime));
    plist[2]  = enif_make_tuple2(env, atom_process_max_resident_memory_bytes,
                                 enif_make_long(env, ru.ru_maxrss * 1024L));
    plist[3]  = enif_make_tuple2(env, atom_process_noio_pagefaults_total,
                                 enif_make_long(env, ru.ru_minflt));
    plist[4]  = enif_make_tuple2(env, atom_process_io_pagefaults_total,
                                 enif_make_long(env, ru.ru_majflt));
    plist[5]  = enif_make_tuple2(env, atom_process_swaps_total,
                                 enif_make_long(env, ru.ru_nswap));
    plist[6]  = enif_make_tuple2(env, atom_process_disk_reads_total,
                                 enif_make_long(env, ru.ru_inblock));
    plist[7]  = enif_make_tuple2(env, atom_process_disk_writes_total,
                                 enif_make_long(env, ru.ru_oublock));
    plist[8]  = enif_make_tuple2(env, atom_process_signals_delivered_total,
                                 enif_make_long(env, ru.ru_nsignals));
    plist[9]  = enif_make_tuple2(env, atom_process_voluntary_context_switches_total,
                                 enif_make_long(env, ru.ru_nvcsw));
    plist[10] = enif_make_tuple2(env, atom_process_involuntary_context_switches_total,
                                 enif_make_long(env, ru.ru_nivcsw));

    return enif_make_tuple2(env, atom_ok,
                            enif_make_list_from_array(env, plist, 11));
}

static int on_load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info)
{
    (void)priv_data;
    (void)load_info;

    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");
    atom_efault = enif_make_atom(env, "efault");
    atom_einval = enif_make_atom(env, "einval");
    atom_unknown = enif_make_atom(env, "unknown");
    atom_process_utime_seconds =
        enif_make_atom(env, "process_utime_seconds");
    atom_process_stime_seconds =
        enif_make_atom(env, "process_stime_seconds");
    atom_process_max_resident_memory_bytes =
        enif_make_atom(env, "process_max_resident_memory_bytes");
    atom_process_noio_pagefaults_total =
        enif_make_atom(env, "process_noio_pagefaults_total");
    atom_process_io_pagefaults_total =
        enif_make_atom(env, "process_io_pagefaults_total");
    atom_process_swaps_total =
        enif_make_atom(env, "process_swaps_total");
    atom_process_disk_reads_total =
        enif_make_atom(env, "process_disk_reads_total");
    atom_process_disk_writes_total =
        enif_make_atom(env, "process_disk_writes_total");
    atom_process_signals_delivered_total =
        enif_make_atom(env, "process_signals_delivered_total");
    atom_process_voluntary_context_switches_total =
        enif_make_atom(env, "process_voluntary_context_switches_total");
    atom_process_involuntary_context_switches_total =
        enif_make_atom(env, "process_involuntary_context_switches_total");
    return 0;
}

static ErlNifFunc nif_funcs[] = {
    {"get_process_info", 0, get_process_info}
};

ERL_NIF_INIT(prometheus_process_collector, nif_funcs, &on_load, NULL, NULL, NULL)
