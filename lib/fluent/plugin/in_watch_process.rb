require 'time'
require "fluent/plugin/input"
require 'fluent/mixin/rewrite_tag_name'
require 'fluent/mixin/type_converter'

module Fluent::Plugin
  class WatchProcessInput < Fluent::Plugin::Input
    Fluent::Plugin.register_input('watch_process', self)

    helpers :timer

    DEFAULT_KEYS = %w(start_time user pid parent_pid cpu_time cpu_percent memory_percent mem_rss mem_size state proc_name command)
    DEFAULT_TYPES = "pid:integer,parent_pid:integer,cpu_percent:float,memory_percent:float,mem_rss:integer,mem_size:integer"

    config_param :tag, :string
    config_param :command, :string, :default => nil
    config_param :keys, :array, :default => DEFAULT_KEYS
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

      @command = @command || get_ps_command
      log.info "watch_process: polling start. :tag=>#{@tag} :lookup_user=>#{@lookup_user} :interval=>#{@interval} :command=>#{@command}"
    end

    def start
      super
      timer_execute(:in_watch_process, @interval, &method(:on_timer))
    end

    def shutdown
      super
    end

    def on_timer
      io = IO.popen(@command, 'r')
      io.gets
      while result = io.gets
        keys_size = @keys.size
        if result =~ /(?<lstart>(^\w+\s+\w+\s+\d+\s+\d\d:\d\d:\d\d \d+))/
          lstart = Time.parse($~[:lstart])
          result = result.sub($~[:lstart], '')
          keys_size -= 1
        end
        values = [lstart.to_s, result.chomp.strip.split(/\s+/, keys_size)]
        data = Hash[@keys.zip(values.reject(&:empty?).flatten)]
        data['elapsed_time'] = (Time.now - Time.parse(data['start_time'])).to_i if data['start_time']
        next unless @lookup_user.nil? || @lookup_user.include?(data['user'])
        emit_tag = tag.dup
        filter_record(emit_tag, Fluent::Engine.now, data)
        router.emit(emit_tag, Fluent::Engine.now, data)
      end
      io.close
    rescue StandardError => e
      log.error "watch_process: error has occured. #{e.message}"
    end

    def get_ps_command
      if OS.linux?
        "LANG=en_US.UTF-8 && ps -ewwo lstart,user:20,pid,ppid,time,%cpu,%mem,rss,sz,s,comm,cmd"
      elsif OS.mac?
        "LANG=en_US.UTF-8 && ps -ewwo lstart,user,pid,ppid,time,%cpu,%mem,rss,vsz,state,comm,command"
      end
    end

    module OS
      # ref. http://stackoverflow.com/questions/170956/how-can-i-find-which-operating-system-my-ruby-program-is-running-on
      def OS.windows?
        (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
      end

      def OS.mac?
       (/darwin/ =~ RUBY_PLATFORM) != nil
      end

      def OS.unix?
        !OS.windows?
      end

      def OS.linux?
        OS.unix? and not OS.mac?
      end
    end
  end
end
