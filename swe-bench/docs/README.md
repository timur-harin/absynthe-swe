# SWE-bench Integration with Absynthe

Complete pipeline for synthesizing Python code from SWE-bench tasks using LLM decomposition and Absynthe synthesis.

## Quick Start

### 0. Download SWE-bench Tasks

You can use the provided script to create sample tasks:

```bash
cd swe-bench
bundle exec ruby download_swe_tasks.rb 5 tasks
```

For real SWE-bench tasks, you can:

1. **Use HuggingFace datasets** (recommended):
   ```python
   from datasets import load_dataset
   dataset = load_dataset('princeton-nlp/SWE-bench', split='test')
   # Save tasks to JSON files
   ```

2. **Clone SWE-bench repository**:
   ```bash
   git clone https://github.com/swe-bench/SWE-bench.git
   # Tasks are in instances/instances_test.jsonl
   ```

3. **Use SWE-bench API** (see official documentation)

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

### 2. Test LLM Connection

```bash
cd swe-bench
bundle exec ruby test_llm.rb
```

### 3. Run Setup

```bash
./setup.sh
```

### 4. Run Pipeline

```bash
# Set environment variables (optional)
export LLM_URL="http://localhost:1234/v1"
export LLM_MODEL="TinyLlama-1.1B-Chat"  # or your model name
export SWE_BENCH_PATH="~/swe-bench-data"

# Run on a task
bundle exec ruby main.rb <task_id>
```

## Architecture

```
┌─────────────────────────────────────────┐
│         SWE-bench Task                  │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│    SWEBenchLoader                       │
│    - Loads task JSON                    │
│    - Extracts problem & tests           │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│    LLMClient (LM Studio)                │
│    - Decomposes task into functions     │
│    - Generates examples                 │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│    FunctionSynthesizer (Absynthe)        │
│    - Infers types from examples         │
│    - Synthesizes code with PyType       │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│    PythonExecutor                       │
│    - Executes synthesized code          │
│    - Validates against examples         │
└──────────────┬──────────────────────────┘
               │
               ▼
         Combined Solution
```

## Files

- `main.rb` - Main pipeline orchestrator
- `swe_bench_loader.rb` - Loads SWE-bench tasks
- `llm_client.rb` - LM Studio API client
- `synthesizer.rb` - Absynthe synthesis engine
- `python_executor.rb` - Python code execution & validation
- `test_llm.rb` - Test LLM connection
- `setup.sh` - Automated setup script

## Usage Examples

### Basic Usage

```bash
bundle exec ruby main.rb django__django-12345
```

### With Custom LLM URL

```bash
LLM_URL="http://localhost:8080/v1" bundle exec ruby main.rb task_123
```

### With SWE-bench Data Path

```bash
SWE_BENCH_PATH="/path/to/swe-bench" bundle exec ruby main.rb task_123
```

## Output

Results are saved to: `swe-bench/results/<task_id>_result.json`

Contains:
- Synthesized function code
- Validation results
- Combined solution
- Statistics

## Requirements

- Ruby 3.2+
- Python 3.x (for code execution)
- LM Studio running locally
- SWE-bench dataset (optional, can use individual task files)

## Troubleshooting

See `setup_lm_studio.md` for LM Studio issues.

For synthesis issues:
- Check that `pytype_only_expand_hole.rb` is accessible
- Verify RDL type definitions are loaded
- Check Python execution path
