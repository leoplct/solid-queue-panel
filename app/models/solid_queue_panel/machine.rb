# frozen_string_literal: true

require "etc"
require "socket"

module SolidQueuePanel
  # Reads how much memory and CPU the current process and the machine it runs on
  # are using, without a native extension: /proc and the cgroup on Linux, sysctl
  # and ps on macOS, and nil everywhere else rather than a wrong number.
  #
  # Inside a container the cgroup limits are what matters, not the size of the
  # host, so they win whenever they are set.
  class Machine
    UNLIMITED = 2**62

    def hostname
      @hostname ||= Socket.gethostname
    end

    # Resident memory of this process, the figure to multiply by the number of
    # processes when sizing a machine.
    def rss_kb
      linux? ? rss_kb_from_proc : rss_kb_from_ps
    end

    # Cores this process is actually allowed to use, which in a container is the
    # CPU quota rather than the number of cores of the host.
    def cpu_count
      @cpu_count ||= cgroup_cpu_limit || Etc.nprocessors
    end

    def load_average
      if linux?
        read_file("/proc/loadavg")&.split&.first&.to_f
      else
        read_command("sysctl -n vm.loadavg")&.scan(/[\d.]+/)&.first&.to_f
      end
    end

    # Total memory available to the processes: the cgroup limit when there is
    # one, the machine's memory otherwise.
    def memory_kb
      @memory_kb ||= cgroup_memory_limit_kb || total_memory_kb
    end

    def available_memory_kb
      cgroup_available_memory_kb || system_available_memory_kb
    end

    def process_cpu_time
      Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
    end

    def self.thread_cpu_time
      Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
    rescue NameError, Errno::EINVAL
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    private
      def linux?
        return @linux if defined?(@linux)

        @linux = File.exist?("/proc/self/statm")
      end

      def rss_kb_from_proc
        resident_pages = read_file("/proc/self/statm")&.split&.at(1).to_i

        resident_pages * page_size_kb
      end

      def rss_kb_from_ps
        read_command("ps -o rss= -p #{Process.pid}")&.strip.to_i
      end

      DEFAULT_PAGE_SIZE = 4096
      private_constant :DEFAULT_PAGE_SIZE

      def page_size_kb
        @page_size_kb ||= begin
          Etc.sysconf(Etc::SC_PAGESIZE)
        rescue StandardError
          DEFAULT_PAGE_SIZE
        end / 1024
      end

      def total_memory_kb
        if linux?
          meminfo("MemTotal")
        else
          bytes = read_command("sysctl -n hw.memsize").to_i
          bytes.positive? ? bytes / 1024 : nil
        end
      end

      def system_available_memory_kb
        linux? ? meminfo("MemAvailable") : available_memory_kb_from_vm_stat
      end

      def meminfo(key)
        contents = read_file("/proc/meminfo")
        return unless contents

        contents[/^#{key}:\s+(\d+) kB/, 1]&.to_i
      end

      def available_memory_kb_from_vm_stat
        output = read_command("vm_stat")
        return unless output

        page_size = output[/page size of (\d+) bytes/, 1].to_i
        return if page_size.zero?

        free_pages = %w[free inactive speculative].sum do |kind|
          output[/^Pages #{kind}:\s+(\d+)\./, 1].to_i
        end

        free_pages * page_size / 1024
      end

      def cgroup_memory_limit_kb
        limit = read_cgroup_number("/sys/fs/cgroup/memory.max") ||
                read_cgroup_number("/sys/fs/cgroup/memory/memory.limit_in_bytes")

        limit / 1024 if limit&.positive? && limit < UNLIMITED
      end

      def cgroup_available_memory_kb
        limit = cgroup_memory_limit_kb
        return unless limit

        used = read_cgroup_number("/sys/fs/cgroup/memory.current") ||
               read_cgroup_number("/sys/fs/cgroup/memory/memory.usage_in_bytes")
        return unless used

        [ limit - (used / 1024), 0 ].max
      end

      def cgroup_cpu_limit
        if (quota = read_file("/sys/fs/cgroup/cpu.max"))
          maximum, period = quota.split
          return if maximum == "max"

          return (maximum.to_f / period.to_f).ceil
        end

        quota = read_cgroup_number("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")
        period = read_cgroup_number("/sys/fs/cgroup/cpu/cpu.cfs_period_us")
        return unless quota&.positive? && period&.positive?

        (quota.to_f / period).ceil
      end

      def read_cgroup_number(path)
        value = read_file(path)
        return if value.nil? || value.strip == "max"

        value.to_i
      end

      def read_file(path)
        File.read(path)
      rescue SystemCallError, IOError
        nil
      end

      def read_command(command)
        `#{command} 2>/dev/null`
      rescue StandardError
        nil
      end
  end
end
