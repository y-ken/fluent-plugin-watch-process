require 'helper'

class WatchProcessInputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    tag          input.watch_process
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::WatchProcessInput).configure(conf)
  end

  def test_configure
    assert_raise(Fluent::ConfigError) {
      d = create_driver('')
    }
    d = create_driver %[
      tag          input.watch_process
      lookup_user  apache, mycron
    ]
    assert_equal 'input.watch_process', d.instance.tag
    assert_equal ['apache', 'mycron'], d.instance.lookup_user
  end

  def test_unixlike
    omit "Only for UNIX like." if Fluent.windows?
    whoami = `whoami`
    d = create_driver %[
      tag          input.watch_process
      lookup_user  #{whoami}
      interval 1s
    ]
    d.run(expect_emits: 1, timeout: 3)
    assert(d.events.size > 1)
  end

  sub_test_case "Windows" do
    def test_windows_default
      omit "Only for Windows." unless Fluent.windows?
      d = create_driver %[
        tag input.watch_process
        interval 1s
      ]
      default_keys = Fluent::Plugin::WatchProcessInput::WindowsWatcher::DEFAULT_PARAMS.keys

      d.run(expect_records: 1, timeout: 10);

      assert d.events.size > 0

      tag, time, record = d.events[0]

      assert_equal "input.watch_process", tag
      assert time.is_a?(Fluent::EventTime)
      assert_equal default_keys, record.keys
    end

    def test_windows_customized
      omit "Only for Windows." unless Fluent.windows?
      custom_keys = ["handles", "pid", "proc_name"]
      d = create_driver %[
        tag input.watch_process
        interval 1s
        keys #{custom_keys.join(",")}
        types pid:integer
      ]

      d.run(expect_records: 1, timeout: 10);

      assert d.events.size > 0

      tag, time, record = d.events[0]

      assert_equal "input.watch_process", tag
      assert time.is_a?(Fluent::EventTime)
      assert_equal custom_keys, record.keys
      assert record["handles"].is_a?(String)
      assert record["pid"].is_a?(Integer)
    end

    def test_windows_lookup
      omit "Only for Windows." unless Fluent.windows?
      d = create_driver %[
        tag input.watch_process
        interval 1s
      ]
      d.run(expect_records: 1, timeout: 10);

      assert d.events.size > 0

      tag, time, record = d.events[0]
      lookup_user = record["user"]

      d = create_driver %[
        tag input.watch_process
        interval 1s
        lookup_user #{lookup_user}
      ]
      d.run(expect_records: 1, timeout: 10);

      assert d.events.size > 0

      other_user_records = d.events.reject do |tag, time, record|
        lookup_user.include?(record["user"])
      end

      assert other_user_records.size == 0
    end
  end
end
