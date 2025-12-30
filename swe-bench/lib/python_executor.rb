#!/usr/bin/env ruby

# Python Executor
# Executes synthesized Python code and validates against examples

require "json"
require "open3"

class PythonExecutor
  def initialize
    @python_cmd = find_python
  end

  # Execute Python code with inputs and check output
  def execute_and_validate(code, examples, function_name: "function_name")
    results = []
    
    examples.each do |ex|
      input = ex["input"]
      expected_output = ex["output"]
      
      begin
        actual_output = execute_code(code, input, function_name: function_name)
        match = compare_outputs(actual_output, expected_output)
        results << {
          input: input,
          expected: expected_output,
          actual: actual_output,
          match: match
        }
      rescue => e
        results << {
          input: input,
          expected: expected_output,
          error: e.message,
          match: false
        }
      end
    end
    
    results
  end

  # Execute Python code with given inputs
  def execute_code(code, inputs, function_name: "function_name")
    # Wrap code in a function and call it
    # Extract function name from code if possible, or use default
    # Escape the code properly for multi-line strings
    code_escaped = code.gsub('\\', '\\\\').gsub("'", "\\'").gsub("\n", "\\n")
    
    wrapped_code = <<~PYTHON
      import json
      import sys
      
      #{code}
      
      # Get inputs from command line
      inputs = json.loads(sys.argv[1])
      
      # Try to call the function (assume it's the last defined function or use function_name)
      if '#{function_name}' in globals():
          result = #{function_name}(*inputs)
      else:
          # Try to find any function in the code
          import re
          code_str = '''#{code_escaped}'''
          func_match = re.search(r'def\\s+(\\w+)\\s*\\(', code_str)
          if func_match:
              func_name = func_match.group(1)
              result = globals()[func_name](*inputs)
          else:
              raise ValueError("No function found in code")
      
      print(json.dumps(result))
    PYTHON
    
    stdout, stderr, status = Open3.capture3(
      @python_cmd,
      "-c", wrapped_code,
      inputs.to_json
    )
    
    if status.success?
      JSON.parse(stdout)
    else
      raise "Python execution error: #{stderr}"
    end
  end

  # Compare actual vs expected output
  def compare_outputs(actual, expected)
    # Deep comparison
    case expected
    when Hash
      return false unless actual.is_a?(Hash)
      expected.all? { |k, v| actual.key?(k.to_s) && compare_outputs(actual[k.to_s], v) }
    when Array
      return false unless actual.is_a?(Array)
      return false unless actual.length == expected.length
      actual.zip(expected).all? { |a, e| compare_outputs(a, e) }
    else
      actual == expected
    end
  end

  private

  def find_python
    ["python3", "python"].find { |cmd| system("which #{cmd} > /dev/null 2>&1") } || "python3"
  end
end

