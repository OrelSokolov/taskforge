# frozen_string_literal: true

require_relative "lib/taskforge/version"

Gem::Specification.new do |spec|
  spec.name = "taskforge"
  spec.version = Taskforge::VERSION
  spec.authors = ["Oleg Sokolov"]
  spec.summary = "Memory-aware parallel pool for heavy shell tasks (rake/crystal builds)"
  spec.description = "Taskforge runs heavy shell tasks (rake build:..., crystal build, ...) " \
                     "in parallel as subprocesses, sizing the worker pool from cores, " \
                     "MemAvailable and a measured peak RSS (warm-up sampling, RAM gate, " \
                     "OOM retry, per-worker CRYSTAL_CACHE_DIR). Ruby port of carat's BuildPool."
  spec.homepage = "https://github.com/OrelSokolov/taskforge"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE exe/taskforge]
  spec.bindir = "exe"
  spec.executables = %w[taskforge]
  spec.require_paths = ["lib"]

  spec.add_dependency "sysmonitor", "~> 0.1"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rake", "~> 13.0"
end
