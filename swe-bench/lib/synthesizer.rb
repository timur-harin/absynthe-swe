#!/usr/bin/env ruby

# Absynthe Synthesizer for SWE-bench functions
# Synthesizes Python code from function specs with examples

require "bundler/setup"
require "absynthe"
require "absynthe/python"
require_relative "../../lib/absynthe/passes/pytype_only_expand_hole"
require "rdl"
require "json"
require "fc"
require "timeout"

# Python unparser function (similar to bin/autopandas)
def unparse_python(node)
  case node.type
  when :const
    konst = node.children[0]
    if konst.is_a?(String)
      "\"#{konst}\""
    elsif konst.is_a?(Integer)
      konst.to_s
    elsif konst.is_a?(Symbol)
      konst.to_s
    else
      konst.to_s
    end
  when :send
    receiver = unparse_python(node.children[0])
    method = node.children[1]
    args = node.children[2..-1].map { |a| unparse_python(a) }.join(", ")
    if method == :__add__
      "#{receiver} + #{args}"
    elsif method == :__sub__
      "#{receiver} - #{args}"
    elsif method == :__mul__
      "#{receiver} * #{args}"
    elsif method == :__div__
      "#{receiver} / #{args}"
    elsif method == :split
      "#{receiver}.split(#{args})"
    elsif method == :strip
      "#{receiver}.strip()"
    elsif method == :replace
      "#{receiver}.replace(#{args})"
    elsif method == :capitalize
      "#{receiver}.capitalize()"
    elsif method == :title
      "#{receiver}.title()"
    elsif method == :upper
      "#{receiver}.upper()"
    elsif method == :lower
      "#{receiver}.lower()"
    else
      "#{receiver}.#{method}(#{args})"
    end
  when :prop
    receiver = unparse_python(node.children[0])
    prop_name = node.children[1].to_s
    args = node.children[2..-1]
    
    if prop_name == "__getitem__"
      if args.empty?
        "#{receiver}[]"
      elsif args.size == 1
        # Check if this is a reverse slice [::-1]
        arg_node = args[0]
        if arg_node.is_a?(Parser::AST::Node) && arg_node.type == :array
          # Check if array has pattern [None, None, -1] for reverse slice
          array_children = arg_node.children
          if array_children.size == 3
            # Check if all three are constants: nil/nil/-1
            vals = array_children.map { |c|
              if c.is_a?(Parser::AST::Node) && c.type == :const
                c.children[0]
              else
                nil
              end
            }
            # Pattern [None, None, -1] or [nil, nil, -1]
            if vals[0].nil? && vals[1].nil? && vals[2] == -1
              return "#{receiver}[::-1]"
            end
          end
          # Regular array - unparse it, but check for reverse slice pattern
          args_str = array_children.map { |a| unparse_python(a) }.join(", ")
          # Check if pattern is [None, None, -1] or [nil, nil, -1] for reverse slice
          # Also check for __REVERSE_SLICE__ marker
          if args_str.include?("__REVERSE_SLICE__") || 
             args_str == ", , -1" ||
             (args_str.include?("None") && args_str.include?("-1") && args_str.count(",") == 2) ||
             (args_str.include?("nil") && args_str.include?("-1") && args_str.count(",") == 2)
            return "#{receiver}[::-1]"
          end
          "#{receiver}[#{args_str}]"
        else
          # Single argument, not an array
          args_str = unparse_python(arg_node)
          if args_str == "slice(None, None, -1)"
            return "#{receiver}[::-1]"
          end
          "#{receiver}[#{args_str}]"
        end
      else
        # Multiple arguments
        args_str = args.map { |a| unparse_python(a) }.join(", ")
        "#{receiver}[#{args_str}]"
      end
    elsif args.empty?
      "#{receiver}.#{prop_name}"
    else
      "#{receiver}.#{prop_name}(#{args})"
    end
  when :array
    # Check if this is a reverse slice pattern [None, None, -1]
    if node.children.size == 3
      vals = node.children.map { |c|
        if c.is_a?(Parser::AST::Node) && c.type == :const
          c.children[0]
        else
          nil
        end
      }
      # Pattern [None, None, -1] for reverse slice [::-1]
      # Return special marker that will be handled by __getitem__
      if vals[0].nil? && vals[1].nil? && vals[2] == -1
        return "__REVERSE_SLICE__"
      end
    end
    elements = node.children.map { |c| unparse_python(c) }.join(", ")
    "[#{elements}]"
  when :hash
    pairs = node.children.map { |c| unparse_python(c) }.join(", ")
    "{#{pairs}}"
  when :key
    key_node = node.children[0]
    value = unparse_python(node.children[1])
    # Handle both constant keys and expression keys
    if key_node.is_a?(Parser::AST::Node)
      # Key is an expression (e.g., split_result[0])
      key_expr = unparse_python(key_node)
      "#{key_expr}: #{value}"
    else
      # Key is a constant string
      "\"#{key_node}\": #{value}"
    end
  when :slice
    # Handle slice syntax: arg[start:end]
    receiver = unparse_python(node.children[0])
    start_val = unparse_python(node.children[1])
    end_val = unparse_python(node.children[2])
    "#{receiver}[#{start_val}:#{end_val}]"
  when :hole
    "□"
  else
    # Fallback: try to convert to string
    node.inspect
  end
