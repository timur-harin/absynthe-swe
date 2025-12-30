# The following algorithm is described with reference of Absynthe paper: Algorithm 1

def synthesize(ctx, spec, q)
  if ctx.lang == :sygus
    lang = spec.lang
  else
    lang = nil
  end

  # line 5
  until q.empty? do
    # line 6
    current = q.top
    q.pop

    # next few lines are for line 7
    pass = ExpandHolePass.new(ctx, lang)
    # puts Sygus::unparse(current)
    # puts current
    expanded = pass.process(current)
    expand_map = pass.expand_map.map { |i| i.times.to_a }
    puts "  [DEBUG] Expand map: #{expand_map.inspect}"
    puts "  [DEBUG] Expand map sizes: #{expand_map.map(&:size).inspect}"
    if expand_map.empty?
      candidates = [current]
      puts "  [DEBUG] No expansions, using current as candidate"
    else
      candidates = expand_map[0].product(*expand_map[1..])
      puts "  [DEBUG] Generated #{candidates.size} candidates from expansions"
      if candidates.size > 0
        puts "  [DEBUG] First candidate selection: #{candidates.first.inspect}"
      end
    end
    puts "  [DEBUG] Processing #{candidates.size} candidates..."
    candidates.each_with_index { |selection, idx|
      if idx < 3 || idx % 100 == 0
        puts "  [DEBUG] Processing candidate #{idx + 1}/#{candidates.size}"
      end
      extract_pass = ExtractASTPass.new(selection)
      prog = extract_pass.process(expanded)
      hc_pass = HoleCountPass.new
      hc_pass.process(prog)
      total_holes = hc_pass.num_holes + hc_pass.num_depholes
      
      if idx < 3
        puts "  [DEBUG] Candidate #{idx + 1}: holes=#{total_holes} (regular=#{hc_pass.num_holes}, dep=#{hc_pass.num_depholes})"
      end
      
      if total_holes > 0
        # if not satisfied by goal abstract value, program is rejected
        interpreter = AbstractInterpreter.interpreter_from(ctx.domain)
        absval = begin
          interpreter.interpret(ctx.init_env, prog)
        rescue => e
          puts "  [DEBUG] Error interpreting candidate #{idx + 1}: #{e.message}"
          puts "  [DEBUG]   Program: #{prog.inspect[0..200]}"
          raise
        end
        
        # Debug: print first few candidates
        if idx < 3
          puts "  [DEBUG]   absval: #{absval.inspect}"
          puts "  [DEBUG]   goal: #{ctx.goal.inspect}"
        end

        # next few lines are for line 8
        # solve dependent holes at <=, model gives value to remaining hole
        absval_le_goal = begin
          result = absval <= ctx.goal
          if idx < 3
            puts "  [DEBUG]   absval <= goal: #{result}"
          end
          result
        rescue => e
          puts "  [DEBUG] Error comparing absval <= goal: #{e.message}"
          puts "  [DEBUG]   absval class: #{absval.class}, goal class: #{ctx.goal.class}"
          false
        end
        
        if !absval_le_goal && idx < 3
          puts "  [DEBUG]   Candidate rejected: absval not <= goal"
        end
        
        if absval_le_goal
          if idx < 3
            puts "  [DEBUG]   Candidate accepted! Adding to queue"
          end
          if hc_pass.num_holes == 0
            dephole_replacer = ReplaceDepholePass.new(ctx, hc_pass.num_depholes)
            if hc_pass.num_depholes > 0
              prog = dephole_replacer.process(prog)
            else
              raise AbsyntheError, "invariant of 1 dephole broken"
            end
          end
          score = ctx.score.call(prog)
          size = ProgSizePass.prog_size(prog)
          # line 15
          q.push(prog, score) if size <= ctx.max_size
        else
          Instrumentation.eliminated += 1
        end
      else
        # line 12 - no holes left, test the program
        if idx < 3
          puts "  [DEBUG] Testing candidate #{idx + 1} (no holes)"
          puts "  [DEBUG]   Program: #{prog.inspect[0..200]}"
        end
        test_result = begin
          spec.test_prog(prog)
        rescue => e
          if idx < 3
            puts "  [DEBUG]   Test error: #{e.message}"
          end
          false
        end
        if test_result
          puts "  [DEBUG] ✓ Solution found! Candidate #{idx + 1} passed tests"
          return prog
        else
          Instrumentation.tested_progs += 1
          if idx < 3
            puts "  [DEBUG]   Candidate #{idx + 1} failed tests"
          end
        end
      end
    }
  end
  raise AbsyntheError, "No candidates found!"
end
