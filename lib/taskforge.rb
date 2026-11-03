# frozen_string_literal: true

module Taskforge
  # Запуск тяжёлых команд параллельно. Точка входа — массив строк
  # (Dir.pwd по умолчанию) или DSL-блок с опциональной директорией:
  #
  #   Taskforge.run ["rake build:web", "rake build:api"]
  #   Taskforge.run "single command"
  #
  #   Taskforge.run do
  #     job "rake build:web"
  #     job "rake build:api"
  #   end
  #
  #   Taskforge.run "path/to/proj" do
  #     job "rake build:web"
  #   end
  def self.run(commands_or_dir = nil, dir = nil, &block)
    if block
      dir = commands_or_dir || dir || Dir.pwd
      dsl = Dsl.new
      dsl.instance_eval(&block)
      commands = dsl.commands
    else
      commands = commands_or_dir
      commands = [commands] if commands.is_a?(String)
    end
    Pool.new(dir || Dir.pwd, commands || []).run
  end

  # DSL-накопитель команд для блока Taskforge.run: блок исполняется
  # через instance_eval, поэтому job вызывается без параметра блока.
  class Dsl
    attr_reader :commands

    def initialize
      @commands = []
    end

    # Одна команда (shell-строка).
    def job(command)
      @commands << command
      nil
    end
  end
end

require_relative "taskforge/version"
require_relative "taskforge/pool"
