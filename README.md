fluent-plugin-watch-process [![Build Status](https://travis-ci.org/y-ken/fluent-plugin-watch-process.png?branch=master)](https://travis-ci.org/y-ken/fluent-plugin-watch-process)
=====================

## Overview

Fluentd Input plugin to collect process information via ps command.

## Use Cases

* collect cron/batch process for analysis.
  * high cpu load time
  * high usage of memory
  * overview running a task over time

## Installation

install with gem or fluent-gem command as:

```
# for fluentd
$ gem install fluent-plugin-watch-process

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-watch-process
```

## TODO

patches welcome!

## Copyright

Copyright © 2013- Kentaro Yoshida (@yoshi_ken)

## License

Apache License, Version 2.0
