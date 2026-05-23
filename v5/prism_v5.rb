require 'net/http'
require 'uri'
require 'json'
require 'parser/current'
require 'unparser'
require 'timeout'

# LLM Client with Parallel Multi-Temperature Llama 3.1 8B Actors
class LLMClient
  attr_reader :cerebras_keys

  def initialize(keys_file = "../dont_delete")
    @cerebras_keys = []
    load_keys(keys_file)
  end

  def load_keys(filepath)
    return unless File.exist?(filepath)

    current_section = nil
    File.foreach(filepath) do |line|
      line = line.strip
      next if line.empty?

      if line.start_with?("#")
        section = line.downcase
        if section.include?("cerebras")
          current_section = :cerebras
        else
          current_section = nil
        end
      else
        case current_section
        when :cerebras then @cerebras_keys << line
        end
      end
    end
  rescue => e
    puts "\e[33m[Warning] Failed to load keys: #{e.message}\e[0m"
  end

  def call_cerebras_with_temp(prompt, temp, key_index = 0)
    raise "No Cerebras keys found" if @cerebras_keys.empty?
    key_index = 0 if key_index >= @cerebras_keys.size
    key = @cerebras_keys[key_index]

    uri = URI("https://api.cerebras.ai/v1/chat/completions")
    payload = {
      model: "llama3.1-8b",
      messages: [{ role: "user", content: prompt }],
      temperature: temp
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.request_uri)
    request.body = payload.to_json
    request.content_type = "application/json"
    request["Authorization"] = "Bearer #{key}"

    response = http.request(request)

    if response.code == "200"
      res_data = JSON.parse(response.body)
      res_data.dig("choices", 0, "message", "content")
    elsif response.code == "429"
      puts "\e[33m[Cerebras Temp #{temp} RateLimit] Key Index #{key_index} HTTP 429. Retrying with next key...\e[0m"
      if key_index + 1 < @cerebras_keys.size
        call_cerebras_with_temp(prompt, temp, key_index + 1)
      else
        sleep 2
        call_cerebras_with_temp(prompt, temp, 0)
      end
    else
      puts "\e[31m[Cerebras Error] Key Index #{key_index} HTTP #{response.code}: #{response.body[0..150]}\e[0m"
      if key_index + 1 < @cerebras_keys.size
        call_cerebras_with_temp(prompt, temp, key_index + 1)
      else
        raise "Cerebras API call failed: #{response.body}"
      end
    end
  end

  def generate_multi_temp_impulse(prompt)
    ideas = []
    temps = [0.0, 0.5, 1.0, 1.5]
    
    temps.each do |temp|
      begin
        puts "\e[36m[LLM Actor: Cerebras Llama 3.1 8B (Temp #{temp})] Querying...\e[0m"
        res = call_cerebras_with_temp(prompt, temp)
        extracted = extract_code_blocks(res)
        puts "  -> Temp #{temp} Actor supplied #{extracted.size} templates."
        ideas += extracted
      rescue => e
        puts "\e[33m[LLM Actor: Cerebras Llama 3.1 8B (Temp #{temp})] Failed: #{e.message}\e[0m"
      end
    end
    
    ideas.map(&:strip).reject(&:empty?)
  end

  private

  def extract_code_blocks(text)
    blocks = text.scan(/```ruby\s*(.*?)\s*```/m).flatten
    if blocks.empty?
      blocks = text.scan(/```\s*(.*?)\s*```/m).flatten
    end
    blocks
  end
end

