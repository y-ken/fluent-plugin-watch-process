module Fluent
  class WatchProcessInput < Fluent::Input
    Plugin.register_input('watch_process', self)

    config_param :tag, :string
    config_param :command, :string, :default => nil
    config_param :keys, :string, :default => nil
    config_param :types, :string, :default => nil
    config_param :interval, :string, :default => '5s'
    config_param :lookup_user, :string, :default => nil
    config_param :hostname_command, :string, :default => 'hostname'

    Converters = {
      'string' => lambda { |v| v.to_s },
      'integer' => lambda { |v| v.to_i },
      'float' => lambda { |v| v.to_f },
      'bool' => lambda { |v|
        case v.downcase
        when 'true', 'yes', '1'
          true
        else
          false
        end
      },
      'time' => lambda { |v, time_parser|
        time_parser.parse(v)
      },
      'array' => lambda { |v, delimiter|
        v.to_s.split(delimiter)
      }
    }

    def initialize
      super
      require 'time'
    end

    def configure(conf)
      super

      @command = @command || get_ps_command
      @keys = @keys || %w(start_time user pid parent_pid cpu_time cpu_percent memory_percent mem_rss mem_size state proc_name command)
      types = @types || %w(pid:integer parent_pid:integer cpu_percent:float memory_percent:float mem_rss:integer mem_size:integer)
      @types_map = Hash[types.map{|v| v.split(':')}]
      @lookup_user = @lookup_user.gsub(' ', '').split(',') unless @lookup_user.nil?
      @interval = Config.time_value(@interval)
      @hostname = `#{@hostname_command}`.chomp
      $log.info "watch_process: polling start. :tag=>#{@tag} :lookup_user=>#{@lookup_user} :interval=>#{@interval} :command=>#{@command}"
    end

    def start
      @thread = Thread.new(&method(:run))
    end

    def shutdown
      Thread.kill(@thread)
    end

    def run
      loop do
        io = IO.popen(@command, 'r')
        io.gets
        while result = io.gets
          values = result.chomp.strip.split(/\s+/, @keys.size + 4)
          time = Time.parse(values[0...5].join(' '))
          data = Hash[
            @keys.zip([time.to_s, values.values_at(5..15)].flatten).map do |k,v|
              v = Converters[@types_map[k]].call(v) if @types_map.include?(k)
              [k,v]
            end
          ]
          data['elapsed_time'] = (Time.now - Time.parse(data['start_time'])).to_i
          next unless @lookup_user.nil? || @lookup_user.include?(data['user'])
          tag = @tag.gsub(/(\${[a-z]+}|__[A-Z]+__)/, get_placeholder)
          Engine.emit(tag, Engine.now, data)
        end
        io.close
        sleep @interval
      end
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

    def get_placeholder
      return {
        '__HOSTNAME__' => @hostname,
        '${hostname}' => @hostname,
      }
    end    
  end
end
