# Pipeline Flow: LLM Decomposition → Absynthe Synthesis

## Overview

The pipeline combines **LLM intelligence** (for task understanding) with **Absynthe synthesis** (for correct code generation) to solve SWE-bench tasks.

```
SWE-bench Task → LLM Decomposition → Absynthe Synthesis → Validation → Solution
```

---

## Why Lines 164-165 in `llm_client.rb`?

**Lines 164-165** implement a **fallback mechanism** for task type detection:

```ruby
# Detect task type from text (case insensitive)
text_lower = text.downcase
```

### Purpose

1. **LLM Fallback**: When LLM fails to return valid JSON or returns conversational text instead of structured data, we need a backup.

2. **Keyword-Based Detection**: The code analyzes the problem statement text to identify task patterns:
   - `"multiply" + "two"` → multiplication task
   - `"format" + "phone"` → phone formatting
   - `"parse" + "query"` → query string parsing
   - etc.

3. **Default Examples**: For each detected pattern, it provides pre-defined examples that work with Absynthe's capabilities.

### When It's Used

The fallback is triggered in `extract_functions_manually` method when:
- LLM JSON parsing fails
- LLM returns conversational text instead of JSON
- LLM response is empty or malformed

### Example

```ruby
if text_lower.include?("format") && text_lower.include?("phone")
  # Automatically creates format_phone_number function
  # with pre-defined examples that Absynthe can solve
end
```

---

## Complete Pipeline Flow

### Step 1: Load SWE-bench Task

**File**: `swe_bench_loader.rb`

```ruby
task_data = @loader.load_task(task_id)
task_info = @loader.extract_task_info(task_data)
```

**Input**: Task ID (e.g., `"django__django-12345"`)  
**Output**: 
- `problem_statement`: Text description of the task
- `test_cases`: Test assertions from the task
- `repo`: Repository name

---

### Step 2: LLM Decomposition

**File**: `llm_client.rb` → `decompose_task`

**Process**:

1. **Build Prompt** (`build_decomposition_prompt`):
   ```
   "Decompose this task into functions with examples:
   Task: [problem_statement]
   Tests: [test_cases]"
   ```

2. **Call LLM** (`call_llm`):
   - Sends request to LM Studio API (`http://127.0.0.1:1234/v1`)
   - Uses OpenAI-compatible chat completions endpoint
   - Temperature: 0.3 (low for structured output)

3. **Parse Response** (`parse_decomposition`):
   - **Primary**: Try to extract JSON from response
   - **Fallback**: If JSON parsing fails → `extract_functions_manually` (lines 164-165)

4. **Output**: Array of function specs:
   ```json
   {
     "functions": [
       {
         "name": "format_phone_number",
         "signature": "format_phone_number(phone: str) -> str",
         "examples": [
           {"input": ["1234567890"], "output": "(123) 456-7890"},
           ...
         ]
       }
     ]
   }
   ```

**Why LLM?**
- Understands natural language task descriptions
- Can extract relevant examples from test cases
- Decomposes complex tasks into smaller functions

**Why Fallback?**
- LLMs can be unreliable (return text instead of JSON)
- Ensures pipeline continues even if LLM fails
- Provides known-good examples for common patterns

---

### Step 3: Absynthe Synthesis

**File**: `synthesizer.rb` → `FunctionSynthesizer#synthesize`

**Process**:

1. **Type Inference** (`infer_types_from_examples`):
   ```ruby
   # From examples: [{"input": [2, 3], "output": 6}, ...]
   # Infer: input_types = [Integer, Integer], output_type = Integer
   ```

2. **Create Abstract Environment**:
   ```ruby
   abs_env = {
     :arg0 => PyType.val(RDL::Type::SingletonType.new(2)),
     :arg1 => PyType.val(RDL::Type::SingletonType.new(3))
   }
   goal = PyType.val(RDL::Globals.types[:integer])
   ```

3. **Extract Constants**:
   - Collect all integer/string literals from examples
   - Add to `ctx.consts[:int]` and `ctx.consts[:str]`

4. **Call Absynthe Core**:
   ```ruby
   prog = Absynthe.synthesize(ctx, spec, q)
   ```
   - Uses `PyTypeOnlyExpandHolePass` to generate candidates
   - Tests candidates against examples using `PythonExecutor`
   - Returns first program that passes all examples

5. **Unparse to Python**:
   ```ruby
   code = "def #{name}(#{args}):\n    return #{unparse_python(prog)}"
   ```

