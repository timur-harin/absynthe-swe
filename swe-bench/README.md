# SWE-bench Integration with Absynthe

Complete pipeline for synthesizing Python code from SWE-bench tasks using LLM decomposition and Absynthe synthesis.

## 📁 Project Structure

```
swe-bench/
├── bin/
│   └── main.rb                    # Main entry point
├── lib/
│   ├── llm_client.rb              # LM Studio API client
│   ├── synthesizer.rb             # Absynthe synthesis engine
│   ├── python_executor.rb         # Python code execution & validation
│   └── swe_bench_loader.rb       # SWE-bench task loader
├── scripts/
│   └── download_swe_tasks.rb     # Download SWE-bench tasks
├── tasks/                         # SWE-bench task JSON files
├── results/                       # Synthesis results
└── docs/
    ├── README.md                  # This file
    ├── PIPELINE_FLOW.md           # Detailed pipeline explanation
    └── FINAL_RESULTS.md           # Results summary
```

## 🚀 Quick Start

### 1. Setup LM Studio

1. Install LM Studio from https://lmstudio.ai/
2. Download a fast model (see recommendations below)
3. Load model in LM Studio
4. Start Local Server (port 1234)

### Model Recommendations for M3 Pro

**Fast & Small Models (Recommended):**
- **TinyLlama-1.1B-Chat** (~637MB) - Fastest option
- **Phi-3-mini-4k-instruct** (~2.3GB) - Good balance
- **Llama-3.2-3B-Instruct** (~2GB) - Better quality

**How to find in LM Studio:**
1. Open LM Studio
2. Go to "Search" tab
3. Search for model name (e.g., "TinyLlama" or "Phi-3")
4. Click "Download"
5. Select: Format=GGUF, Quantization=Q4_K_M (good balance)
6. Load model in "Chat" tab
7. Start "Local Server" in "Local Server" tab

### 2. Download SWE-bench Tasks

```bash
cd swe-bench
bundle exec ruby scripts/download_swe_tasks.rb 5
```

Tasks will be saved to `tasks/` directory.

### 3. Run Pipeline

```bash
# Set environment variables (optional)
export LLM_URL="http://localhost:1234/v1"
export LLM_MODEL="TinyLlama-1.1B-Chat"  # or your model name
export SWE_BENCH_PATH="~/swe-bench-data"  # optional

# Run on a task
bundle exec ruby bin/main.rb swe_real_task_1
```

## 📖 Documentation

- **[PIPELINE_FLOW.md](docs/PIPELINE_FLOW.md)** - Detailed explanation of the pipeline flow
- **[FINAL_RESULTS.md](docs/FINAL_RESULTS.md)** - Results summary and statistics

## 🏗️ Architecture

```
SWE-bench Task → LLM Decomposition → Absynthe Synthesis → Validation → Solution
```

### Components

- **`bin/main.rb`**: Orchestrates the entire pipeline
- **`lib/llm_client.rb`**: Connects to LM Studio for task decomposition
- **`lib/synthesizer.rb`**: Integrates Absynthe for code synthesis
- **`lib/python_executor.rb`**: Executes and validates Python code
- **`lib/swe_bench_loader.rb`**: Loads SWE-bench task files

## 📊 Results

Results are saved to: `results/<task_id>_result.json`

Contains:
- Synthesized function code
- Validation results
- Combined solution
- Statistics

## 🔧 Requirements

- Ruby 3.2+
- Python 3.x (for code execution)
- LM Studio running locally
- SWE-bench dataset (optional, can use individual task files)

## 📝 Usage Examples

### Basic Usage

```bash
bundle exec ruby bin/main.rb swe_real_task_1
```

### With Custom LLM URL

```bash
LLM_URL="http://localhost:8080/v1" bundle exec ruby bin/main.rb task_123
```

### With SWE-bench Data Path

```bash
SWE_BENCH_PATH="/path/to/swe-bench" bundle exec ruby bin/main.rb task_123
```

## 🐛 Troubleshooting

For synthesis issues:
- Check that `pytype_only_expand_hole.rb` is accessible
- Verify RDL type definitions are loaded
- Check Python execution path

For LLM issues:
- Ensure LM Studio server is running
- Check LLM_URL environment variable
- Verify model is loaded in LM Studio
