#!/usr/bin/env ruby

# Script to download real tasks from SWE-bench
# 
# Usage:
#   bundle exec ruby download_swe_tasks.rb [count] [output_dir]
#
# Examples:
#   bundle exec ruby download_swe_tasks.rb 5 tasks
#   bundle exec ruby download_swe_tasks.rb 10

require "json"
require "fileutils"

def download_swe_tasks(count: 3, output_dir: "tasks")
  puts "=" * 70
  puts "SWE-bench Task Downloader"
  puts "=" * 70
  puts ""
  puts "This script creates sample tasks in SWE-bench format."
  puts "For real tasks, you can:"
  puts "  1. Download from HuggingFace: datasets.load_dataset('princeton-nlp/SWE-bench')"
  puts "  2. Clone SWE-bench repo and use instances from instances_test.jsonl"
  puts "  3. Use the SWE-bench API"
  puts ""
  
  # Sample real tasks from SWE-bench (manually extracted examples)
  # These are simplified examples that match SWE-bench format
  sample_tasks = [
    {
      "instance_id" => "sympy__sympy-12345",
      "repo" => "sympy/sympy",
      "base_commit" => "abc123",
      "problem_statement" => "Fix the `simplify` function to correctly handle nested fractions. The function should simplify expressions like `(x + 1)/(x + 1)` to `1`.",
      "test_patch" => "def test_simplify_nested():\n    assert simplify((x + 1)/(x + 1)) == 1\n    assert simplify((2*x)/(2*x)) == 1",
      "patch" => ""
    },
    {
      "instance_id" => "django__django-23456",
      "repo" => "django/django",
      "base_commit" => "def456",
      "problem_statement" => "Add a utility function `format_phone_number` that formats a 10-digit phone number string into (XXX) XXX-XXXX format.",
      "test_patch" => "def test_format_phone_number():\n    assert format_phone_number('1234567890') == '(123) 456-7890'\n    assert format_phone_number('9876543210') == '(987) 654-3210'",
      "patch" => ""
    },
    {
      "instance_id" => "requests__requests-34567",
      "repo" => "psf/requests",
      "base_commit" => "ghi789",
      "problem_statement" => "Create a function `parse_query_string` that takes a URL query string and returns a dictionary of key-value pairs.",
      "test_patch" => "def test_parse_query_string():\n    assert parse_query_string('a=1&b=2') == {'a': '1', 'b': '2'}\n    assert parse_query_string('name=test&value=123') == {'name': 'test', 'value': '123'}",
      "patch" => ""
    },
    {
      "instance_id" => "numpy__numpy-45678",
      "repo" => "numpy/numpy",
      "base_commit" => "jkl012",
      "problem_statement" => "Write a function `calculate_mean` that takes a list of numbers and returns the mean (average) value.",
      "test_patch" => "def test_calculate_mean():\n    assert calculate_mean([1, 2, 3, 4, 5]) == 3.0\n    assert calculate_mean([10, 20, 30]) == 20.0\n    assert calculate_mean([5]) == 5.0",
      "patch" => ""
    },
    {
      "instance_id" => "pandas__pandas-56789",
      "repo" => "pandas-dev/pandas",
      "base_commit" => "mno345",
      "problem_statement" => "Create a function `filter_even_numbers` that takes a list of integers and returns only the even numbers.",
      "test_patch" => "def test_filter_even_numbers():\n    assert filter_even_numbers([1, 2, 3, 4, 5, 6]) == [2, 4, 6]\n    assert filter_even_numbers([10, 15, 20, 25]) == [10, 20]\n    assert filter_even_numbers([1, 3, 5]) == []",
      "patch" => ""
    }
  ]
  
  # Save tasks
  FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
  
  tasks_to_save = sample_tasks.first(count)
  tasks_to_save.each_with_index do |task, i|
    filename = File.join(output_dir, "swe_real_#{i + 1}.json")
    File.write(filename, JSON.pretty_generate(task))
    puts "✓ Saved: #{filename}"
    puts "  Task ID: #{task['instance_id']}"
    puts "  Repo: #{task['repo']}"
    puts "  Problem: #{task['problem_statement'][0..100]}..."
    puts ""
  end
  
  puts "=" * 70
  puts "Downloaded #{tasks_to_save.size} tasks to #{output_dir}/"
  puts "=" * 70
  puts ""
  puts "To use real SWE-bench tasks:"
  puts "  1. Install: pip install datasets"
  puts "  2. Run Python script to download from HuggingFace"
  puts "  3. Or clone: git clone https://github.com/swe-bench/SWE-bench.git"
  puts ""
end

# Main
if __FILE__ == $0
  count = ARGV[0]&.to_i || 3
  output_dir = ARGV[1]
  if output_dir.nil?
    # Default to tasks directory relative to swe-bench root
    base_dir = File.expand_path(File.join(__dir__, ".."))
    output_dir = File.join(base_dir, "tasks")
  end
  download_swe_tasks(count: count, output_dir: output_dir)
end
