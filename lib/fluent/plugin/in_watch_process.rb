require 'time'
require 'csv' if Fluent.windows?
require "fluent/plugin/input"
require 'fluent/mixin/rewrite_tag_name'
require 'fluent/mixin/type_converter'

module Fluent::Plugin
  class WatchProcessInput < Fluent::Plugin::Input
    Fluent::Plugin.register_input('watch_process', self)

    helpers :timer

    DEFAULT_KEYS = %w(start_time user pid parent_pid cpu_time cpu_percent memory_percent mem_rss mem_size state proc_name command)
    DEFAULT_TYPES = %w(
      pid:integer
      parent_pid:integer
      cpu_percent:float
      memory_percent:float
      mem_rss:integer
      mem_size:integer
    ).join(",")

    config_param :tag, :string
    config_param :command, :string, :default => nil
    config_param :keys, :array, :default => nil
    config_param :interval, :time, :default => '5s'
    config_param :lookup_user, :array, :default => nil
    config_param :hostname_command, :string, :default => 'hostname'
    config_param :powershell_command, :enum, list: [:powershell, :pwsh], :default => :powershell

    include Fluent::HandleTagNameMixin
    include Fluent::Mixin::RewriteTagName
    include Fluent::Mixin::TypeConverter

    def initialize
      super
    end

    def configure(conf)
      super

      @windows_watcher = WindowsWatcher.new(@keys, @command, @lookup_user, @powershell_command) if Fluent.windows?
      @keys ||= Fluent.windows? ? @windows_watcher.keys : DEFAULT_KEYS
      @command ||= get_ps_command
      apply_default_types
      log.info "watch_process: polling start. :tag=>#{@tag} :lookup_user=>#{@lookup_user} :interval=>#{@interval} :command=>#{@command}"
    end

    def start
      super
      timer_execute(:in_watch_process, @interval, &method(:on_timer))
    end

    def shutdown
      super
    end

    def apply_default_types
      return unless @types.nil?
      @types = Fluent.windows? ? @windows_watcher.default_types : DEFAULT_TYPES
      @type_converters = parse_types_parameter unless @types.nil?
    end

    def on_timer
      io = IO.popen(@command, 'r')
      begin
        io.gets
        while result = io.gets
          if Fluent.windows?
            data = @windows_watcher.parse_line(result)
            next unless @windows_watcher.match_look_up_user?(data)
          else
            data = parse_line(result)
            next unless match_look_up_user?(data)
          end
          emit_tag = tag.dup
          filter_record(emit_tag, Fluent::Engine.now, data)
          router.emit(emit_tag, Fluent::Engine.now, data)
        end
      ensure
        io.close
      end
    rescue StandardError => e
      log.error "watch_process: error has occured. #{e.message}"
    end

    def parse_line(line)
      keys_size = @keys.size
      if line =~ /(?<lstart>(^\w+\s+\w+\s+\d+\s+\d\d:\d\d:\d\d \d+))/
        lstart = Time.parse($~[:lstart])
        line = line.sub($~[:lstart], '')
        keys_size -= 1
      end
      values = [lstart.to_s, line.chomp.strip.split(/\s+/, keys_size)]
      data = Hash[@keys.zip(values.reject(&:empty?).flatten)]
      data['elapsed_time'] = (Time.now - Time.parse(data['start_time'])).to_i if data['start_time']
      data
    end

    def match_look_up_user?(data)
      return true if @lookup_user.nil?

      @lookup_user.include?(data['user'])
    end

    def get_ps_command
      if mac?
        "LANG=en_US.UTF-8 && ps -ewwo lstart,user,pid,ppid,time,%cpu,%mem,rss,vsz,state,comm,command"
      elsif Fluent.windows?
        @windows_watcher.command
      else
        "LANG=en_US.UTF-8 && ps -ewwo lstart,user:20,pid,ppid,time,%cpu,%mem,rss,sz,s,comm,cmd"
      end
    end

    def mac?
      (/darwin/ =~ RUBY_PLATFORM) != nil
    end

    class WindowsWatcher
      # Keys are from the "System.Diagnostics.Process" object properties that can be taken by the "Get-Process" command.
      # You can check the all properties by the "(Get-Process)[0] | Get-Member" command.
      DEFAULT_KEYS = %w(StartTime UserName SessionId Id CPU WorkingSet VirtualMemorySize HandleCount ProcessName)

      DEFAULT_TYPES = %w(
        SessionId:integer
        Id:integer
        CPU:float
        WorkingSet:integer
        VirtualMemorySize:integer
        HandleCount:integer
      ).join(",")

      attr_reader :keys
      attr_reader :command

      def initialize(keys, command, lookup_user, powershell_command)
        @keys = keys || DEFAULT_KEYS
        @powershell_command = powershell_command
        @command = command || default_command
        @lookup_user = lookup_user
      end

      def default_types
        DEFAULT_TYPES
      end

      def parse_line(line)
        values = line.chomp.strip.parse_csv.map { |e| e ? e : "" }
        data = Hash[@keys.zip(values)]

        unless data["StartTime"].nil?
          start_time = Time.parse(data['StartTime'])
          data['ElapsedTime'] = (Time.now - start_time).to_i
          data["StartTime"] = start_time.to_s
        end

        data
      end

      def match_look_up_user?(data)
        return true if @lookup_user.nil?

        @lookup_user.include?(data["UserName"])
      end

      def default_command
        command = [
          command_ps,
          pipe_filtering_normal_ps,
          pipe_select_columns,
          pipe_fixing_locale,
          pipe_formatting_output,
        ].join
        "#{@powershell_command} -command \"#{command}\""
      end

      def command_ps
        if @keys.include?("UserName")
          # The "IncludeUserName" option is needed to get the username, but this option requires Administrator privilege.
          "Get-Process -IncludeUserName"
        else
          "Get-Process"
        end
      end

      private

      def pipe_filtering_normal_ps
        # There are some special processes that don't have some properties, such as the "Idle" process.
        # Normally, these are specific to the system and are not important, so exclude them.
        # Note: The same situation can occur in some processes if there are no Administrator privilege.
        " | ?{$_.StartTime -ne $NULL -and $_.CPU -ne $NULL}"
      end

      def pipe_select_columns
        if @keys.nil? || @keys.empty?
          raise "The 'keys' parameter is not specified correctly. [keys: #{@keys}]"
        end

        " | Select-Object -Property #{@keys.join(',')}"
      end

      def pipe_fixing_locale()
        # In Windows, setting the "$env:Lang" environment variable is not effective in changing the format of the output.
        # You can use "Datetime.ToString" method to change format of datetime values in for-each pipe.
        # Note: About "DateTime.ToString" method: https://docs.microsoft.com/en-us/dotnet/api/system.datetime.tostring
        return "" unless @keys.include?("StartTime")

        " | %{$_.StartTime = $_.StartTime.ToString('o'); return $_;}"
      end

      def pipe_formatting_output
        # In the "ConvertTo-Csv" command, there are 2 lines of type info and header info at the beginning in the outputs.
        # By the "NoTypeInformation" option, the line of type info is excluded.
        # This enables you to skip the just first line for parsing, like linux or mac.
        " | ConvertTo-Csv -NoTypeInformation"
      end
    end
  end
end
