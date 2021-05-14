require 'time'
require "fluent/plugin/input"
require 'fluent/mixin/rewrite_tag_name'
require 'fluent/mixin/type_converter'

module Fluent::Plugin
  class WatchProcessInput < Fluent::Plugin::Input
    Fluent::Plugin.register_input('watch_process', self)

    helpers :timer

    DEFAULT_TYPES = "pid:integer,parent_pid:integer,cpu_percent:float,memory_percent:float,mem_rss:integer,mem_size:integer"

    config_param :tag, :string
    config_param :command, :string, :default => nil
    config_param :keys, :array, :default => nil
    config_param :interval, :time, :default => '5s'
    config_param :lookup_user, :array, :default => nil
    config_param :hostname_command, :string, :default => 'hostname'

    include Fluent::HandleTagNameMixin
    include Fluent::Mixin::RewriteTagName
    include Fluent::Mixin::TypeConverter
    config_set_default :types, DEFAULT_TYPES

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
