# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "fluent-plugin-watch-process"
  s.version     = "0.1.1"
  s.authors     = ["Kentaro Yoshida"]
  s.email       = ["y.ken.studio@gmail.com"]
  s.homepage    = "https://github.com/y-ken/fluent-plugin-watch-process"
  s.summary     = %q{Fluentd Input plugin to collect continual process information via ps command. It is useful for cron/barch process monitoring.}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies:
  s.add_development_dependency "rake"
  s.add_development_dependency "test-unit", ">= 3.1.0"
  s.add_development_dependency "appraisal"
  s.add_runtime_dependency "fluentd", [">= 0.14.0", "< 2"]
  s.add_runtime_dependency "fluent-mixin-rewrite-tag-name"
  s.add_runtime_dependency "fluent-mixin-type-converter", ">= 0.1.0"
end
