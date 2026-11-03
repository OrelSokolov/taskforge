# taskforge

Универсальный запуск тяжёлых задач параллельно — с шириной пула,
выведенной из машины, а не зашитой в конфиг. Ruby-порт
`Carat::BuildPool` из [carat.cr](https://github.com/OrelSokolov/carat.cr);
системная информация — гем [sysmonitor](https://github.com/OrelSokolov/sysmonitor).

Задачи — произвольные shell-команды (`rake build:...`,
`crystal build ...`, `make ...`), выполняются как subprocess'ы.

## Почему не `make -j`

Параллельные тяжёлые задачи масштабируются ~N по wall-clock, но каждая
держит ~1-2 ГБ RAM: фиксированная ширина, подобранная под одну машину,
на другой уходит в OOM. Taskforge выводит ширину из ТЕКУЩЕГО состояния:

```
workers = min(ядра, MemAvailable * 0.7 / peak_rss, 8, |задач|)
```

- **Peak RSS измеряется, не угадывается**: первая задача идёт как
  warm-up, каждые 250 мс сэмплируется RSS её дерева процессов
  (sh + rake + crystal + cc).
- **RAM-гейт**: перед выдачей каждого задания очередь придерживается,
  пока `MemAvailable < peak + 512 МБ` — тяжёлая задача замедляет пул,
  а не валит машину в OOM.
- **Ретрай OOM**: упавшая (exit 137 / SIGKILL) задача после осушения
  пула ретраится один раз последовательно.
- **Per-worker `CRYSTAL_CACHE_DIR`**: `<dir>/.taskforge/cache/jN`,
  персистентный между запусками; тёплый слот j0 клонируется остальным —
  конкурентные кристалл-компиляторы не дерутся за общий кэш.

## CLI

```
taskforge 'rake build:web' 'rake build:api' 'crystal build --release src/x.cr -o bin/x'
taskforge -j 2 'cmd1' 'cmd2'     # форсировать число воркеров
taskforge -C ~/proj 'cmd1' 'cmd2'
```

## Библиотека

```ruby
require "taskforge"

jobs = ["rake build:web", "rake build:api"].map do |cmd|
  Taskforge::Pool::Job.new(cmd, cmd)   # name, command
end
Taskforge::Pool.new(Dir.pwd, jobs).run # кидает Taskforge::Pool::Error
```

## Интеграция в Rakefile (любой проект)

```ruby
require "taskforge/rake_task"

Taskforge::RakeTask.new(:build_all) do |t|
  t.description = "Build every binary in parallel"
  t.commands = ["rake build:web", "rake build:api", "rake build:cli"]
end
```

Воркеров можно форсировать переменной `TASKFORGE_JOBS=N` (1..8) — она
отключает адаптивный подбор (бенчмарки, A/B-прогоны).

## Установка

В Gemfile:

```ruby
gem "taskforge"
```

## Разработка

```
bundle install
bundle exec rspec
```

MIT License.
