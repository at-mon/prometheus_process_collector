#include "prometheus_process_info.h"
#include <cstdio>

namespace Prometheus
{
    static struct proc_taskinfo proc_pidtaskinfo(pid_t pid)
    {
        struct proc_taskinfo pti;
        if (PROC_PIDTASKINFO_SIZE == proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &pti, PROC_PIDTASKINFO_SIZE))
        {
            return pti;
        }
        else
        {
            throw ProcessInfoException();
        }
    }
    
    int ProcessInfo::get_fds_total()
    {
        int buffer_size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
        if (buffer_size < 0)
        {
            throw ProcessInfoException();
        }

        if (buffer_size == 0)
        {
            return 0;
        }

        std::unique_ptr<char[]> fd_info {new char[buffer_size]};
        int used_size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fd_info.get(), buffer_size);
        if (used_size < 0 || used_size % PROC_PIDLISTFD_SIZE != 0)
        {
            throw ProcessInfoException();
        }

        return used_size / PROC_PIDLISTFD_SIZE;
    }

    void ProcessInfo::set_proc_stat()
    {
        const auto &pti = proc_pidtaskinfo(pid);

        threads_total = pti.pti_threadnum;
        vm_bytes = pti.pti_virtual_size;
        rm_bytes = pti.pti_resident_size;
    }
}