**Why Absynthe?**
- **Correctness**: Guarantees code matches examples exactly
- **No Hallucinations**: Only generates code that passes tests
- **Type Safety**: Uses abstract interpretation to guide search

---

### Step 4: Validation

**File**: `python_executor.rb` → `execute_and_validate`

**Process**:

1. **Execute Code**: Run synthesized Python function
2. **Compare Results**: Check output against expected values
3. **Report**: Return validation results

```ruby
validation = [
  {
    input: ["1234567890"],
    expected: "(123) 456-7890",
    actual: "(123) 456-7890",
    match: true
  },
  ...
]
```

---

### Step 5: Combine & Save

**File**: `main.rb` → `generate_combined_code`

- Combines all validated functions into single code block
- Saves to `results/<task_id>_result.json`

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 1. SWE-bench Task JSON                                      │
│    {problem_statement, test_patch, ...}                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. LLMClient.decompose_task()                              │
│    ├─ Build prompt with problem + tests                     │
│    ├─ Call LM Studio API                                    │
│    ├─ Parse JSON response                                   │
│    └─ Fallback: extract_functions_manually() ← Lines 164-165│
│                                                             │
│    Output: [{name, signature, examples}, ...]               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. FunctionSynthesizer.synthesize()                         │
│    ├─ Infer types from examples                             │
│    ├─ Create abstract environment (PyType)                  │
│    ├─ Extract constants                                     │
│    ├─ Call Absynthe.synthesize()                            │
│    │   ├─ PyTypeOnlyExpandHolePass generates candidates    │
│    │   ├─ Test each candidate with PythonExecutor          │
│    │   └─ Return first passing program                      │
│    └─ Unparse to Python code                                │
│                                                             │
│    Output: "def format_phone_number(arg0): return ..."      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. PythonExecutor.execute_and_validate()                   │
│    ├─ Execute Python code                                   │
│    ├─ Compare with expected outputs                         │
│    └─ Return validation results                             │
│                                                             │
│    Output: [{input, expected, actual, match}, ...]         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Generate Combined Solution                                │
│    └─ Save to results/<task_id>_result.json                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Why This Architecture?

### LLM Strengths
- ✅ Natural language understanding
- ✅ Task decomposition
- ✅ Example extraction from tests

### LLM Weaknesses
- ❌ Can generate incorrect code
- ❌ May hallucinate
- ❌ Unreliable JSON output

### Absynthe Strengths
- ✅ Guaranteed correctness (matches examples)
- ✅ No hallucinations
- ✅ Type-safe synthesis

### Absynthe Weaknesses
- ❌ Needs structured examples
- ❌ Limited to supported operations
- ❌ Can't understand natural language

### Combined Solution
- **LLM** handles understanding and decomposition
- **Absynthe** ensures correctness
- **Fallback** (lines 164-165) ensures reliability

---

## Example: Complete Flow

### Input Task
```json
{
  "problem_statement": "Format a 10-digit phone number into (XXX) XXX-XXXX",
  "test_patch": "assert format_phone_number('1234567890') == '(123) 456-7890'"
}
```

### Step 2: LLM Decomposition
```json
{
  "functions": [{
    "name": "format_phone_number",
    "examples": [
      {"input": ["1234567890"], "output": "(123) 456-7890"}
    ]
  }]
}
```

### Step 3: Absynthe Synthesis
- Generates candidates: `arg0 + "..."`, `arg0[0:3]`, etc.
- Tests each candidate
- Finds: `"(" + arg0[0:3] + ") " + arg0[3:6] + "-" + arg0[6:10]`
- ✅ Passes all examples

### Step 4: Validation
```python
def format_phone_number(arg0):
    return "(" + arg0[0:3] + ") " + arg0[3:6] + "-" + arg0[6:10]
```
✅ All tests pass

---

## Key Files

- **`main.rb`**: Orchestrates the pipeline
- **`llm_client.rb`**: LLM API client + fallback (lines 164-165)
- **`synthesizer.rb`**: Absynthe integration
- **`python_executor.rb`**: Code execution & validation
- **`swe_bench_loader.rb`**: Task loading

---

## Summary

**Lines 164-165** provide a **reliable fallback** when LLM fails, using keyword-based pattern matching to identify common task types and provide known-good examples. This ensures the pipeline can continue even when LLM is unreliable, while still leveraging LLM's strengths when it works correctly.

