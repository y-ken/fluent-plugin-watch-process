fluent-plugin-watch-process [![Build Status](https://travis-ci.org/y-ken/fluent-plugin-watch-process.png?branch=master)](https://travis-ci.org/y-ken/fluent-plugin-watch-process)
=====================

## Overview

Fluentd Input plugin to collect continual process information via ps command. It is useful for cron/barch process monitoring.

## Use Cases

* collect cron/batch process for long term analysis.
  * high cpu load time
  * high usage of memory
  * determine too long running task

* output destination example
  * Elasticsearch + Kibana to visualize cron/batch process statistics. Example: [example1.conf](https://github.com/y-ken/fluent-plugin-watch-process/blob/master/example1.conf)
  * save process information as audit log into AWS S3 which filename isolated by hostname. Example: [example2.conf](https://github.com/y-ken/fluent-plugin-watch-process/blob/master/example2.conf)

## Installation

install with gem or fluent-gem command as:

```
# for fluentd
$ gem install fluent-plugin-watch-process

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-watch-process -v 0.1.1

# for td-agent2 (recommend)
$ sudo td-agent-gem install fluent-plugin-watch-process -v 0.1.1
```

## Configuration

### Sample

It is a quick sample to output log to `/var/log/td-agent/td-agent.log` with td-agent.

`````
<source>
  @type        watch_process
  tag          debug.batch.${hostname}  # Required
  lookup_user  batchuser                # Optional
  interval     10s                      # Optional (default: 5s)
</source>

<match debug.**>
  @type        stdout
</match>
`````

After restarting td-agent, it will output process information to the td-agent.log like below.

`````
$ tail -f /var/log/td-agent/td-agent.log
...snip...
2014-01-16 14:21:34 +0900 debug.batch.localhost: {"start_time":"2014-01-16 14:21:13 +0900","user":"td-agent","pid":17486,"parent_pid":17483,"cpu_time":"00:00:00","cpu_percent":1.5,"memory_percent":3.5,"mem_rss":36068,"mem_size":60708,"state":"S","proc_name":"ruby","command":"/usr/lib64/fluent/ruby/bin/ruby /usr/sbin/td-agent --group td-agent --log /var/log/td-agent/td-agent.log --daemon /var/run/td-agent/td-agent.pid","elapsed_time":21}
`````

### Syntax

* tag (Required)
  * record output destination
  * supported tag placeholders are `${hostname}` and `__HOSTNAME__`.

* command (Optional)
  * execute ps command with some options
  * [default] Linux: `LANG=en_US.UTF-8 && ps -ewwo lstart,user:20,pid,ppid,time,%cpu,%mem,rss,sz,s,comm,cmd`
  * [default] MacOSX: `LANG=en_US.UTF-8 && ps -ewwo lstart,user,pid,ppid,time,%cpu,%mem,rss,vsz,state,comm,command`
  * [default] Windows: described in the next section, `About Windows`.

* keys (Optional)
  * output record keys of the ps command results
  * [default] Linux, MacOSX: `start_time,user,pid,parent_pid,cpu_time,cpu_percent,memory_percent,mem_rss,mem_size,state,proc_name,command`
    * need to modify `command` too if you modify this value.
  * [default] Windows: `StartTime,UserName,SessionId,Id,CPU,WorkingSet,VirtualMemorySize,HandleCount,ProcessName`
    * in Windows only, you can fix this without fixing `command`. These keys can be specified from the properties of `System.Diagnostics.Process` object of `.NET`.
    * `UserName` key needs administrator privilege. You can exclude this to avoid needing administrator privilege.

* types (Optional)
  * settings of converting types from string to integer/float.
  * [default] Linux, MacOSX: `pid:integer,parent_pid:integer,cpu_percent:float,memory_percent:float,mem_rss:integer,mem_size:integer`
  * [default] Windows: `SessionId:integer,Id:integer,CPU:float,WorkingSet:integer,VirtualMemorySize:integer,HandleCount:integer`

* interval (Optional)
  * execute interval time
  * [default] 5s

* lookup_user (Optional)
  * filter process owner username with comma delimited
  * [default] N/A

* hostname_command (Optional)
  * settings for tag placeholder, `${hostname}` and `__HOSTNAME__`. By default, it using long hostname.
  * to use short hostname, set `hostname -s` for this option on linux/mac.
  * [default] `hostname`

### About Windows

Default `command` in Windows below is complicated, but you can fix `keys` without fixing `command`, unless you specify a key other than the default.

`````powershell
powershell -command "Get-Process -IncludeUserName
 | ?{$_.StartTime -ne $NULL -and $_.CPU -ne $NULL}
 | Select-Object -Property StartTime,UserName,SessionId,Id,CPU,WorkingSet,VirtualMemorySize,HandleCount,ProcessName
 | %{$_.StartTime = $_.StartTime.ToString('o'); return $_;}
 | ConvertTo-Csv -NoTypeInformation"
`````

Here are details of this default command.

* `Get-Process -IncludeUserName`
  * `Get-Process` powershell command takes `System.Diagnostics.Process` objects.
  * `IncludeUserName` option is needed to take `UserName`.
    * this needs administrator privilege.
    * this will be omitted if `keys` does not contain `UserName`.
* ` | ?{$_.StartTime -ne $NULL -and $_.CPU -ne $NULL}`
  * this exlcludes some special processes that don't have some properties, such as the "Idle" process in Windows.
* ` | Select-Object -Property ...`
  * this takes the necessary parameters from `System.Diagnostics.Process` objects.
  * `...` part will be automatically fixed by `keys`.
* ` | %{$_.StartTime = $_.StartTime.ToString('o'); return $_;}`
  * this fixes the format of `StartTime` value.
  * note: in Windows, setting the "$env:Lang" environment variable is not effective in changing the format of the output.
* ` | ConvertTo-Csv -NoTypeInformation`
  * this formats objects to csv strings.
  * currently, it is needed that `command` outputs the results in csv format.
    * this is because white space delimiter is not suitable for Windows, in which empty values are often mixed.

## FAQ

* I need hostname key in the record.  
To add the hostname key in the record, use fluent-plugin-record-reformer together.

## TODO

patches welcome!

## Copyright

Copyright © 2013- Kentaro Yoshida (@yoshi_ken)

## License

Apache License, Version 2.0
