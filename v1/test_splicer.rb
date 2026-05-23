require 'parser/current'
require 'unparser'
require_relative 'prism'

puts "\e[34;1m=== Starting Deterministic Splicer & Amb Test ===\e[0m"
puts "We are feeding two slightly broken Ruby implementations for solve(x, y) = x * 2 + y"
puts "Target tests: solve(5, 3) = 13, solve(10, 4) = 24"

# Broken Idea 1: x + 2 + y  (has '+' instead of '*')
idea1 = <<~RUBY
  def solve(x, y)
    x + 2 + y
  end
RUBY

# Broken Idea 2: x * 2 - y  (has '-' instead of '+')
idea2 = <<~RUBY
  def solve(x, y)
    x * 2 - y
  end
RUBY

ast_trees = [ASTMutator.parse(idea1), ASTMutator.parse(idea2)]
test_cases = [
  { inputs: [5, 3], expected: 13 },
  { inputs: [10, 4], expected: 24 }
]

puts "\nInput Idea 1:\n#{idea1}"
puts "Input Idea 2:\n#{idea2}"

puts "\nRunning Amb backtracking search..."

amb = Amb.new
tries = 0
success_code = nil

while amb.has_more?
  amb.reset_pass
  begin
    begin
      tries += 1
      
      # 1. Choose base AST
      base_ast = amb.choose(ast_trees)
      
      # 2. Choose mutation type (let's only try op_swap and crossover to demonstrate them)
      mut_type = amb.choose([:op_swap, :crossover])
      
      mutated_ast = case mut_type
      when :op_swap
        # Collect send nodes representing operators
        op_nodes = ASTMutator.collect_nodes(base_ast).select { |e|
          e[:node].type == :send && e[:node].children[0].is_a?(Parser::AST::Node)
        }
        
        target_send = amb.choose(op_nodes)[:node]
        new_op = amb.choose([:+, :-, :*, :/, :**, :%])
        
        ASTMutator.mutate_operators(base_ast, target_send, new_op)
        
      when :crossover
        donor_ast = amb.choose(ast_trees)
        
        base_nodes = ASTMutator.collect_nodes(base_ast).select { |e| 
          [:send, :lvar, :int].include?(e[:node].type)
        }
        donor_nodes = ASTMutator.collect_nodes(donor_ast).select { |e|
          [:send, :lvar, :int].include?(e[:node].type)
        }
        
        base_entry = amb.choose(base_nodes)
        donor_entry = amb.choose(donor_nodes)
        
        ASTMutator.replace_node(base_ast, base_entry[:node], donor_entry[:node])
      end
      
      candidate_code = ASTMutator.unparse(mutated_ast)
      
      # Evaluate candidate
      Sandbox.run_tests(candidate_code, "solve", test_cases)
      
      success_code = candidate_code
      puts "\e[32;1m\n[AMB SUCCESS] Found working code on pass ##{tries}!\e[0m"
      puts "Mutation Path: #{mut_type.to_s.upcase}"
      puts "\e[32mSynthesized Code:\e[0m"
      puts candidate_code
      break
    rescue => e
      # Log failure and invoke Amb failure to backtrack (raising Amb::Backtrack)
      # puts "[AMB Pass ##{tries} Failed] #{e.message}. Backtracking..."
      amb.failure
    end
  rescue Amb::Backtrack
    next
  rescue Amb::NoMoreChoices
    break
  end
end

if success_code
  puts "\n\e[32;1m=== Deterministic Test Passed successfully! ===\e[0m"
else
  puts "\n\e[31;1m=== Deterministic Test Failed to find a solution! ===\e[0m"
end
