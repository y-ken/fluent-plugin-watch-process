require 'helper'

class WatchProcessInputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    tag          input.watch_process
    lookup_user  apache, mycron
  ]

  def create_driver(conf=CONFIG,tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::WatchProcessInput, tag).configure(conf)
  end

  def test_configure
    assert_raise(Fluent::ConfigError) {
      d = create_driver('')
    }
    d = create_driver %[
      tag          input.watch_process
      lookup_user  apache, mycron
    ]
    d.instance.inspect
    assert_equal 'input.watch_process', d.instance.tag
    assert_equal ['apache', 'mycron'], d.instance.lookup_user
  end
end