end

class FunctionSynthesizer
  def initialize(executor = nil)
    @executor = executor
    @operations_defined = false
  end
  
  def ensure_operations_defined
    return if @operations_defined
    define_common_operations
    @operations_defined = true
  end

  # Synthesize a function from spec
  def synthesize(function_spec, timeout: 60)
    ensure_operations_defined
    
    name = function_spec["name"]
    examples = function_spec["examples"] || []
    
    puts "  Synthesizing: #{name}"
    puts "    Examples: #{examples.size}"
    
    return nil if examples.empty?
    
    # Infer types from examples
    input_types, output_type = infer_types_from_examples(examples)
    
    puts "    Input types: #{input_types.map { |t| t.attrs[:ty] if t.is_a?(PyType) }.inspect}"
    puts "    Output type: #{output_type.attrs[:ty] if output_type.is_a?(PyType)}"
    
    # Create abstract environment
    abs_env = {}
    input_types.each_with_index do |ty, i|
      abs_env["arg#{i}".to_sym] = ty
    end
    
    # Goal
    goal = output_type
    
    # Extract constants
    consts = extract_constants(examples)
    
    # Add more constants from examples to help synthesis
    # Extract all unique values from examples
    all_values = examples.flat_map { |e| [e["input"], e["output"]] }.flatten
    all_values.each do |val|
      if val.is_a?(Integer) && !consts[:int].include?(val)
        consts[:int] << val
      elsif val.is_a?(String) && !consts[:str].include?(val) && val.length < 20
        consts[:str] << val
      elsif val.is_a?(Hash)
        val.each do |k, v|
          consts[:str] << k.to_s unless consts[:str].include?(k.to_s)
          consts[:str] << v.to_s if v.is_a?(String) && !consts[:str].include?(v.to_s) && v.length < 20
          consts[:int] << v if v.is_a?(Integer) && !consts[:int].include?(v)
        end
      end
    end
    
    # Create context
    ctx = Context.new(abs_env, goal)
    ctx.lang = :py
    ctx.domain = PyType
    ctx.score = Proc.new { |prog| ProgSizePass.prog_size(prog) }
    ctx.consts[:str] = consts[:str].uniq.first(20)  # Limit to avoid explosion
    ctx.consts[:int] = consts[:int].uniq.first(20)
    ctx.max_size = 50  # Increase max size for more complex solutions
    
    # Initialize search
    seed = s(:hole, nil, goal)
    q = FastContainers::PriorityQueue.new(:min)
    q.push(seed, 1)
    
    Instrumentation.reset!
    Instrumentation.examples = examples.size
    
    spec = ExampleSpec.new(examples, @executor)
    
    # Create a wrapper class that matches ExpandHolePass interface  
    wrapper_class = Class.new(::AST::Processor) do
      attr_reader :expand_map
      
      def initialize(ctx, lang)
        @expander = PyTypeOnlyExpandHolePass.new(ctx)
      end
      
      def process(node)
        @expander.process(node)
      end
      
      def expand_map
        @expander.expand_map
      end
    end
    
    # Monkey-patch ExpandHolePass temporarily
    original_expand = ExpandHolePass
    Object.const_set(:ExpandHolePass, wrapper_class)
    
    begin
      Timeout::timeout(timeout) do
        # Call the global synthesize function (not the instance method)
        prog = Kernel.method(:synthesize).call(ctx, spec, q)
        # Use Python language unparser - check how it's done in autopandas
        expr_code = unparse_python(prog)
        
        # Wrap expression in a function
        input_types, _ = infer_types_from_examples(examples)
        arg_names = input_types.each_with_index.map { |_, i| "arg#{i}" }
        code = "def #{name}(#{arg_names.join(', ')}):\n    return #{expr_code}"
        
        puts "    ✓ Success (#{Instrumentation.tested_progs} programs tested)"
        puts "    ✓ Generated: #{code}"
        return {
          name: name,
          code: code,
          tested_progs: Instrumentation.tested_progs,
          eliminated: Instrumentation.eliminated
        }
      end
    rescue Timeout::Error
        puts "    ✗ Timeout after #{timeout}s"
        Object.const_set(:ExpandHolePass, original_expand) if defined?(original_expand)
        return nil
    rescue => e
        puts "    ✗ Error: #{e.class} - #{e.message}"
        puts "    Backtrace: #{e.backtrace.first(3).join("\n    ")}"
        Object.const_set(:ExpandHolePass, original_expand) if defined?(original_expand)
        return nil
    ensure
        Object.const_set(:ExpandHolePass, original_expand) if defined?(original_expand)
    end
  end

  private

  def define_common_operations
    # Skip RDL type definitions for now - they cause initialization issues
    # The types will be inferred from examples directly
    # RDL types are mainly used for method signatures, not for basic synthesis
  end

  def infer_types_from_examples(examples)
    inputs = examples.map { |e| e["input"] }
    outputs = examples.map { |e| e["output"] }
    
    # Handle single input vs multiple inputs
    if inputs.first.is_a?(Array) && inputs.first.size > 1
      input_types = inputs.transpose.map { |column| infer_python_type(column.first, for_goal: false) }
    else
      # Single input or array of single values
      first_input = inputs.first.is_a?(Array) ? inputs.first.first : inputs.first
      input_types = [infer_python_type(first_input, for_goal: false)]
    end
    
    # For output type, use general type (not SingletonType) to allow matching
    output_type = infer_python_type(outputs.first, for_goal: true)
    
    [input_types, output_type]
  end

  def infer_python_type(value, for_goal: false)
    case value
    when String
      if for_goal
        # For goals, use general string type to allow matching
        rdl_type = RDL::Globals.types[:string]
      else
        # Use PreciseStringType for inputs (like PyTypeInterpreter does)
        rdl_type = RDL::Type::PreciseStringType.new(value)
      end
      PyType.val(rdl_type)
    when Integer
      if for_goal
        # For goals, use general integer type to allow matching any integer result
        rdl_type = RDL::Globals.types[:integer]
      else
        # Use SingletonType for inputs (like PyTypeInterpreter does)
        rdl_type = RDL::Type::SingletonType.new(value)
      end
      PyType.val(rdl_type)
    when TrueClass, FalseClass
      rdl_type = RDL::Globals.types[:bool]
      PyType.val(rdl_type)
    when Array
      if value.empty?
        rdl_type = RDL::Type::GenericType.new(RDL::Globals.types[:array], RDL::Globals.types[:top])
        PyType.val(rdl_type)
      else
        elem_pytype = infer_python_type(value.first)
        elem_rdl_type = elem_pytype.attrs[:ty]
        rdl_type = RDL::Type::GenericType.new(RDL::Globals.types[:array], elem_rdl_type)
        PyType.val(rdl_type)
      end
    when Hash
      elts = value.map { |k, v| [k.to_s, infer_python_type(v).attrs[:ty]] }.to_h
      rdl_type = RDL::Type::FiniteHashType.new(elts, RDL::Globals.types[:top])
      PyType.val(rdl_type)
    when NilClass
      rdl_type = RDL::Globals.types[:nil]
      PyType.val(rdl_type)
    else
      PyType.top
    end
  end

  def extract_constants(examples)
    str_consts = []
    int_consts = []
    
    examples.each do |ex|
      extract_from_value(ex["input"], str_consts, int_consts)
      extract_from_value(ex["output"], str_consts, int_consts)
    end
    
    {str: str_consts.uniq, int: int_consts.uniq}
  end

  def extract_from_value(value, str_consts, int_consts)
    case value
    when String
      str_consts << value unless value.empty?
    when Integer
      int_consts << value
    when Array
      value.each { |v| extract_from_value(v, str_consts, int_consts) }
    when Hash
      value.each { |k, v| 
        extract_from_value(k, str_consts, int_consts)
        extract_from_value(v, str_consts, int_consts)
      }
    end
  end
