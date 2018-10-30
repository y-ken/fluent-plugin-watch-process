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

  def test_emit
    whoami = `whoami`
    d = create_driver %[
      tag          input.watch_process
      lookup_user  #{whoami}
      interval 1s
    ]
    d.run(expect_emits: 1, timeout: 3)
    assert(d.events.size > 1)
  end
end
