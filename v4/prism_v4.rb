require 'net/http'
require 'uri'
require 'json'
require 'parser/current'
require 'unparser'
require 'timeout'

# Custom Alternative Physics Accelerator Simulator: "Weyl Space"
class WeylGenerator
  # Generates a dataset of 5D Weyl space collision events
  def self.generate_dataset(size = 30)
    dataset = []
    
    # 50% Weyl Resonance decay events (Signal)
    signal_size = (size / 2.0).to_i
    signal_size.times do
      particles = []
      
      # Charge conservation: sum(q) = 0
      q = [-2, 1, 2, -1].shuffle
      
      w = Array.new(4)
      x = Array.new(4) { rand(1.0..5.0) }
      y = Array.new(4) { rand(0.5..1.0) } # x > y to ensure x^2 - y^2 > 0
      z = Array.new(4) { rand(1.0..5.0) }
      spin = Array.new(4) { rand(0.0..30.0) } # small spins so cos(spin) is positive
      theta = Array.new(4) { rand(0.0..90.0) }
      
      # Calculate denominator
      denom = 0.0
      4.times do |i|
        denom += (z[i]**2 + 1.0) * Math.cos(spin[i] * Math::PI / 180.0)
      end
      denom = 10.0 if denom.abs < 0.1
      
      target_mass = 84.0 + (rand - 0.5) * 1.0 # smear mass between 83.5 and 84.5
      target_sq = target_mass ** 2
      target_num = target_sq * denom
      
      # Calculate subtracted term: sum((x^2 - y^2) * sin(theta))
      sub_term = 0.0
      4.times do |i|
        sub_term += (x[i]**2 - y[i]**2) * Math.sin(theta[i] * Math::PI / 180.0)
      end
      
      # Distinguish indices of positive and negative Weyl charges
      pos_indices = []
      neg_indices = []
      4.times do |i|
        if q[i] > 0
          pos_indices << i
        else
          neg_indices << i
        end
      end
      
      # Set small w for negative Weyl charges to minimize their negative cubed impact
      neg_indices.each do |idx|
        w[idx] = rand(0.1..0.3)
      end
      
      neg_contrib = neg_indices.sum { |idx| (w[idx] * q[idx])**3 }
      
      # Solve for the remaining positive w requirements
      required_pos_wq3 = target_num + sub_term - neg_contrib
      required_pos_wq3 = 1000.0 if required_pos_wq3 < 100.0
      
      share = required_pos_wq3 / 2.0
      pos_indices.each do |idx|
        w[idx] = (share ** (1.0 / 3.0)) / q[idx]
      end
      
      4.times do |i|
        particles << {
          w: w[i],
          x: x[i],
          y: y[i],
          z: z[i],
          q: q[i],
          spin: spin[i],
          theta: theta[i]
        }
      end
      
      dataset << { signal: true, particles: particles }
    end
    
    # 50% Background noise events
    background_size = size - signal_size
    background_size.times do
      particles = []
      4.times do
        particles << {
          w: rand(1.0..10.0),
          x: rand(1.0..10.0),
          y: rand(1.0..10.0),
          z: rand(1.0..10.0),
          q: rand(-2..2), # charge might not sum to 0
          spin: rand(0.0..360.0),
          theta: rand(0.0..360.0)
        }
      end
      dataset << { signal: false, particles: particles }
    end
    
    dataset.shuffle
  end
  
  # Absolute Ground Truth Math Reference
  def self.calculate_weyl_mass(particles)
    # 1. Weyl charge conservation
    q_sum = particles.sum { |p| p[:q] }
    return nil if q_sum != 0
    
    # 2. Spin resonance sum projection
    spin_sum = particles.sum { |p| p[:spin] * Math::PI / 180.0 }
    return nil if spin_sum < 0.0
    
    num = 0.0
    denom = 0.0
    
    particles.each do |p|
      num += (p[:w] * p[:q])**3 - (p[:x]**2 - p[:y]**2) * Math.sin(p[:theta] * Math::PI / 180.0)
      denom += (p[:z]**2 + 1.0) * Math.cos(p[:spin] * Math::PI / 180.0)
    end
    
    return nil if denom.abs < 1e-5
    val_under_sqrt = num / denom
    return nil if val_under_sqrt < 0.0
    
    mass = Math.sqrt(val_under_sqrt)
    (mass >= 83.0 && mass <= 85.0) ? mass : nil
  end
end

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
        # Sleep and retry
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

# AST DNA Splicer & Mutator
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

