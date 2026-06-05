#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <sys/sysctl.h>
#include <sys/user.h>

#ifdef __APPLE__
#include <libproc.h>
#include <sys/proc_info.h>
#endif

#define UNUSED(x) (void)(x)

struct prometheus_process_info
{
  int fds_total;
  rlim_t fds_limit;
  time_t start_time_seconds;
  long uptime_seconds;
  int threads_total;
  unsigned long vm_bytes;
  unsigned long rm_bytes;
  double utime_seconds;
  double stime_seconds;
  long max_rm_bytes;
  long noio_pagefaults_total;
  long io_pagefaults_total;
  long swaps_total;
  long disk_reads_total;
  long disk_writes_total;
  long signals_delivered_total;
  long voluntary_context_switches_total;
  long involuntary_context_switches_total;
};

#define PROCESS_INFO_COUNT 16

int fill_prometheus_process_info(pid_t pid, struct prometheus_process_info *prometheus_process_info);