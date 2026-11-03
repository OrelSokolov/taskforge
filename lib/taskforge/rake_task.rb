# frozen_string_literal: true

# Rake-интеграция: задача, запускающая тяжёлые команды параллельно
# через Taskforge::Pool. Подключается в ЛЮБОМ проекте:
#
#   # Rakefile
#   require "taskforge/rake_task"
#
#   Taskforge::RakeTask.new(:build_all) do |t|
#     t.description = "Build every binary in parallel"
#     t.commands = ["rake build:web", "rake build:api", "rake build:cli"]
#   end
#
# Воркеров можно форсировать: TASKFORGE_JOBS=N (иначе адаптивно — из
# ядер и свободной RAM).

require "rake"
require_relative "pool"

module Taskforge
  class RakeTask
    include Rake::DSL

    attr_accessor :name, :description, :commands, :dir

    def initialize(name = :forge)
      @name = name
      @description = "Run heavy commands in parallel through Taskforge::Pool"
      @commands = []
      @dir = Dir.pwd
      yield self if block_given?
      define_task
    end

    private

    def define_task
      desc @description
      task(@name) do
        jobs = @commands.map { |cmd| Pool::Job.new(cmd, cmd) }
        Pool.new(@dir, jobs).run
      end
    end
  end
end
