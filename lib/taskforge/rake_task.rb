# frozen_string_literal: true

# Rake-интеграция: задача, запускающая тяжёлые команды параллельно
# через Taskforge. Подключается в ЛЮБОМ проекте:
#
#   # Rakefile
#   require "taskforge/rake_task"
#
#   Taskforge::RakeTask.new(:build_all) do |t|
#     t.job "rake build:web"
#     t.job "rake build:api"
#   end
#
# Воркеров можно форсировать: TASKFORGE_JOBS=N (иначе адаптивно — из
# ядер и свободной RAM).

require "rake"
require_relative "../taskforge"

module Taskforge
  class RakeTask
    include Rake::DSL

    attr_accessor :name, :description, :dir

    def initialize(name = :forge)
      @name = name
      @description = "Run heavy commands in parallel through Taskforge"
      @dir = Dir.pwd
      @commands = []
      yield self if block_given?
      define_task
    end

    # Одна команда (shell-строка).
    def job(command)
      @commands << command
    end

    private

    def define_task
      desc @description
      task(@name) do
        Taskforge.run(@commands, @dir)
      end
    end
  end
end
