#!/usr/bin/env ruby

# Main SWE-bench Pipeline
# Orchestrates: Load task → LLM decomposition → Absynthe synthesis → Validation

require "bundler/setup"
require "absynthe"
require "absynthe/python"
require_relative "../../lib/absynthe/passes/pytype_only_expand_hole"
require "rdl"
require_relative "../lib/swe_bench_loader"
require_relative "../lib/llm_client"
require_relative "../lib/synthesizer"
require_relative "../lib/python_executor"
require "json"
require "fc"
require "timeout"

class SWEBenchPipeline
  def initialize(llm_url: "http://127.0.0.1:1234/v1", llm_model: nil, swe_bench_path: nil)
    @loader = SWEBenchLoader.new(data_path: swe_bench_path)
    @llm = LLMClient.new(base_url: llm_url, model: llm_model)
    @executor = PythonExecutor.new
    @synthesizer = FunctionSynthesizer.new(@executor)
  end

  def process_task(task_id)
    puts "=" * 70
    puts "Processing SWE-bench Task: #{task_id}"
    puts "=" * 70
    puts ""

    # Step 1: Load task
    puts "Step 1: Loading task..."
    task_data = @loader.load_task(task_id)
    task_info = @loader.extract_task_info(task_data)
    
    puts "  Repo: #{task_info[:repo]}"
    puts "  Problem: #{task_info[:problem_statement][0..200]}..."
    puts ""

    # Step 2: Decompose with LLM
    puts "Step 2: Decomposing with LLM..."
    decomposition = @llm.decompose_task(
      task_info[:problem_statement],
      task_info[:test_cases]
    )
    
    functions = decomposition["functions"] || []
    puts "  Found #{functions.size} functions to synthesize"
    puts ""

    # Step 3: Synthesize each function
    puts "Step 3: Synthesizing functions with Absynthe..."
    synthesized_functions = {}
    
    functions.each do |func_spec|
      result = @synthesizer.synthesize(func_spec, timeout: 120)
      if result
        synthesized_functions[func_spec["name"]] = result
      else
        puts "  ✗ Failed to synthesize: #{func_spec["name"]}"
      end
    end
    
    puts ""

    # Step 4: Validate synthesized code
    puts "Step 4: Validating synthesized code..."
    validation_results = {}
    
    synthesized_functions.each do |name, result|
      func_spec = functions.find { |f| f["name"] == name }
      next unless func_spec
      
      validation = @executor.execute_and_validate(result[:code], func_spec["examples"])
      validation_results[name] = {
        code: result[:code],
        validation: validation,
        all_passed: validation.all? { |r| r[:match] }
      }
      
      if validation_results[name][:all_passed]
        puts "  ✓ #{name}: All examples passed"
      else
        puts "  ✗ #{name}: Some examples failed"
      end
    end
    
    puts ""

    # Step 5: Generate combined solution
    puts "Step 5: Generating combined solution..."
    combined_code = generate_combined_code(validation_results)
    
    puts "=" * 70
    puts "Results"
    puts "=" * 70
    puts ""
    puts "Synthesized Functions: #{synthesized_functions.size}/#{functions.size}"
    puts "Validated Functions: #{validation_results.count { |_, v| v[:all_passed] }}/#{validation_results.size}"
    puts ""
    puts "Combined Code:"
    puts "-" * 70
    puts combined_code
    puts "-" * 70

    {
      task_id: task_id,
      functions_synthesized: synthesized_functions.size,
      functions_validated: validation_results.count { |_, v| v[:all_passed] },
      combined_code: combined_code,
      details: validation_results
    }
  end

  private

  def generate_combined_code(validation_results)
    code_parts = validation_results.map do |name, result|
      "# #{name}\n#{result[:code]}\n"
    end
    
    code_parts.join("\n")
  end
end

# Main execution
if __FILE__ == $0
  task_id = ARGV[0]
  llm_url = ENV["LLM_URL"] || "http://127.0.0.1:1234/v1"
  llm_model = ENV["LLM_MODEL"] || nil
  swe_bench_path = ENV["SWE_BENCH_PATH"] || nil

  unless task_id
    puts "Usage: #{$0} <task_id>"
    puts ""
    puts "Environment variables:"
    puts "  LLM_URL - LM Studio API URL (default: http://localhost:1234/v1)"
    puts "  LLM_MODEL - Model name (optional, uses default)"
    puts "  SWE_BENCH_PATH - Path to SWE-bench data (optional)"
    exit 1
  end

  pipeline = SWEBenchPipeline.new(
    llm_url: llm_url,
    llm_model: llm_model,
    swe_bench_path: swe_bench_path
  )

  begin
    result = pipeline.process_task(task_id)
    
    # Save results
    require "fileutils"
    output_file = File.join(__dir__, "..", "results", "#{task_id}_result.json")
    FileUtils.mkdir_p(File.dirname(output_file))
    File.write(output_file, JSON.pretty_generate(result))
    puts ""
    puts "Results saved to: #{output_file}"
  rescue => e
    puts ""
    puts "Error: #{e.class} - #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end
end

