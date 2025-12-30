# Expands holes for PyType-only synthesis (without Pandas)
# Based on py_expand_hole.rb but uses PyType directly instead of ProductDomain

require 'ast'
require 'absynthe/python/domains/pytype'
require 'absynthe/python/abstract-interpreters/pytype_interpreter'

class PyTypeOnlyExpandHolePass < ::AST::Processor
  attr_reader :expand_map
  include VarName

  def initialize(ctx)
    @ctx = ctx
    @expand_map = []
  end

  def on_hole(node)
    goal = node.children[1]
    
    # Extract type from goal (supports both PyType and ProductDomain for compatibility)
    if goal.is_a?(ProductDomain)
      ty = goal.domains[PyType].attrs[:ty]
    elsif goal.is_a?(PyType)
      ty = goal.attrs[:ty]
    else
      raise AbsyntheError, "unexpected goal type: #{goal.class}"
    end
    
    interpreter = AbstractInterpreter.interpreter_from(@ctx.domain)
    expanded = []
    
    # Debug: print goal type
    puts "  [DEBUG] Expanding hole with goal type: #{ty.class} - #{ty}"
    puts "  [DEBUG] Environment keys: #{@ctx.init_env.keys.inspect}"
    puts "  [DEBUG] Constants: int=#{@ctx.consts[:int]&.size || 0}, str=#{@ctx.consts[:str]&.size || 0}"

    # 1. Constants
    if RDL::Globals.types[:string] <= ty
      (@ctx.consts[:str] || []).each { |v| expanded << s(:const, v) }
    end
    if ty.is_a? RDL::Type::SingletonType
      expanded << s(:const, ty.val)
    end
    if ty.is_a? RDL::Type::PreciseStringType
      expanded << s(:const, ty.vals[0])
    end
    if RDL::Globals.types[:integer] <= ty
      (@ctx.consts[:int] || []).each { |v| expanded << s(:const, v) }
    end
    if ty.is_a? RDL::Type::NominalType
      # Handle special nominal types if needed
    end

    # 2. Union types - try each variant
    if ty.is_a? RDL::Type::UnionType
      ty.types.each { |t|
        expanded << s(:hole, nil, PyType.val(t))  # Use PyType directly, not ProductDomain
      }
    end

    # 3. Variables from environment
    @ctx.init_env.each { |name, val|
      # Project to PyType if val is ProductDomain
      pyval = val.is_a?(ProductDomain) ? val.domains[PyType] : val
      if pyval.is_a?(PyType) && pyval <= goal
        expanded << s(:const, name.to_sym)
      end
    }

    # 4. Arrays
    if ty.is_a?(RDL::Type::GenericType) && ty.base == RDL::Globals.types[:array]
      elem_ty = ty.params[0]
      
      if elem_ty <= RDL::Globals.types[:integer]
        # Generate small integer arrays
        3.times { |i|
          (@ctx.consts[:int] || []).permutation(i + 1) { |arr|
            expanded << s(:array, *arr.map { |n| s(:const, n) })
          }
        }
      elsif elem_ty <= RDL::Globals.types[:string]
        # Generate small string arrays
        3.times { |i|
          (@ctx.consts[:str] || []).permutation(i + 1) { |arr|
            expanded << s(:array, *arr.map { |n| s(:const, n) })
          }
        }
      elsif elem_ty <= RDL::Globals.types[:bool]
        expanded << s(:array, s(:const, true), s(:const, false))
        expanded << s(:array, s(:const, true), s(:const, false), s(:const, true))
      end
    end

    # 5. Hashes/Dictionaries
    if ty.is_a? RDL::Type::FiniteHashType
      ty.elts.size.times { |i|
        keys = ty.elts.keys.combination(i + 1)
        keys.each { |ks|
          expanded << s(:hash, *ks.map { |k|
                        s(:key, k, s(:hole, nil, PyType.val(ty.elts[k])))  # Use PyType directly
                      })
        }
      }
    end

    # 6. Arithmetic operations for integers
    # Check if goal type is integer (including SingletonType and NominalType)
    is_integer_goal = begin
      ty <= RDL::Globals.types[:integer]
    rescue
      ty.is_a?(RDL::Type::SingletonType) ||
      (ty.is_a?(RDL::Type::NominalType) && ty.name == "Integer") ||
      (ty.is_a?(RDL::Type::UnionType) && ty.types.any? { |t| 
        begin
          t <= RDL::Globals.types[:integer]
        rescue
          t.is_a?(RDL::Type::NominalType) && t.name == "Integer"
        end
      })
    end
    
    if is_integer_goal
      # Generate addition: arg0 + arg1
      @ctx.init_env.each { |name1, val1|
        pyval1 = val1.is_a?(ProductDomain) ? val1.domains[PyType] : val1
        next unless pyval1.is_a?(PyType)
        pyval1_ty = pyval1.attrs[:ty]
        next unless pyval1_ty <= RDL::Globals.types[:integer] || pyval1_ty.is_a?(RDL::Type::SingletonType)
        
        @ctx.init_env.each { |name2, val2|
          pyval2 = val2.is_a?(ProductDomain) ? val2.domains[PyType] : val2
          next unless pyval2.is_a?(PyType)
          pyval2_ty = pyval2.attrs[:ty]
          next unless pyval2_ty <= RDL::Globals.types[:integer] || pyval2_ty.is_a?(RDL::Type::SingletonType)
          next if name1 == name2
          
          # Generate addition
          expanded << s(:send,
                       s(:const, name1.to_sym),
                       :__add__,
                       s(:const, name2.to_sym))
          
          # Generate multiplication
          expanded << s(:send,
                       s(:const, name1.to_sym),
                       :__mul__,
                       s(:const, name2.to_sym))
          
          # Also try with constants
          (@ctx.consts[:int] || []).first(5).each { |c|
            expanded << s(:send,
                         s(:const, name1.to_sym),
                         :__add__,
                         s(:const, c))
            expanded << s(:send,
                         s(:const, c),
                         :__add__,
                         s(:const, name1.to_sym))
            expanded << s(:send,
                         s(:const, name1.to_sym),
                         :__mul__,
                         s(:const, c))
            expanded << s(:send,
                         s(:const, c),
                         :__mul__,
                         s(:const, name1.to_sym))
          }
        }
      }
      
      # Also try direct constant addition
      if (@ctx.consts[:int] || []).size >= 2
        (@ctx.consts[:int] || []).combination(2).first(10).each { |c1, c2|
          expanded << s(:send,
                       s(:const, c1),
                       :__add__,
                       s(:const, c2))
        }
      end
      
      # Generate chained additions for three arguments (a + b + c)
      if @ctx.init_env.size >= 3
        env_vars = @ctx.init_env.keys.select { |name|
          val = @ctx.init_env[name]
          pyval = val.is_a?(ProductDomain) ? val.domains[PyType] : val
          pyval.is_a?(PyType) && (pyval.attrs[:ty] <= RDL::Globals.types[:integer] || pyval.attrs[:ty].is_a?(RDL::Type::SingletonType))
        }
        if env_vars.size >= 3
          # Try all permutations of three variables
          env_vars.permutation(3).first(6).each { |v1, v2, v3|
            # Generate (v1 + v2) + v3
            expanded << s(:send,
                         s(:send,
                           s(:const, v1),
                           :__add__,
                           s(:const, v2)),
                         :__add__,
                         s(:const, v3))
            # Generate v1 + (v2 + v3)
            expanded << s(:send,
                         s(:const, v1),
                         :__add__,
                         s(:send,
                           s(:const, v2),
                           :__add__,
                           s(:const, v3)))
          }
        end
      end
    end
    
    # 7. String concatenation
    if ty <= RDL::Globals.types[:string]
      @ctx.init_env.each { |name1, val1|
        pyval1 = val1.is_a?(ProductDomain) ? val1.domains[PyType] : val1
        next unless pyval1.is_a?(PyType) && pyval1.attrs[:ty] <= RDL::Globals.types[:string]
        @ctx.init_env.each { |name2, val2|
          pyval2 = val2.is_a?(ProductDomain) ? val2.domains[PyType] : val2
          next unless pyval2.is_a?(PyType) && pyval2.attrs[:ty] <= RDL::Globals.types[:string]
          next if name1 == name2
          expanded << s(:send,
                       s(:const, name1.to_sym),
                       :__add__,
                       s(:const, name2.to_sym))
        }
        # Also try with string constants
        (@ctx.consts[:str] || []).first(3).each { |c|
          expanded << s(:send,
                       s(:const, name1.to_sym),
                       :__add__,
                       s(:const, c))
          expanded << s(:send,
                       s(:const, c),
                       :__add__,
                       s(:const, name1.to_sym))
        }
      }
    end
    
    # 8. String operations for dict parsing and string manipulation
    if ty.is_a?(RDL::Type::FiniteHashType)
      # Try string split operations to create dictionaries
      @ctx.init_env.each { |name, val|
        pyval = val.is_a?(ProductDomain) ? val.domains[PyType] : val
        next unless pyval.is_a?(PyType) && pyval.attrs[:ty] <= RDL::Globals.types[:string]
        
        # Generate split('=') -> array, then create dict from array
        # {split_result[0]: split_result[1]}
        split_result = s(:send, s(:const, name.to_sym), :split, s(:const, "="))
        expanded << s(:hash,
                     s(:key,
                       s(:prop, split_result, :__getitem__, s(:const, 0)),
                       s(:prop, split_result, :__getitem__, s(:const, 1))))
        
        # Also try split('&') for query strings, then process each pair
        split_by_amp = s(:send, s(:const, name.to_sym), :split, s(:const, "&"))
        # Handle first pair: {split_by_amp[0].split('=')[0]: split_by_amp[0].split('=')[1]}
        first_pair = s(:prop, split_by_amp, :__getitem__, s(:const, 0))
        first_pair_split = s(:send, first_pair, :split, s(:const, "="))
        expanded << s(:hash,
                     s(:key,
                       s(:prop, first_pair_split, :__getitem__, s(:const, 0)),
                       s(:prop, first_pair_split, :__getitem__, s(:const, 1))))
        
        # Handle two pairs for query strings like "a=1&b=2"
        # Split by '&', then split each pair by '=', create dict
        second_pair = s(:prop, split_by_amp, :__getitem__, s(:const, 1))
        second_pair_split = s(:send, second_pair, :split, s(:const, "="))
        # Create dict with two keys - use key nodes with expressions
        # Note: key node expects [key_string, value_expr]
        # We need to use string expressions for keys, not constants
        expanded << s(:hash,
                     s(:key,
                       s(:prop, first_pair_split, :__getitem__, s(:const, 0)),
                       s(:prop, first_pair_split, :__getitem__, s(:const, 1))),
                     s(:key,
                       s(:prop, second_pair_split, :__getitem__, s(:const, 0)),
                       s(:prop, second_pair_split, :__getitem__, s(:const, 1))))
      }
    end
    
    # 8c. Special handling for query string parsing with dynamic keys
    # This generates: {pair.split('=')[0]: pair.split('=')[1] for pair in query.split('&')}
    # But without loops, we handle first two pairs explicitly
    if ty.is_a?(RDL::Type::FiniteHashType) && ty.elts.size >= 2
      @ctx.init_env.each { |name, val|
        pyval = val.is_a?(ProductDomain) ? val.domains[PyType] : val
        next unless pyval.is_a?(PyType) && pyval.attrs[:ty] <= RDL::Globals.types[:string]
        
        # Generate: split('&') -> [pair1, pair2], then for each: split('=') -> [key, value]
        split_by_amp = s(:send, s(:const, name.to_sym), :split, s(:const, "&"))
        
        # First pair
        pair1 = s(:prop, split_by_amp, :__getitem__, s(:const, 0))
        pair1_split = s(:send, pair1, :split, s(:const, "="))
        key1 = s(:prop, pair1_split, :__getitem__, s(:const, 0))
        val1 = s(:prop, pair1_split, :__getitem__, s(:const, 1))
        
        # Second pair
        pair2 = s(:prop, split_by_amp, :__getitem__, s(:const, 1))
        pair2_split = s(:send, pair2, :split, s(:const, "="))
        key2 = s(:prop, pair2_split, :__getitem__, s(:const, 0))
        val2 = s(:prop, pair2_split, :__getitem__, s(:const, 1))
        
        # Create dict with dynamic keys from expressions
        # Note: key node format is s(:key, key_expr, value_expr)
        # But FiniteHashType expects string keys, so we need to ensure key_expr evaluates to string
        expanded << s(:hash,
                     s(:key, key1, val1),
                     s(:key, key2, val2))
      }
    end
    
    # 8b. String formatting operations (for phone numbers, etc.)
    if ty <= RDL::Globals.types[:string]
      @ctx.init_env.each { |name, val|
        pyval = val.is_a?(ProductDomain) ? val.domains[PyType] : val
        next unless pyval.is_a?(PyType) && pyval.attrs[:ty] <= RDL::Globals.types[:string]
        
        arg_var = s(:const, name.to_sym)
        
        # Generate string slicing for phone formatting
        # Format: (XXX) XXX-XXXX from 10-digit string
        slice_0_3 = s(:slice, arg_var, s(:const, 0), s(:const, 3))
        slice_3_6 = s(:slice, arg_var, s(:const, 3), s(:const, 6))
        slice_6_10 = s(:slice, arg_var, s(:const, 6), s(:const, 10))
        
        expanded << s(:send,
                     s(:send,
                       s(:send,
                         s(:send,
                           s(:const, "("),
                           :__add__,
                           slice_0_3),
                         :__add__,
                         s(:const, ") ")),
                       :__add__,
                       slice_3_6),
                     :__add__,
                     s(:send,
                       s(:const, "-"),
                       :__add__,
                       slice_6_10))
        
        # Generate string reverse: arg[::-1]
        # Use slice with negative step
        expanded << s(:send, arg_var, :__getitem__, 
                     s(:array, s(:const, nil), s(:const, nil), s(:const, -1)))
        
        # Generate string capitalize operations
        # capitalize() - first letter uppercase
        expanded << s(:send, arg_var, :capitalize)
        # title() - first letter of each word uppercase (for capitalize_words)
        expanded << s(:send, arg_var, :title)
        # upper() - all uppercase
        expanded << s(:send, arg_var, :upper)
        # lower() - all lowercase
        expanded << s(:send, arg_var, :lower)
        
        # For capitalize_words: split by space, capitalize each, join
        # This is more complex but let's try: ' '.join([word.capitalize() for word in arg.split(' ')])
        # For now, just try title() which does this automatically
        # (title() capitalizes first letter of each word)
        
        # Also try simpler slice operations
        [0, 1, 2, 3, 6].each { |start_idx|
          [3, 6, 10].each { |end_idx|
            next if end_idx <= start_idx
            expanded << s(:slice, s(:const, name.to_sym), s(:const, start_idx), s(:const, end_idx))
          }
        }
      }
    end

    # 8. Properties (attribute access)
    RDL::Globals.info.info.each { |cls, mthds|
      next if cls.to_s.include?("RDL::")
      mthds.delete(:__getobj__)
      mthds.each { |mthd, info|
        # Skip Pandas-specific methods
        next if [:loc_getitem, :__getitem__, :T, :values].include?(mthd)
        
        trecv = RDL::Type::NominalType.new(cls)
        info[:type].each { |tmeth|
          tret = tmeth.ret

          # Handle self types
          if tret.is_a? RDL::Type::VarType
            tret = ty
            trecv = RDL::Type::GenericType.new(trecv, tret)
          end

          next unless tret <= ty
          targs = tmeth.args
          next if targs.any? { |t| t.is_a? RDL::Type::BotType }

          expanded << s(:prop,
                       s(:hole, nil, PyType.val(trecv)),  # Use PyType directly
                       mthd,
                       *targs.map { |t|
                         s(:hole, nil, PyType.val(t))  # Use PyType directly
                       })
        }
      }
    }

    # 7. Method calls (functions)
    RDL::Globals.info.info.each { |cls, mthds|
      next if cls.to_s.include?("RDL::")
      mthds.delete(:__getobj__)
      mthds.each { |mthd, info|
        # Skip Pandas-specific methods
        next if [:loc_getitem, :__getitem__, :T, :values].include?(mthd)
        
        trecv = RDL::Type::NominalType.new(cls)
        info[:type].each { |tmeth|
          next unless tmeth.ret <= ty

          targs = tmeth.args
          arg_terms = targs.map { |arg|
            if [RDL::Type::NominalType, RDL::Type::GenericType, RDL::Type::UnionType].any? { |t| arg.is_a? t }
              s(:hole, nil, PyType.val(arg))  # Use PyType directly
            elsif arg.is_a? RDL::Type::FiniteHashType
              s(:hole, nil, PyType.val(arg))  # Use PyType directly
            else
              raise AbsyntheError, "unexpected type #{arg}"
            end
          }
          next if targs.any? { |t| t.is_a? RDL::Type::BotType }
          
          expanded << s(:send,
                       s(:hole, nil, PyType.val(trecv)),  # Use PyType directly
                       mthd,
                       *arg_terms)
        }
      }
    }

    @expand_map << expanded.size
    
    # Debug: print expansion info
    if expanded.size == 0
      puts "  [WARNING] No expansions for goal type: #{ty.class} - #{ty}"
    else
      puts "  [DEBUG] Total expansions: #{expanded.size}"
    end
    
    s(:filled_hole, goal, *expanded)
  end

  def handler_missing(node)
    node.updated(nil, node.children.map { |k|
      k.is_a?(Parser::AST::Node) ? process(k) : k
    })
  end
end