# Task-Agnostic AST DNA Splicer & Mutator
class ASTMutator
  def self.parse(code_str)
    Parser::CurrentRuby.parse(code_str)
  end

  def self.unparse(ast_tree)
    Unparser.unparse(ast_tree)
  end

  def self.collect_nodes(node, parent = nil, field_index = nil)
    return [] unless node.is_a?(Parser::AST::Node)

    results = []
    results << { node: node, parent: parent, index: field_index }

    node.children.each_with_index do |child, idx|
      if child.is_a?(Parser::AST::Node)
        results += collect_nodes(child, node, idx)
      end
    end
    results
  end

  def self.replace_node(tree, target_node, replacement_node)
    return tree unless tree.is_a?(Parser::AST::Node)
    return deep_copy(replacement_node) if tree.equal?(target_node)

    new_children = tree.children.map do |child|
      if child.is_a?(Parser::AST::Node)
        replace_node(child, target_node, replacement_node)
      else
        child
      end
    end

    Parser::AST::Node.new(tree.type, new_children)
  end

  def self.deep_copy(node)
    return node unless node.is_a?(Parser::AST::Node)
    new_children = node.children.map do |child|
      child.is_a?(Parser::AST::Node) ? deep_copy(child) : child
    end
    Parser::AST::Node.new(node.type, new_children)
  end

  def self.mutate_operators(tree, target_send_node, new_operator)
    return tree unless tree.is_a?(Parser::AST::Node)
    
    if tree.equal?(target_send_node) && tree.type == :send
      new_children = tree.children.dup
      new_children[1] = new_operator
      return Parser::AST::Node.new(tree.type, new_children)
    end

    new_children = tree.children.map do |child|
      child.is_a?(Parser::AST::Node) ? mutate_operators(child, target_send_node, new_operator) : child
    end

    Parser::AST::Node.new(tree.type, new_children)
  end

  def self.mutate_constant(tree, target_const_node, new_val)
    return tree unless tree.is_a?(Parser::AST::Node)

    if tree.equal?(target_const_node) && (tree.type == :int || tree.type == :float)
      type = new_val.is_a?(Integer) ? :int : :float
      return Parser::AST::Node.new(type, [new_val])
    end

    new_children = tree.children.map do |child|
      child.is_a?(Parser::AST::Node) ? mutate_constant(child, target_const_node, new_val) : child
    end

    Parser::AST::Node.new(tree.type, new_children)
  end

  def self.mutate_symbol(tree, target_sym_node, new_sym)
    return tree unless tree.is_a?(Parser::AST::Node)

    if tree.equal?(target_sym_node) && tree.type == :sym
      return Parser::AST::Node.new(:sym, [new_sym])
    end

    new_children = tree.children.map do |child|
      child.is_a?(Parser::AST::Node) ? mutate_symbol(child, target_sym_node, new_sym) : child
    end

    Parser::AST::Node.new(tree.type, new_children)
  end

  def self.mutate_variable(tree, target_lvar_node, new_var_sym)
    return tree unless tree.is_a?(Parser::AST::Node)

    if tree.equal?(target_lvar_node) && tree.type == :lvar
      return Parser::AST::Node.new(:lvar, [new_var_sym])
    end

    new_children = tree.children.map do |child|
      child.is_a?(Parser::AST::Node) ? mutate_variable(child, target_lvar_node, new_var_sym) : child
    end

    Parser::AST::Node.new(tree.type, new_children)
  end
end

# Candidate Genome Struct
class Candidate
  attr_accessor :ast, :code, :fitness, :score, :error, :type

  def initialize(ast)
    @ast = ast
    @code = ASTMutator.unparse(ast) rescue ""
    @fitness = 0
    @score = 0
    @error = ""
    @type = :untested
  end
end

# Isolated General-Purpose Sandbox (Task-Agnostic)
class Sandbox
  def self.evaluate_candidate!(candidate, method_name, test_cases)
    klass = Class.new
    begin
      klass.class_eval(candidate.code)
    rescue SyntaxError => e
      candidate.type = :syntax_error
      candidate.error = "SyntaxError: #{e.message}"
      candidate.fitness = 0
      return
    rescue => e
      candidate.type = :compile_error
      candidate.error = "CompileError: #{e.message}"
      candidate.fitness = 0
      return
    end

    instance = klass.new
    passed_count = 0
    candidate.fitness = 50 # Base points for compiling
    candidate.type = :success

    test_cases.each_with_index do |tc, idx|
      # Deep copy test inputs to ensure complete isolated evaluations
      inputs = Marshal.load(Marshal.dump(tc[:inputs]))
      expected = tc[:expected]

      begin
        output = nil
        Timeout.timeout(1.0) do
          output = instance.send(method_name, *inputs)
        end

        if match?(output, expected)
          passed_count += 1
          candidate.fitness += 100
        else
          candidate.error = "Test #{idx+1} expected #{expected.inspect}, got #{output.inspect}"
          candidate.type = :assertion_error
        end
      rescue Timeout::Error
        candidate.error = "TimeoutError: Test #{idx+1} timed out."
        candidate.type = :timeout_error
      rescue => e
        candidate.error = "RuntimeError on test #{idx+1}: #{e.class}: #{e.message}"
        candidate.type = :runtime_error
      end
    end

    candidate.score = passed_count
  end

  def self.match?(output, expected)
    if output.is_a?(Numeric) && expected.is_a?(Numeric)
      (output.to_f - expected.to_f).abs < 0.05
    else
      output == expected
    end
  end
end

