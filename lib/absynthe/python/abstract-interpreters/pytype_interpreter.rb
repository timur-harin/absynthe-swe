# The abstract interpter for Pandas methods defined using the RDL types domain
module Python
  class PyTypeInterpreter < AbstractInterpreter
    ::DOMAIN_INTERPRETER[PyType] = self

    def self.domain
      PyType
    end

    def self.interpret(env, node)
      case node.type
        # returns the types of constants and variables
      when :const
        konst = node.children[0]
        case konst
        when AbstractDomain
          konst
        when Integer
          domain.val(RDL::Type::SingletonType.new(konst))
        when String
          # domain.val(RDL::Globals.types[:string])
          domain.val(RDL::Type::PreciseStringType.new(konst))
        when NUnique, PyInt
          domain.val(RDL::Type::NominalType.new(konst.class))
        when Symbol
          # assume all environment maps to abstract values
          env[konst]
        when true
          domain.val(RDL::Globals.types[:true])
        when false
          domain.val(RDL::Globals.types[:false])
        else
          raise AbsyntheError, "unexpected constant type #{konst}"
        end
      when :key
        # warning: does not return an abstract domain!!
        # Handle both constant keys and expression keys
        key_node = node.children[0]
        value_node = node.children[1]
        
        # If key is a constant string, use it directly
        if key_node.is_a?(Parser::AST::Node) && key_node.type == :const && key_node.children[0].is_a?(String)
          key_str = key_node.children[0]
        elsif key_node.is_a?(String)
          key_str = key_node
        elsif key_node.is_a?(Parser::AST::Node)
          # Key is an expression (e.g., split_result[0])
          # Interpret it to get the type, but we can't get the concrete value
          # For FiniteHashType, we need string keys, so we'll use a placeholder
          # In practice, this will be evaluated at runtime
          key_val = interpret(env, key_node)
          # If it's a string type, we can use a generic key
          # For now, use a placeholder that will match any string key
          key_str = nil  # Will be handled specially
        else
          key_str = key_node.to_s
        end
        
        v = interpret(env, value_node)
        
        # If key is an expression, we can't create a FiniteHashType with specific keys
        # Return a more general dict type or use placeholder
        if key_str.nil?
          # For dynamic keys from expressions, we can't create FiniteHashType
          # Return a generic dict type
          return [nil, v.attrs[:ty]]  # Signal that key is dynamic
        else
          [key_str, v.attrs[:ty]]
        end
      # retuns the hash type or a finite hash type
      when :hash
        PyType.val(RDL::Type::FiniteHashType.new(
          node.children.map { |elt| interpret(env, elt)}
            .to_h, nil))
      # nominal arrays or generic type of arrays
      when :array
        # TODO(unsound): iterate over all items in the array
        # TODO: handle empty arrays
        item0 = node.children[0]
        v = interpret(env, item0)
        node.children[1..].each { |k| v = domain.val(RDL::Type::UnionType.new(v.attrs[:ty], interpret(env, k).attrs[:ty])) }
        domain.val(RDL::Type::GenericType.new(RDL::Globals.types[:array], v.attrs[:ty].canonical)).promote
      # properties and method calls are resolved by looking up the RDL class table
      # checking if the arguments are a subtype and then return the type in the retuns position from the signature
      when :prop, :send
        recv = interpret(env, node.children[0])
        meth_name = node.children[1]
        args = node.children[2..].map { |n|
          interpret(env, n)
        }

        trecv = recv.attrs[:ty]
        
        # Handle special cases for arithmetic operations
        if meth_name == :__add__ || meth_name == :__mul__
          # Addition/Multiplication: try to infer result type
          arg_ty = args[0] ? args[0].attrs[:ty] : nil
          
          # Check if both are integers (including SingletonType)
          recv_is_int = begin
            trecv <= RDL::Globals.types[:integer]
          rescue
            trecv.is_a?(RDL::Type::SingletonType) && trecv.val.is_a?(Integer)
          end
          
          arg_is_int = if arg_ty
            begin
              arg_ty <= RDL::Globals.types[:integer]
            rescue
              arg_ty.is_a?(RDL::Type::SingletonType) && arg_ty.val.is_a?(Integer)
            end
          else
            false
          end
          
          if recv_is_int && arg_is_int
            # Return general integer type (not SingletonType) to allow matching with goal
            op_name = meth_name == :__add__ ? "+" : "*"
            puts "  [DEBUG] Interpreting __#{meth_name}__: #{trecv.inspect} #{op_name} #{arg_ty.inspect} -> Integer"
            return domain.val(RDL::Globals.types[:integer])
          end
          
          # Check if both are strings (only for addition)
          if meth_name == :__add__
            recv_is_str = begin
              trecv <= RDL::Globals.types[:string]
            rescue
              trecv.is_a?(RDL::Type::PreciseStringType)
            end
            
            arg_is_str = if arg_ty
              begin
                arg_ty <= RDL::Globals.types[:string]
              rescue
                arg_ty.is_a?(RDL::Type::PreciseStringType)
              end
            else
              false
            end
            
            if recv_is_str && arg_is_str
              puts "  [DEBUG] Interpreting __add__: #{trecv.inspect} + #{arg_ty.inspect} -> String"
              return domain.val(RDL::Globals.types[:string])
            end
          end
        end
        
        # Look up method in RDL info
        meths = nil
        if trecv.is_a? RDL::Type::GenericType
          meths = RDL::Globals.info.info[trecv.base.to_s]
        elsif trecv.is_a? RDL::Type::NominalType
          meths = RDL::Globals.info.info[trecv.to_s]
        elsif trecv <= RDL::Globals.types[:integer]
          # Try Integer class
          meths = RDL::Globals.info.info["Integer"]
        elsif trecv <= RDL::Globals.types[:string]
          # Try String class
          meths = RDL::Globals.info.info["String"]
        end
        
        # Handle string slicing with __getitem__ (including reverse slice [::-1])
        if meth_name == :__getitem__ && args.size >= 1
          if begin
                trecv <= RDL::Globals.types[:string]
              rescue
                trecv.is_a?(RDL::Type::PreciseStringType)
              end
            # Check if this is a reverse slice [::-1]
            arg_node = args[0]
            if arg_node.is_a?(Parser::AST::Node) && arg_node.type == :array
              array_children = arg_node.children
              # Check if array contains -1 and None/nil (reverse slice pattern)
              has_neg_one = array_children.any? { |c|
                c.is_a?(Parser::AST::Node) && c.type == :const && c.children[0] == -1
              }
              has_none = array_children.any? { |c|
                c.is_a?(Parser::AST::Node) && c.type == :const && c.children[0].nil?
              }
              if has_neg_one && (has_none || array_children.size == 3)
                puts "  [DEBUG] Interpreting string reverse slice: #{trecv.inspect}[::-1] -> String"
                return domain.val(RDL::Globals.types[:string])
              end
            end
            # Regular slice
            puts "  [DEBUG] Interpreting string slice: #{trecv.inspect}[...] -> String"
            return domain.val(RDL::Globals.types[:string])
          end
        end
        
        if meths.nil? || !meths[meth_name]
          # Fallback: return top if method not found
          return domain.top
        end

        ret_ty = domain.top

        meths[meth_name][:type].filter { |ty|
          ty.args.size == args.size
        }.each { |meth_ty|
          tc = args.map.with_index { |arg, i|
            res = arg <= PyType.val(meth_ty.args[i])
            res = arg.promote <= PyType.val(meth_ty.args[i]) unless res
            res
          }.all?

          if tc
            if meth_ty.ret.is_a? RDL::Type::VarType
              # assume trecv is GenericType
              params = RDL::Wrap.get_type_params(trecv.base.to_s)[0]
              idx = params.index(meth_ty.ret.name)
              raise RbSynError, "unexpected" if idx.nil?
              ret_ty = domain.val(trecv.params[idx])
            else
              ret_ty = domain.val(meth_ty.ret)
            end
            break
          end
        }

        # puts "===="
        # puts node.children[0] if ret_ty.top?
        # puts node.children[1] if ret_ty.top?
        # puts node.children[2] if ret_ty.top?
        # puts args if ret_ty.top?
        # puts meths[meth_name][:type][0].args if ret_ty.top?
        # puts "==> #{args[0] <= PyType.val(meths[meth_name][:type][0].args[0])}" if ret_ty.top?

        ret_ty
      # holes returns the abstract values projected into the RDL Types domain
      when :hole
        eval_hole(node)
      when :slice
        # Handle slice operation: slice(receiver, start, end) -> string
        recv = interpret(env, node.children[0])
        trecv = recv.attrs[:ty]
        if begin
              trecv <= RDL::Globals.types[:string]
            rescue
              trecv.is_a?(RDL::Type::PreciseStringType)
            end
          puts "  [DEBUG] Interpreting slice: #{trecv.inspect}[start:end] -> String"
          return domain.val(RDL::Globals.types[:string])
        else
          return domain.top
        end
      else
        raise AbsyntheError, "unexpected AST node #{node.type}"
      end
    end
  end
end
