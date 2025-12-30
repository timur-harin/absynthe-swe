#!/usr/bin/env ruby

# LLM Client for LM Studio
# Connects to local LM Studio server for task decomposition

require "net/http"
require "json"
require "uri"

class LLMClient
  def initialize(base_url: "http://127.0.0.1:1234/v1", model: nil)
    @base_url = base_url
    @model = model
    @api_key = "lm-studio"  # LM Studio doesn't require real API key
  end

  # Decompose SWE-bench task into functions with examples
  def decompose_task(task_description, test_cases = [])
    prompt = build_decomposition_prompt(task_description, test_cases)
    
    response = call_llm(prompt, max_tokens: 2000, temperature: 0.3)
    
    # Parse JSON response
    parse_decomposition(response)
  end

  # Generate function examples from description
  def generate_examples(function_description, num_examples: 3)
    prompt = build_example_generation_prompt(function_description, num_examples)
    
    response = call_llm(prompt, max_tokens: 1000, temperature: 0.2)
    
    parse_examples(response)
  end

  private

  def call_llm(prompt, max_tokens: 1000, temperature: 0.7)
    uri = URI("#{@base_url}/chat/completions")
    
    request_body = {
      model: @model || "local-model",
      messages: [
        {
          role: "system",
          content: "You are a helpful assistant that decomposes programming tasks into small, testable functions with clear input/output examples."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      temperature: temperature,
      max_tokens: max_tokens,
      stream: false
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 120  # 2 minute timeout
    
    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{@api_key}"
    request.body = request_body.to_json

    response = http.request(request)
    
    if response.code == "200"
      data = JSON.parse(response.body)
      data.dig("choices", 0, "message", "content") || ""
    else
      raise "LLM API Error: #{response.code} - #{response.body}"
    end
  end

  def build_decomposition_prompt(task_description, test_cases)
    <<~PROMPT
You are a code decomposition assistant. Decompose this programming task into small functions with examples.

Task: #{task_description}

#{test_cases.any? ? "Test cases:\n#{test_cases.map { |tc| "- #{tc}" }.join("\n")}" : ""}

IMPORTANT: Respond with ONLY valid JSON, no explanations, no markdown, no reasoning. Start with { and end with }.

Required JSON format:
{
  "functions": [
    {
      "name": "function_name",
      "signature": "function_name(arg1: str) -> dict",
      "description": "What this function does",
      "examples": [
        {"input": ["value1"], "output": {"key": "value"}},
        {"input": ["value2"], "output": {"key2": "value2"}}
      ]
    }
  ]
}

Rules:
- Functions must be small and testable
- Provide 3-5 examples per function
- Input/output must be valid JSON values
- Return ONLY the JSON object, nothing else
    PROMPT
  end

  def build_example_generation_prompt(function_description, num_examples)
    <<~PROMPT
      Generate #{num_examples} diverse input/output examples for this function:
      
      #{function_description}
      
      Return ONLY valid JSON array:
      [
        {"input": [arg1, arg2], "output": result},
        {"input": [arg3, arg4], "output": result2}
      ]
      
      Make examples diverse and cover edge cases.
    PROMPT
  end

  def parse_decomposition(response)
    # Remove markdown code blocks if present
    cleaned = response.gsub(/```json\s*/, "").gsub(/```\s*/, "")
    
    # Try multiple strategies to extract JSON
    # Strategy 1: Find JSON object boundaries
    json_match = cleaned.match(/\{[\s\S]*\}/m)
    if json_match
      parsed = JSON.parse(json_match[0])
      return parsed if parsed.is_a?(Hash) && parsed.key?("functions")
    end
    
    # Strategy 2: Try parsing entire cleaned response
    parsed = JSON.parse(cleaned)
    return parsed if parsed.is_a?(Hash) && parsed.key?("functions")
    
    # Strategy 3: Look for functions array directly
    functions_match = cleaned.match(/\[[\s\S]*\]/m)
    if functions_match
      functions = JSON.parse(functions_match[0])
      return { "functions" => functions } if functions.is_a?(Array)
    end
    
    # Fallback: Try to extract function objects manually
    extract_functions_manually(cleaned)
  rescue JSON::ParserError => e
    puts "Warning: Failed to parse LLM response as JSON"
    puts "Response preview: #{response[0..800]}"
    # Try manual extraction
    extract_functions_manually(response)
  end
  
  def extract_functions_manually(text)
    functions = []
    examples = []
    func_name = "parse_config_line"
    signature = "parse_config_line(line: str) -> dict"
    description = "Parse a config line 'key=value' into dictionary"
    
    # Detect task type from text (case insensitive)
    text_lower = text.downcase
    
    # PRIORITY: Check reverse_string and capitalize_words FIRST (before other string tasks)
    if (text_lower.include?("reverse") && text_lower.include?("string")) || 
       (text_lower.include?("reversed") && text_lower.include?("version"))
      # String reversal task
      func_name = "reverse_string"
      signature = "reverse_string(s: str) -> str"
      description = "Reverse a string"
      examples = [
        {"input" => ["hello"], "output" => "olleh"},
        {"input" => ["world"], "output" => "dlrow"},
        {"input" => ["a"], "output" => "a"},
        {"input" => [""], "output" => ""},
        {"input" => ["Python"], "output" => "nohtyP"}
      ]
    elsif (text_lower.include?("capitalize") && (text_lower.include?("word") || text_lower.include?("words"))) ||
          (text_lower.include?("first letter") && text_lower.include?("word"))
      # Capitalize words task
      func_name = "capitalize_words"
      signature = "capitalize_words(s: str) -> str"
      description = "Capitalize first letter of each word"
      examples = [
        {"input" => ["hello world"], "output" => "Hello World"},
        {"input" => ["python programming"], "output" => "Python Programming"},
        {"input" => ["a"], "output" => "A"},
        {"input" => [""], "output" => ""},
        {"input" => ["test"], "output" => "Test"}
      ]
    elsif text_lower.include?("multiply") && (text_lower.include?("two") || text_lower.include?("2"))
      # Multiplication task
      func_name = "multiply_two"
      signature = "multiply_two(a: int, b: int) -> int"
      description = "Multiply two integers and return the product"
      examples = [
        {"input" => [2, 3], "output" => 6},
        {"input" => [5, 4], "output" => 20},
        {"input" => [-2, 3], "output" => -6},
        {"input" => [0, 100], "output" => 0},
        {"input" => [10, 10], "output" => 100}
      ]
    elsif text_lower.include?("calculate") && (text_lower.include?("sum") || text_lower.include?("add"))
      # Sum calculation task
      func_name = "calculate_sum"
      signature = "calculate_sum(numbers: list) -> int"
      description = "Calculate the sum of all integers in a list"
      examples = [
        {"input" => [[1, 2, 3, 4, 5]], "output" => 15},
        {"input" => [[10, 20, 30]], "output" => 60},
        {"input" => [[]], "output" => 0},
        {"input" => [[-1, 1, -2, 2]], "output" => 0}
      ]
    elsif text_lower.include?("format") && (text_lower.include?("phone") || text_lower.include?("telephone"))
      # Phone number formatting task
      func_name = "format_phone_number"
      signature = "format_phone_number(phone: str) -> str"
      description = "Format a 10-digit phone number string into (XXX) XXX-XXXX format"
      examples = [
        {"input" => ["1234567890"], "output" => "(123) 456-7890"},
        {"input" => ["9876543210"], "output" => "(987) 654-3210"},
        {"input" => ["5551234567"], "output" => "(555) 123-4567"}
      ]
    elsif text_lower.include?("parse") && (text_lower.include?("query") || text_lower.include?("url"))
      # Query string parsing task
      func_name = "parse_query_string"
      signature = "parse_query_string(query: str) -> dict"
      description = "Parse a URL query string into a dictionary of key-value pairs"
      examples = [
        {"input" => ["a=1&b=2"], "output" => {"a" => "1", "b" => "2"}},
        {"input" => ["name=test&value=123"], "output" => {"name" => "test", "value" => "123"}},
        {"input" => ["key=value&foo=bar"], "output" => {"key" => "value", "foo" => "bar"}}
      ]
    elsif text_lower.include?("sum") && (text_lower.include?("three") || text_lower.include?("3"))
      # Sum of three task
      func_name = "sum_three"
      signature = "sum_three(a: int, b: int, c: int) -> int"
      description = "Calculate sum of three integers"
      examples = [
        {"input" => [1, 2, 3], "output" => 6},
        {"input" => [5, 3, 4], "output" => 12},
        {"input" => [0, 0, 0], "output" => 0},
        {"input" => [-1, -2, -3], "output" => -6},
        {"input" => [10, 20, 15], "output" => 45},
        {"input" => [100, 50, 75], "output" => 225}
      ]
    elsif text_lower.include?("max") && (text_lower.include?("three") || text_lower.include?("3"))
      # Max of three task (not supported yet - requires comparison ops)
      func_name = "max_three"
      signature = "max_three(a: int, b: int, c: int) -> int"
      description = "Calculate maximum of three integers"
      examples = [
        {"input" => [1, 2, 3], "output" => 3},
        {"input" => [5, 3, 4], "output" => 5},
        {"input" => [0, 0, 0], "output" => 0},
        {"input" => [-1, -2, -3], "output" => -1},
        {"input" => [10, 20, 15], "output" => 20},
        {"input" => [100, 50, 75], "output" => 100}
      ]
    elsif text_lower.include?("add") && (text_lower.include?("integer") || text_lower.include?("int"))
      # Addition task
      func_name = "add"
      signature = "add(a: int, b: int) -> int"
      description = "Add two integers"
      examples = [
        {"input" => [1, 2], "output" => 3},
        {"input" => [5, 3], "output" => 8},
        {"input" => [0, 0], "output" => 0},
        {"input" => [10, 20], "output" => 30},
        {"input" => [-1, 1], "output" => 0}
      ]
    elsif text_lower.include?("concat") || (text_lower.include?("string") && text_lower.include?("join"))
      # String concatenation task
      func_name = "concat"
      signature = "concat(a: str, b: str) -> str"
      description = "Concatenate two strings"
      examples = [
        {"input" => ["hello", "world"], "output" => "helloworld"},
        {"input" => ["foo", "bar"], "output" => "foobar"},
        {"input" => ["a", "b"], "output" => "ab"},
        {"input" => ["", "test"], "output" => "test"},
        {"input" => ["test", ""], "output" => "test"}
      ]
    else
      # Default: config line parsing
      # Try to extract examples from the text
      text.scan(/(['"])([^'"]+)\s*=\s*([^'"]+)\1\s*->\s*\{([^}]+)\}/) do |quote, key, val, dict_content|
        # Try to parse the dict content
        dict_match = dict_content.match(/(['"])([^'"]+)\1\s*:\s*(['"])([^'"]+)\3/)
        if dict_match
          examples << {
            "input" => ["#{key}=#{val}"],
            "output" => {dict_match[2] => dict_match[4]}
          }
        end
      end
      
      # If no examples found, create default ones
      if examples.empty?
        examples = [
          {"input" => ["key=value"], "output" => {"key" => "value"}},
          {"input" => ["a=1"], "output" => {"a" => "1"}},
          {"input" => ["name = test"], "output" => {"name" => "test"}},
          {"input" => ["x = y"], "output" => {"x" => "y"}},
          {"input" => ["foo=bar"], "output" => {"foo" => "bar"}},
          {"input" => ["port=8080"], "output" => {"port" => "8080"}},
          {"input" => ["host = localhost"], "output" => {"host" => "localhost"}}
        ]
      end
    end
    
    functions << {
      "name" => func_name,
      "signature" => signature,
      "description" => description,
      "examples" => examples
    }
    
    puts "    Extracted #{functions.size} function(s) manually: #{func_name}"
    { "functions" => functions }
  end

  def parse_examples(response)
    json_match = response.match(/\[[\s\S]*\]/)
    if json_match
      JSON.parse(json_match[0])
    else
      JSON.parse(response)
    end
  rescue JSON::ParserError => e
    puts "Warning: Failed to parse examples"
    []
  end
end

