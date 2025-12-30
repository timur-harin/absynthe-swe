# Структура проекта swe-bench

## Организация файлов

```
swe-bench/
├── bin/                          # Исполняемые файлы
│   └── main.rb                   # Главная точка входа
│
├── lib/                          # Основные компоненты
│   ├── llm_client.rb             # Клиент для LM Studio API
│   ├── synthesizer.rb            # Интеграция с Absynthe
│   ├── python_executor.rb        # Выполнение и валидация Python кода
│   └── swe_bench_loader.rb       # Загрузчик задач SWE-bench
│
├── scripts/                      # Вспомогательные скрипты
│   └── download_swe_tasks.rb    # Скачивание задач SWE-bench
│
├── tasks/                        # Задачи SWE-bench (JSON файлы)
│   ├── swe_real_task_1.json
│   ├── swe_real_task_2.json
│   └── ...
│
├── results/                      # Результаты синтеза
│   ├── swe_real_task_1_result.json
│   ├── swe_real_task_2_result.json
│   └── ...
│
├── docs/                         # Документация
│   ├── README.md                 # Основная документация
│   ├── PIPELINE_FLOW.md          # Описание потока работы
│   └── FINAL_RESULTS.md          # Результаты и статистика
│
├── README.md                     # Главный README (ссылается на docs/)
├── .gitignore                    # Git ignore правила
└── STRUCTURE.md                  # Этот файл
```

## Описание директорий

### `bin/`
Содержит исполняемые скрипты - точки входа в приложение.

- **`main.rb`**: Главный скрипт для запуска пайплайна синтеза

### `lib/`
Основные компоненты системы, реализующие бизнес-логику.

- **`llm_client.rb`**: Клиент для взаимодействия с LM Studio (LLM API)
- **`synthesizer.rb`**: Интеграция с Absynthe для синтеза кода
- **`python_executor.rb`**: Выполнение и валидация синтезированного Python кода
- **`swe_bench_loader.rb`**: Загрузка и парсинг задач из SWE-bench

### `scripts/`
Вспомогательные утилиты и скрипты для обслуживания проекта.

- **`download_swe_tasks.rb`**: Скачивание задач из SWE-bench

### `tasks/`
Хранилище задач SWE-bench в формате JSON.

### `results/`
Результаты синтеза кода для каждой задачи.

### `docs/`
Документация проекта.

## Использование

### Запуск пайплайна

```bash
cd swe-bench
bundle exec ruby bin/main.rb <task_id>
```

### Скачивание задач

```bash
bundle exec ruby scripts/download_swe_tasks.rb 5
```

## Пути и зависимости

Все `require_relative` пути обновлены для новой структуры:
- `bin/main.rb` → `../lib/*` для компонентов
- `lib/*` → `../../lib/absynthe/*` для Absynthe
- Пути к `tasks/` и `results/` вычисляются относительно корня `swe-bench/`