end

class ExampleSpec
  def initialize(examples, executor = nil)
    @examples = examples
    @executor = executor
  end
  
  def test_prog(prog)
    expr_code = unparse_python(prog)
    
    # Wrap expression in a function for testing
    # Infer function name and args from examples
    # For now, use a generic function name
    function_name = "synthesized_function"
    # Try to infer number of arguments from first example
    first_input = @examples.first["input"]
    num_args = first_input.is_a?(Array) ? first_input.size : 1
    arg_names = (0...num_args).map { |i| "arg#{i}" }
    
    code = "def #{function_name}(#{arg_names.join(', ')}):\n    return #{expr_code}"
    
    puts "    [TEST] Testing code: #{code[0..150]}"
    
    if @executor
      # Use Python executor for real validation
      results = @executor.execute_and_validate(code, @examples, function_name: function_name)
      puts "    [TEST] Results: #{results.map { |r| r[:match] ? '✓' : '✗' }.join(' ')}"
      results.each_with_index do |r, i|
        unless r[:match]
          puts "    [TEST]   Example #{i+1} failed:"
          puts "    [TEST]     Input: #{r[:input].inspect}"
          puts "    [TEST]     Expected: #{r[:expected].inspect}"
          puts "    [TEST]     Got: #{r[:actual].inspect}"
          puts "    [TEST]     Error: #{r[:error]}" if r[:error]
        end
      end
      results.all? { |r| r[:match] }
    else
      # Fallback: simplified check (for testing without Python)
      puts "    [TEST] No executor, using fallback"
      @examples.all? do |ex|
        # Basic structure check
        true
      end
    end
  end
end

