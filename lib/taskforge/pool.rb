# frozen_string_literal: true

# Taskforge — универсальный запуск тяжёлых задач параллельно: ширина из
# ядер и MemAvailable, замер peak RSS первой задачи на warm-up,
# RAM-гейт очереди, ретрай упавших задач, per-worker CRYSTAL_CACHE_DIR.
# Ruby-порт Carat::BuildPool (carat.cr): вместо фиберов и каналов —
# потоки и Queue; системная информация — гем sysmonitor.

require "fileutils"
require "sysmonitor"

module Taskforge
  # Тяжёлые задачи (например, `rake build:...`) масштабируются ~N по
  # wall-clock (один процесс — фактически одно ядро на кодоген), но
  # каждая задача держит ~1-2 ГБ RAM, поэтому фиксированная ширина пула,
  # подобранная под одну машину, на другой уходит в OOM. Вместо этого
  # ширина выводится из ТЕКУЩЕГО состояния машины (Sysmonitor): ядра
  # ограничивают сверху, MemAvailable / замеренный peak RSS задачи —
  # снизу:
  #
  #   workers = min(ядра, MemAvailable * 0.7 / peak_rss, 8, |jobs|)
  #
  # Peak RSS не угадывается, а измеряется: первая задача греет слот j0
  # кэша компилятора, пока сэмплируется RSS её дерева процессов
  # (sh + rake + crystal + cc); слот затем клонируется в пустые слоты
  # воркеров. Перед выдачей каждого следующего задания гейт перепроверяет
  # MemAvailable и придерживает очередь, когда свободной памяти меньше
  # (peak + запас) — случай «одна задача тяжелее остальных» замедляет
  # пул, а не валит его. Задача, всё-таки умершая от OOM (exit 137 /
  # SIGKILL), после осушения пула ретраится один раз последовательно.
  #
  # Конкурентные компиляторы также гоняются на общем ~/.cache/crystal
  # (tmp-переименования), поэтому каждый воркер получает свой
  # персистентный CRYSTAL_CACHE_DIR: <dir>/.taskforge/cache/jN — он
  # живёт между запусками, второй и дальнейшие прогоны тёплые.
  # TASKFORGE_JOBS=N отключает адаптивный подбор (бенчмарки, A/B).
  class Pool
    class Error < StandardError; end

    MAX_WORKERS = 8
    # Запас свободной RAM ниже наблюдаемого peak RSS (гейт очереди).
    MARGIN_KB = 524_288
    # Пока warm-up не измерил реальный след: ~2 ГБ на release-сборку.
    FALLBACK_PEAK_KB = 2_097_152
    # Пол измеренного peak: крошечная задача не должна раздувать пул до
    # 8 воркеров (она и так выполняется секунды — ширина не важна).
    MIN_PEAK_KB = 262_144

    # Задачи — массив shell-строк, каждая запускается как subprocess
    # (sh -c command). Имя задачи для сообщений = сама команда.
    def initialize(dir, commands, cache_root: nil)
      @dir = File.expand_path(dir)
      @jobs = commands
      @cache_root = cache_root || File.join(@dir, ".taskforge", "cache")
      @peak_kb = FALLBACK_PEAK_KB
      FileUtils.mkdir_p(@cache_root)
    end

    def run
      return if @jobs.empty?

      forced = forced_workers
      workers = (forced || initial_workers).clamp(1, @jobs.size)
      if workers == 1 || @jobs.size == 1
        @jobs.each do |job|
          raise Error, "task failed: #{job}" unless run_one(job, 0)
        end
        return
      end
      warm = @jobs.first
      unless warm_up(warm)
        # не исключён OOM при стартовой оценке — один последовательный ретрай
        raise Error, "task failed: #{warm}" unless run_one(warm, 0)
      end
      workers = (forced || workers_for(@peak_kb)).clamp(1, @jobs.size)
      clone_warm_cache(workers)
      report(workers, forced)
      failures = run_pool(@jobs[1..], workers)
      # ретрай по одному: падение в пуле могло быть разовым перекосом памяти
      still = failures.reject { |job| run_one(job, 0) }
      raise Error, "task failed: #{still.sort.join(', ')}" unless still.empty?
    end

    # Запуск shell-команды с env-переопределениями (CRYSTAL_CACHE_DIR) —
    # вывод наследуется, окружение = текущее + overrides.
    def self.spawn_process(command, dir, overrides)
      pid = Process.spawn(overrides, command, chdir: dir,
                                              out: $stdout, err: $stderr)
      Process.wait2(pid)[1].success?
    rescue StandardError
      false
    end

    # Стартовая ширина до замера peak: консервативный fallback.
    private def initial_workers
      workers_for(FALLBACK_PEAK_KB)
    end

    private def workers_for(peak_kb)
      workers = self.class.core_count || 4
      if (mem = Sysmonitor.memory)
        mem_bound = (mem.available_kb * 0.7 / peak_kb).to_i
        workers = [workers, mem_bound].min
      end
      workers.clamp(1, MAX_WORKERS)
    end

    # Число ядер — nil на платформах без CPU-бэкенда.
    def self.core_count
      Sysmonitor.core_count
    end

    # Первая задача на кэше j0 + сэмплирование RSS её дерева процессов
    # (250 мс интервал). Замеренный peak становится знаменателем формулы
    # ширины и порогом гейта.
    private def warm_up(job)
      pid = Process.spawn(env_for(0), job, chdir: @dir,
                                          out: $stdout, err: $stderr)
      peak_kb = 0
      status = nil
      loop do
        if (waited = Process.wait2(pid, Process::WNOHANG))
          status = waited[1]
          break
        end
        sleep 0.25
        begin
          Sysmonitor.refresh_processes
          tree = Sysmonitor.process_tree_memory_kb(pid)
          peak_kb = tree if tree > peak_kb
        rescue Errno::ENOENT
          # гонка в /proc (процесс исчез посреди скана) — пропускаем сэмпл
        end
      end
      @peak_kb = peak_kb < MIN_PEAK_KB ? MIN_PEAK_KB : peak_kb
      puts self.class.paint(
        "Warm-up: #{job} done, peak task RSS #{@peak_kb / 1024} MB", :blue
      )
      status.success?
    rescue SystemCallError => e
      puts self.class.paint("taskforge: #{e.message}", :red)
      false
    end

    # Тёплый j0 клонируется в ПУСТЫЕ слоты воркеров (полупустые цели от
    # прерванного прогона пересоздаются). Уже населённые слоты не трогаем.
    private def clone_warm_cache(workers)
      warm = cache_dir(0)
      # Слот j0 обычно создаёт сам компилятор; generic-задача (не crystal)
      # могла его не создать — создаём пустой, клонирование работает и так.
      FileUtils.mkdir_p(warm)
      (1...workers).each do |i|
        dst = cache_dir(i)
        next if Dir.exist?(dst) && !Dir.empty?(dst)

        FileUtils.rm_rf(dst)
        FileUtils.cp_r(warm, dst)
      end
    end

    private def run_pool(jobs, workers)
      queue = Queue.new
      jobs.each { |job| queue << job }
      queue.close
      failures = []
      lock = Mutex.new
      threads = workers.times.map do |i|
        Thread.new do
          while (job = queue.pop)
            gate
            run_one(job, i) || lock.synchronize { failures << job }
          end
        end
      end
      threads.each(&:join)
      failures
    end

    # Придержать очередь, пока свободной RAM меньше (peak + запас):
    # уже работающие задачи завершатся и освободят память — дедлока нет.
    private def gate
      while (mem = Sysmonitor.memory) && mem.available_kb < @peak_kb + MARGIN_KB
        sleep 0.3
      end
    end

    private def run_one(job, cache_index)
      self.class.spawn_process(job, @dir, env_for(cache_index))
    end

    private def env_for(cache_index)
      {"CRYSTAL_CACHE_DIR" => cache_dir(cache_index)}
    end

    private def cache_dir(index)
      File.join(@cache_root, "j#{index}")
    end

    private def forced_workers
      value = ENV["TASKFORGE_JOBS"]&.to_i
      value&.clamp(1, MAX_WORKERS)
    end

    # ANSI-подкраска, только когда stdout — терминал.
    COLORS = {blue: "\e[34m", red: "\e[31m"}.freeze
    private_constant :COLORS

    def self.paint(line, color)
      $stdout.tty? ? "#{COLORS[color]}#{line}\e[0m" : line
    end

    private def report(workers, forced)
      mem = Sysmonitor.memory&.available_kb&.div(1024)
      puts self.class.paint(
        "Taskforge pool: #{workers} workers" \
        "#{forced ? " (TASKFORGE_JOBS=#{forced})" : ''} — cores=#{self.class.core_count}," \
        " RAM available=#{mem ? "#{mem} MB" : 'n/a'}, peak task RSS=#{@peak_kb / 1024} MB",
        :blue
      )
    end
  end
end