# Isolated Physics Sandbox with Weyl invariants validator
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
      # Deep copy test case inputs to prevent candidate code from corrupting shared data
      particles = Marshal.load(Marshal.dump(tc[:particles]))
      
      # Determine absolute mathematical reference mass
      ground_truth_mass = WeylGenerator.calculate_weyl_mass(particles)

      begin
        output = nil
        Timeout.timeout(1.0) do
          output = instance.send(method_name, particles)
        end

        if ground_truth_mass
          # Signal Event: Reconstructed mass must match ground truth exactly!
          if output.is_a?(Numeric) && (output - ground_truth_mass).abs < 0.001
            passed_count += 1
            error = (output - ground_truth_mass).abs
            precision_bonus = [0.0, (0.001 - error) * 100000.0].max
            candidate.fitness += 100 + precision_bonus
          else
            candidate.error = "Test #{idx+1} (Signal) expected mass #{ground_truth_mass.round(4)}, got #{output.inspect}"
            candidate.type = :assertion_error
          end
        else
          # Background Event: Must return nil
          if output.nil?
            passed_count += 1
            candidate.fitness += 100
          else
            candidate.error = "Test #{idx+1} (Background) expected nil, got #{output.inspect}"
            candidate.type = :assertion_error
          end
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
end

# Version 4 Orchestrator: Multi-Temperature Llama 3.1 8B Actors + Recursive Self-Reflection
class GeneticPrism
  def initialize(llm_client, population_size = 40, generations = 5)
    @llm = llm_client
    @pop_size = population_size
    @generations = generations
  end

  def evolve_solution(task_description, method_name, test_cases)
    puts "\e[32;1m=== Starting Quantum-Cognitive Prism v4 ===\e[0m"
    puts "Model constraint: Cerebras llama3.1-8b exclusively (Temperatures 0.0, 0.5, 1.0, 1.5)"
    puts "Task: #{task_description}"
    puts "Population: #{@pop_size} | Generations per Epoch: #{@generations}"

    # Setup the Weyl Physics Relativistic prompt
    prompt = <<~PROMPT
      You are the Physicist in the alternative universe of 5D Weyl Space.
      Your task is to write a Ruby method called '#{method_name}(particles)' that reconstructs the Weyl Resonance mass M_W.
      
      Input `particles` is an array of 4 particle hashes, each with the format:
      { w: Float, x: Float, y: Float, z: Float, q: Integer, spin: Float, theta: Float }

      Your method must:
      1. Check charge conservation: The sum of Weyl charges (q) of the four particles must be exactly equal to 0.
         If sum(q) is not 0, return nil (background event).
      2. Check spin resonance projection: Convert each particle's `spin` polarization from degrees to radians using:
         spin_rad = spin * Math::PI / 180.0
         If the sum of spins in radians (sum(spin_rad)) is less than 0.0, return nil.
      3. Calculate the 5D Weyl invariant mass M_W using the following custom parallel universe kinematics formula:
         
         M_W = sqrt( Numerator / Denominator )
         
         Where:
         Numerator = Sum over all 4 particles of: (w * q)^3 - (x^2 - y^2) * sin(theta_radians)
         Denominator = Sum over all 4 particles of: (z^2 + 1.0) * cos(spin_radians)
         
         Note: The fields `spin` and `theta` are provided in DEGREES. You must convert them to RADIANS using:
         angle_rad = angle * Math::PI / 180.0
      4. If the denominator is close to 0 (e.g. absolute sum is less than 1e-5), or if the term under the square root (Numerator / Denominator) is negative, return nil.
      5. If the calculated M_W is within the target Weyl Resonance window [83.0, 85.0] GeV, return the calculated mass. Else return nil.

      You must provide THREE completely distinct, creative, and different implementations of this method.
      Wrap each implementation in standard ruby code blocks:

      ```ruby
      # Implementation 1
      def #{method_name}(particles)
        ...
      end
      ```

      ```ruby
      # Implementation 2
      def #{method_name}(particles)
        ...
      end
      ```

      ```ruby
      # Implementation 3
      def #{method_name}(particles)
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

      puts "\n\e[32m[Epoch #{epoch}] Loaded #{seed_ideas.size} seed physics templates.\e[0m"

      # Compile seeds into ASTs
      seed_asts = []
      seed_ideas.each_with_index do |code, idx|
        begin
          seed_asts << ASTMutator.parse(code)
        rescue => e
          puts "\e[33m[Warning] Seed physics template #{idx+1} failed AST parsing: #{e.message}\e[0m"
        end
      end

      if seed_asts.size >= 2
        # Run evolution for this epoch
        winner = run_evolution_epoch(seed_asts, method_name, test_cases, epoch)
        return winner if winner
      end

      # Epochal Self-Reflection: Package the best attempt and error log, feed it back to the actors!
      if best_overall_candidate_failed
        puts "\n\e[33;1m=== [Epoch #{epoch} Self-Reflection Loop Activated] ===\e[0m"
        puts "Best failed candidate score: #{best_overall_candidate_failed.score}/#{test_cases.size}"
        puts "Compiler/Runner error: #{best_overall_candidate_failed.error}"
        
        prompt = <<~PROMPT
          You are the Physicist in the alternative universe of 5D Weyl Space.
          We ran Llama 3.1 8B templates through an evolutionary GP cycle to solve: #{task_description}

          Our best candidate code was:
          ```ruby
          #{best_overall_candidate_failed.code}
          ```

          It failed with the following execution or assertion error:
          #{best_overall_candidate_failed.error}

          Please analyze why this candidate failed. Using this feedback, please output THREE completely new, mathematically corrected, and robust Ruby implementations of the method '#{method_name}'.
          Ensure you convert both polarization angles (spin and theta) from DEGREES to RADIANS, verify q_sum == 0, check spin_sum_rad >= 0.0, protect the square root from negative numbers, and check for denominator division by zero!

          Wrap each implementation in standard ruby markdown blocks:

          ```ruby
          # Implementation 1
          def #{method_name}(particles)
            ...
          end
          ```

          ```ruby
          # Implementation 2
          def #{method_name}(particles)
            ...
          end
          ```

          ```ruby
          # Implementation 3
          def #{method_name}(particles)
            ...
          end
          ```

          Do not add explanations. Output ONLY the three code blocks.
        PROMPT
      end

      epoch += 1
    end

    puts "\e[31m[Epochal Search Exhausted] Failed to reconstruct Weyl resonance Peak.\e[0m"
    raise "5D Weyl Space search failed to converge."
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
      puts "  Best Candidate Fitness: #{best_this_gen.fitness.round(2)} | Passed Weyl Events: #{best_this_gen.score}/#{test_cases.size} [Type: #{best_this_gen.type}]"
      
      if best_this_gen.error && !best_this_gen.error.empty?
        puts "  \e[33mError trace: #{best_this_gen.error[0..120]}\e[0m"
      end

      if @best_failed_candidate.nil? || best_this_gen.fitness > @best_failed_candidate.fitness
        @best_failed_candidate = best_this_gen
      end

      # Success!
      if best_this_gen.score == test_cases.size
        puts "\e[32;1m\n=== SUCCESS: Weyl Reconstructor Code Evolved! ===\e[0m"
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
      
      new_val = if rand < 0.5
        [0, 1, 2, 6, 83.0, 84.0, 85.0, 180.0, 1e-5].sample
      else
        adjust = (rand - 0.5) * 2.0
        (orig_val + adjust).round(4)
      end
      
      ASTMutator.mutate_constant(ast, target_const, new_val)
      
    when :sym_swap
      sym_nodes = ASTMutator.collect_nodes(ast).select { |e|
        e[:node].type == :sym
      }
      return ast if sym_nodes.empty?
      target_sym = sym_nodes.sample[:node]
      keys = [:w, :x, :y, :z, :q, :spin, :theta]
      
      if keys.include?(target_sym.children[0])
        new_key = keys.sample
        ASTMutator.mutate_symbol(ast, target_sym, new_key)
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

# Self-Running Physics Challenge Demo for Version 4
if __FILE__ == $0
  client = LLMClient.new("../dont_delete")
  # Population size: 40, Generations per Epoch: 5
  prism = GeneticPrism.new(client, 40, 5)

  task = "Write a Ruby method 'reconstruct_weyl(particles)' to reconstruct the 5D Weyl Resonance mass M_W. " \
         "It must check that sum(q) is exactly 0, check sum(spin_rad) >= 0.0, calculate M_W using our custom " \
         "Weyl vector kinematics formula, and if M_W is within [83.0, 85.0] GeV, return the mass. Else return nil."

  method_name = "reconstruct_weyl"
  
  # Generate 30 simulated 5D Weyl space collision events for GP evaluation
  test_events = WeylGenerator.generate_dataset(30)

  begin
    winning_code = prism.evolve_solution(task, method_name, test_events)
    
    File.write("winning_solution_v4.rb", winning_code)
    puts "\n\e[32;1m[Prism v4] Evolved Weyl Reconstructor saved to winning_solution_v4.rb\e[0m"
  rescue => e
    puts "\n\e[31;1m[Prism v4 Terminated] #{e.message}\e[0m"
    puts e.backtrace.join("\n")
  end
end
