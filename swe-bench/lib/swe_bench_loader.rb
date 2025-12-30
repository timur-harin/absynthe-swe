#!/usr/bin/env ruby

# SWE-bench Task Loader
# Loads tasks from SWE-bench dataset

require "json"
require "open-uri"
require "fileutils"

class SWEBenchLoader
  def initialize(data_path: nil)
    @data_path = data_path || find_swe_bench_data
  end

  # Load a specific task by ID
  def load_task(task_id)
    # Try different paths
    paths = [
      "#{@data_path}/#{task_id}.json",
      "#{@data_path}/#{task_id}",
      File.join(@data_path, "#{task_id}.json"),
      File.join(@data_path, task_id)
    ]
    
    paths.each do |path|
      if File.exist?(path)
        return JSON.parse(File.read(path))
      end
    end
    
    raise "Task not found: #{task_id}. Tried: #{paths.join(', ')}"
  end

  # List available tasks
  def list_tasks
    if Dir.exist?(@data_path)
      Dir.glob("#{@data_path}/*.json").map { |f| File.basename(f, ".json") }
    else
      []
    end
  end

  # Extract task description and test cases
  def extract_task_info(task_data)
    {
      instance_id: task_data["instance_id"],
      repo: task_data["repo"],
      base_commit: task_data["base_commit"],
      problem_statement: task_data["problem_statement"] || task_data["instruction"],
      test_patch: task_data["test_patch"],
      patch: task_data["patch"],
      test_cases: extract_test_cases(task_data)
    }
  end

  private

  def find_swe_bench_data
    # Try common locations
    base_dir = File.expand_path(File.join(__dir__, ".."))
    [
      File.join(base_dir, "tasks"),  # Relative to swe-bench root
      @data_path,
      "~/swe-bench",
      "~/Downloads/swe-bench",
      "./swe-bench-data",
      "../swe-bench"
    ].compact.each do |path|
      expanded = File.expand_path(path)
      if Dir.exist?(expanded)
        return expanded
      end
    end
    
    # Default: use tasks directory relative to swe-bench root
    tasks_dir = File.join(base_dir, "tasks")
    FileUtils.mkdir_p(tasks_dir) unless Dir.exist?(tasks_dir)
    return tasks_dir
    default_path = File.expand_path("~/swe-bench")
    FileUtils.mkdir_p(default_path) unless Dir.exist?(default_path)
    default_path
  end

  def extract_test_cases(task_data)
    # Extract test cases from test_patch or problem_statement
    test_patch = task_data["test_patch"] || ""
    
    # Try to find test function calls or assertions
    test_cases = []
    
    # Look for pytest-style tests
    test_patch.scan(/def test_\w+\([^)]*\):[\s\S]*?(?=def |\Z)/) do |test|
      test_cases << test.strip
    end
    
    # Look for assert statements
    test_patch.scan(/assert\s+[^\n]+/) do |assertion|
      test_cases << assertion.strip
    end
    
    test_cases.any? ? test_cases : ["No test cases found"]
  end
end

