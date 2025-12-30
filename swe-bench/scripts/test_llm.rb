#!/usr/bin/env ruby

# Test script for LLM connection
# Verifies LM Studio is working correctly

require_relative "../lib/llm_client"

def test_llm_connection
  puts "Testing LM Studio Connection..."
  puts "=" * 70
  
  llm_url = ENV["LLM_URL"] || "http://127.0.0.1:1234/v1"
  llm_model = ENV["LLM_MODEL"]
  
  puts "URL: #{llm_url}"
  puts "Model: #{llm_model || 'default'}"
  puts ""
  
  begin
    client = LLMClient.new(base_url: llm_url, model: llm_model)
    
    # Test simple prompt using decompose_task (it calls LLM internally)
    puts "Sending test prompt..."
    response = client.decompose_task("Say 'Hello' if you can hear me.", [])
    
    puts "Response:"
    puts response.inspect
    puts ""
    puts "✓ Connection successful!"
    
  rescue => e
    puts "✗ Error: #{e.class} - #{e.message}"
    puts ""
    puts "Troubleshooting:"
    puts "1. Make sure LM Studio is running"
    puts "2. Check that Local Server is started"
    puts "3. Verify URL: #{llm_url}"
    puts "4. Try: curl #{llm_url}/models"
    exit 1
  end
end

if __FILE__ == $0
  test_llm_connection
end

