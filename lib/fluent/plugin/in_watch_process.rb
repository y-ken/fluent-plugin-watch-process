require 'time'
require 'csv'
require "fluent/plugin/input"
require 'fluent/mixin/rewrite_tag_name'
require 'fluent/mixin/type_converter'

module Fluent::Plugin
  class WatchProcessInput < Fluent::Plugin::Input
    Fluent::Plugin.register_input('watch_process', self)

    helpers :timer

    config_param :tag, :string
    config_param :command, :string, :default => nil
    config_param :keys, :array, :default => nil
    config_param :interval, :time, :default => '5s'
    config_param :lookup_user, :array, :default => nil
    config_param :hostname_command, :string, :default => 'hostname'

    include Fluent::HandleTagNameMixin
    include Fluent::Mixin::RewriteTagName
    include Fluent::Mixin::TypeConverter

    def initialize
      super
    end

    def configure(conf)
      super

      @watcher = Watcher.get_watcher(@keys, @command)
      log.info "watch_process: polling start. :tag=>#{@tag} :lookup_user=>#{@lookup_user} :interval=>#{@interval} :command=>#{@watcher.command}"
    end

    def start
      super
      timer_execute(:in_watch_process, @interval, &method(:on_timer))
    end

    def shutdown
      super
    end

    def on_timer
      @watcher.process do |data|
        next unless @lookup_user.nil? || @lookup_user.include?(data['user'])
        emit_tag = tag.dup
        filter_record(emit_tag, Fluent::Engine.now, data)
        router.emit(emit_tag, Fluent::Engine.now, data)
      end
    rescue StandardError => e
      log.error "watch_process: error has occured. #{e.message}"
    end

    module Watcher
      def self.get_watcher(keys, command)
        if OS.linux?
          Linux.new(keys, command)
        elsif OS.mac?
          Mac.new(keys, command)
        elsif OS.windows?
          Windows.new(keys, command)
        else
          raise NotImplementedError, "This OS type is not supported."
        end
      end

      class Base
        attr_reader :keys
        attr_reader :command

        def initialize(keys, command)
          @keys = keys
          @command = command
        end

        def parse_line(line)
          raise NotImplementedError, "Need to override #{self.class}##{__method__}."
        end

        def process
          io = open_and_get_io
          begin
            while result = io.gets
              yield parse_line(result)
            end
          ensure
            close_io(io)
          end
        end

        def open_and_get_io
          io = IO.popen(@command, 'r')
          io.gets
          io
        end

        def close_io(io)
          io.close
        end
      end
      private_constant :Base

      class BaseUnixLike < Base
        DEFAULT_KEYS = %w(start_time user pid parent_pid cpu_time cpu_percent memory_percent mem_rss mem_size state proc_name command)
        DEFAULT_TYPES = "pid:integer,parent_pid:integer,cpu_percent:float,memory_percent:float,mem_rss:integer,mem_size:integer"

        def initialize(keys, command)
          super(keys, command)
          @keys = @keys || DEFAULT_KEYS
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
      end
      private_constant :BaseUnixLike

      class Linux < BaseUnixLike
        DEFAULT_COMMAND = "LANG=en_US.UTF-8 && ps -ewwo lstart,user:20,pid,ppid,time,%cpu,%mem,rss,sz,s,comm,cmd"

        def initialize(keys, command)
          super(keys, command)
          @command = @command || DEFAULT_COMMAND
        end
      end

      class Mac < BaseUnixLike
        DEFAULT_COMMAND = "LANG=en_US.UTF-8 && ps -ewwo lstart,user,pid,ppid,time,%cpu,%mem,rss,vsz,state,comm,command"

        def initialize(keys, command)
          super(keys, command)
          @command = @command || DEFAULT_COMMAND
        end
      end

      class Windows < Base
        # Values are from the "System.Diagnostics.Process" object properties that can be taken by the "Get-Process" command.
        # You can check the all properties by the "(Get-Process)[0] | Get-Member" command.
        DEFAULT_PARAMS = {
          "start_time" => "StartTime",
          "user" => "UserName",
          "sid" => "SessionId",
          "pid" => "Id",
          "cpu_second" => "CPU",
          "working_set" => "WorkingSet",
          "virtual_memory_size" => "VirtualMemorySize",
          "handles" => "HandleCount",
          "proc_name" => "ProcessName",
        }
        DEFAULT_TYPES = "sid:integer,pid:integer,cpu_second:float,working_set:integer,virtual_memory_size:integer,handles:integer"

        def initialize(keys, command)
          super(keys, command)
          @keys = @keys || DEFAULT_PARAMS.keys
          @command = @command || default_command
        end

        def parse_line(line)
          values = line.chomp.strip.parse_csv.map { |e| e ? e : "" }
          Hash[@keys.zip(values)]
        end

        def default_command
          command = [
            command_ps,
            pipe_filtering_normal_ps,
            pipe_select_columns,
            pipe_fixing_locale,
            pipe_formatting_output,
          ].join
          "powershell -command \"#{command}\""
        end

        private

        def command_ps
          if @keys.include?("user")
            # The "IncludeUserName" option is needed to get the username, but this option requires Administrator privilege.
            "Get-Process -IncludeUserName"
          else
            "Get-Process"
          end
        end

        def pipe_filtering_normal_ps
          # There are some special processes that don't have some properties, such as the "Idle" process.
          # Normally, these are specific to the system and are not important, so exclude them.
          # Note: The same situation can occur in some processes if there are no Administrator privilege.
          " | ?{$_.StartTime -ne $NULL -and $_.CPU -ne $NULL}"
        end

        def pipe_select_columns
          columns = DEFAULT_PARAMS.keys.map { |key|
            next unless @keys.include?(key)
            DEFAULT_PARAMS[key]
          }.compact

          if columns.nil? || columns.empty?
            raise "The 'keys' parameter is not specified correctly. [keys: #{@keys}]"
          end

          " | Select-Object -Property #{columns.join(',')}"
        end

        def pipe_fixing_locale(format: "ddd MMM dd HH:mm:ss yyyy", locale: "en-US")
          # In Windows, setting the "$env:Lang" environment variable is not effective in changing the format of the output.
          # You can use "Datetime.ToString" method to change format of datetime values in for-each pipe.
          # Note: About "DateTime.ToString" method: https://docs.microsoft.com/en-us/dotnet/api/system.datetime.tostring
          # Note: About "Custom date and time format strings": https://docs.microsoft.com/en-us/dotnet/standard/base-types/custom-date-and-time-format-strings
          " | %{
            $_.StartTime = $_.StartTime.ToString(
              '#{format}',
              [Globalization.CultureInfo]::GetCultureInfo('#{locale}').DateTimeFormat
            ); 
            return $_;
          }"
        end

        def pipe_formatting_output
          # In the "ConvertTo-Csv" command, there are 2 lines of type info and header info at the beginning in the outputs.
          # By the "NoTypeInformation" option, the line of type info is excluded.
          # This enables you to skip the just first line for parsing, like linux or mac.
          " | ConvertTo-Csv -NoTypeInformation"
        end
      end

      module OS
        # ref. http://stackoverflow.com/questions/170956/how-can-i-find-which-operating-system-my-ruby-program-is-running-on
        def self.windows?
          (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
        end

        def self.mac?
         (/darwin/ =~ RUBY_PLATFORM) != nil
        end

        def self.unix?
          !windows?
        end

        def self.linux?
          unix? and not mac?
        end
      end
    end
  end
end