# General-Purpose Genetic Orchestrator (Task-Agnostic)
class GeneticPrism
  def initialize(llm_client, population_size = 40, generations = 5)
    @llm = llm_client
    @pop_size = population_size
    @generations = generations
  end

  def evolve_solution(task_description, method_name, test_cases)
    puts "\e[32;1m=== Starting Unified Task-Agnostic Genetic Prism v5 ===\e[0m"
    puts "Model constraint: Cerebras llama3.1-8b exclusively (Temperatures 0.0, 0.5, 1.0, 1.5)"
    puts "Task: #{task_description[0..150]}..."
    puts "Population: #{@pop_size} | Generations per Epoch: #{@generations}"

    prompt = <<~PROMPT
      #{task_description}

      You must provide THREE completely distinct, creative, and different implementations of this method.
      Wrap each implementation in standard ruby code blocks:

      ```ruby
      # Implementation 1
      def #{method_name}(...)
        ...
      end
      ```

      ```ruby
      # Implementation 2
      def #{method_name}(...)
        ...
      end
      ```

      ```ruby
      # Implementation 3
      def #{method_name}(...)
        ...
      end
      ```

      Do not add explanations. Output ONLY the three code blocks.
    PROMPT

    epoch = 1
    max_epochs = 3
    
    while epoch <= max_epochs
      puts "\n\e[35;1m=== [Epoch #{epoch}: Multi-Temperature 8B Actors Impulse] ===\e[0m"
      seed_ideas = @llm.generate_multi_temp_impulse(prompt)
      if seed_ideas.empty?
        raise "Could not retrieve any seed ideas from Llama 3.1 8B actors."
      end

      puts "\n\e[32m[Epoch #{epoch}] Loaded #{seed_ideas.size} seed templates.\e[0m"

      # Compile seeds into ASTs
      seed_asts = []
      seed_ideas.each_with_index do |code, idx|
        begin
          seed_asts << ASTMutator.parse(code)
        rescue => e
          puts "\e[33m[Warning] Seed template #{idx+1} failed AST parsing: #{e.message}\e[0m"
        end
      end

      if seed_asts.size >= 2
        # Run evolution for this epoch
        winner = run_evolution_epoch(seed_asts, method_name, test_cases, epoch)
        return winner if winner
      end

      # Epochal Self-Reflection
      if best_overall_candidate_failed
        puts "\n\e[33;1m=== [Epoch #{epoch} Self-Reflection Loop Activated] ===\e[0m"
        puts "Best failed candidate score: #{best_overall_candidate_failed.score}/#{test_cases.size}"
        puts "Compiler/Runner error: #{best_overall_candidate_failed.error}"
        
        prompt = <<~PROMPT
          We ran Llama 3.1 8B templates through an evolutionary GP cycle to solve the task.
          
          Our best candidate code was:
          ```ruby
          #{best_overall_candidate_failed.code}
          ```

          It failed with the following execution or assertion error:
          #{best_overall_candidate_failed.error}

          Please analyze why this candidate failed. Using this feedback, please output THREE completely new, corrected, and highly robust Ruby implementations of the method.
          
          Wrap each implementation in standard ruby markdown blocks:

          ```ruby
          # Implementation 1
          def #{method_name}(...)
            ...
          end
          ```

          ```ruby
          # Implementation 2
          def #{method_name}(...)
            ...
          end
          ```

          ```ruby
          # Implementation 3
          def #{method_name}(...)
            ...
          end
          ```

          Do not add explanations. Output ONLY the three code blocks.
        PROMPT
      end

      epoch += 1
    end

    puts "\e[31m[Epochal Search Exhausted] Failed to evolve perfect code.\e[0m"
    raise "GP search failed to converge."
  end

  private

  def run_evolution_epoch(seed_asts, method_name, test_cases, epoch)
    population = []
    while population.size < @pop_size
      ast = ASTMutator.deep_copy(seed_asts.sample)
      ast = apply_random_mutation(ast, seed_asts) if rand < 0.5
      population << Candidate.new(ast)
    end

    @best_failed_candidate = nil

    @generations.times do |gen|
      puts "\n\e[35;1m--- Epoch #{epoch} | Generation #{gen + 1} ---\e[0m"
      
      # Evaluate Fitness in Sandbox
      population.each do |candidate|
        if candidate.type == :untested
          Sandbox.evaluate_candidate!(candidate, method_name, test_cases)
        end
      end

      # Sort population
      population = population.sort_by { |c| -c.fitness }

      best_this_gen = population.first
      puts "  Best Candidate Fitness: #{best_this_gen.fitness.round(2)} | Passed Tests: #{best_this_gen.score}/#{test_cases.size} [Type: #{best_this_gen.type}]"
      
      if best_this_gen.error && !best_this_gen.error.empty?
        puts "  \e[33mError trace: #{best_this_gen.error[0..120]}\e[0m"
      end

      if @best_failed_candidate.nil? || best_this_gen.fitness > @best_failed_candidate.fitness
        @best_failed_candidate = best_this_gen
      end

      # Success!
      if best_this_gen.score == test_cases.size
        puts "\e[32;1m\n=== SUCCESS: Perfect Task Reconstructor Evolved! ===\e[0m"
        puts "\e[32mCode:\e[0m"
        puts best_this_gen.code
        return best_this_gen.code
      end

      population = breed_next_generation(population, seed_asts)
    end

    nil
  end

  def best_overall_candidate_failed
    @best_failed_candidate
  end

  def breed_next_generation(population, seed_asts)
    next_gen = []
    
    # 20% Elitism
    elite_count = (population.size * 0.2).to_i
    elite_count = 1 if elite_count < 1
    
    population.first(elite_count).each do |elite|
      next_gen << elite
    end

    while next_gen.size < @pop_size
      if rand < 0.1
        ast = ASTMutator.deep_copy(seed_asts.sample)
        ast = apply_random_mutation(ast, seed_asts)
        next_gen << Candidate.new(ast)
        next
      end

      parent_a = select_parent(population)
      parent_b = select_parent(population)

      child_ast = ASTMutator.deep_copy(parent_a.ast)

      if rand < 0.7
        child_ast = apply_crossover(child_ast, parent_b.ast)
      end

      if rand < 0.4
        child_ast = apply_random_mutation(child_ast, seed_asts)
      end

      next_gen << Candidate.new(child_ast)
    end

    next_gen
  end

  def select_parent(population)
    min_fit = population.map(&:fitness).min
    offset = min_fit < 0 ? -min_fit + 1 : 0
    total_fitness = population.sum { |c| c.fitness + offset }
    return population.sample if total_fitness == 0

    pick = rand(0..total_fitness)
    current = 0
    population.each do |c|
      current += c.fitness + offset
      return c if current >= pick
    end
    population.last
  end

  def apply_crossover(ast_a, ast_b)
    base_nodes = ASTMutator.collect_nodes(ast_a).select { |e| 
      [:send, :lvar, :int, :float, :str].include?(e[:node].type)
    }
    donor_nodes = ASTMutator.collect_nodes(ast_b).select { |e|
      [:send, :lvar, :int, :float, :str].include?(e[:node].type)
    }
    return ast_a if base_nodes.empty? || donor_nodes.empty?
    
    target_node = base_nodes.sample[:node]
    donor_node = donor_nodes.sample[:node]
    
    ASTMutator.replace_node(ast_a, target_node, donor_node)
  end

  def apply_random_mutation(ast, seed_asts)
    mut_type = [:op_swap, :const_mutate, :sym_swap, :var_swap].sample
    
    case mut_type
    when :op_swap
      op_nodes = ASTMutator.collect_nodes(ast).select { |e|
        e[:node].type == :send && e[:node].children[0].is_a?(Parser::AST::Node)
      }
      return ast if op_nodes.empty?
      target_send = op_nodes.sample[:node]
      new_op = [:+, :-, :*, :/, :**, :%].sample
      ASTMutator.mutate_operators(ast, target_send, new_op)
      
    when :const_mutate
      const_nodes = ASTMutator.collect_nodes(ast).select { |e|
        [:int, :float].include?(e[:node].type)
      }
      return ast if const_nodes.empty?
      target_const = const_nodes.sample[:node]
      orig_val = target_const.children[0]
      
      # Extract unique constants in pool to use for mutations
      all_consts = const_nodes.map { |e| e[:node].children[0] }.uniq
      
      new_val = if rand < 0.5 && !all_consts.empty?
        all_consts.sample
      else
        adjust = (rand - 0.5) * 2.0
        orig_val.is_a?(Numeric) ? (orig_val + adjust).round(4) : orig_val
      end
      
      ASTMutator.mutate_constant(ast, target_const, new_val)
      
    when :sym_swap
      sym_nodes = ASTMutator.collect_nodes(ast).select { |e|
        e[:node].type == :sym
      }
      return ast if sym_nodes.empty?
      target_sym = sym_nodes.sample[:node]
      all_syms = sym_nodes.map { |e| e[:node].children[0] }.uniq
      
      if all_syms.size > 1
        new_sym = (all_syms - [target_sym.children[0]]).sample
        ASTMutator.mutate_symbol(ast, target_sym, new_sym)
      else
        ast
      end
      
    when :var_swap
      var_nodes = ASTMutator.collect_nodes(ast).select { |e|
        e[:node].type == :lvar
      }
      return ast if var_nodes.empty?
      target_var = var_nodes.sample[:node]
      all_vars = var_nodes.map { |e| e[:node].children[0] }.uniq
      
      if all_vars.size > 1
        new_var = (all_vars - [target_var.children[0]]).sample
        ASTMutator.mutate_variable(ast, target_var, new_var)
      else
        ast
      end
    else
      ast
    end
  end
end
