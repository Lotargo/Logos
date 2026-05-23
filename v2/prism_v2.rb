require 'net/http'
require 'uri'
require 'json'
require 'parser/current'
require 'unparser'
require 'timeout'

# Custom Alternative Physics Accelerator Simulator: "Chronos Space"
class ChronosGenerator
  # Generates a dataset of Chronon collision events
  def self.generate_dataset(size = 30)
    dataset = []
    
    # 50% Signal events: Chronon Fusions where Q_tot = 6 and M_C is around 42.0
    signal_size = (size / 2.0).to_i
    signal_size.times do
      particles = []
      
      q = [1, 2, 2, 1] # sum = 6
      x = Array.new(4) { rand(1.0..5.0) }
      y = Array.new(4) { rand(1.0..5.0) }
      z = Array.new(4) { rand(1.0..5.0) }
      sigma = Array.new(4) { rand(0.0..360.0) }
      t = Array.new(4) { rand(1.0..5.0) }
      
      denom = sigma.sum { |s| Math.cos(s * Math::PI / 180.0) }
      denom = 0.5 if denom.abs < 0.1 # avoid division by zero
      
      target_mass = 42.0 + (rand - 0.5) * 1.0 # smear mass between 41.5 and 42.5
      target_num = target_mass * denom
      
      sum_xyz = 0.0
      4.times do |i|
        sum_xyz += (x[i]**2 + y[i]**2) - (q[i] * z[i])
      end
      
      required_sum_alpha_t = target_num + sum_xyz
      if required_sum_alpha_t < 1.0
        required_sum_alpha_t = 50.0
        target_mass = (required_sum_alpha_t - sum_xyz) / denom
      end
      
      share = required_sum_alpha_t / 4.0
      alpha = []
      4.times do |i|
        val = Math.sqrt(share) / t[i]
        alpha << val
      end
      
      4.times do |i|
        particles << {
          alpha: alpha[i],
          t: t[i],
          x: x[i],
          y: y[i],
          z: z[i],
          q: q[i],
          sigma: sigma[i]
        }
      end
      
      dataset << { signal: true, particles: particles.shuffle }
    end
    
    # 50% Background noise events (where sum(q) != 6 or M_C is random)
    background_size = size - signal_size
    background_size.times do
      particles = []
      4.times do
        particles << {
          alpha: rand(1.0..10.0),
          t: rand(1.0..10.0),
          x: rand(1.0..10.0),
          y: rand(1.0..10.0),
          z: rand(1.0..10.0),
          q: rand(1..3), # random charge, sum might not be 6
          sigma: rand(0.0..360.0)
        }
      end
      dataset << { signal: false, particles: particles }
    end
    
    dataset.shuffle
  end
  
  # Absolute Ground Truth Math Reference
  def self.calculate_chronon_mass(particles)
    q_sum = particles.sum { |p| p[:q] }
    return nil if q_sum != 6
    
    num = 0.0
    denom = 0.0
    particles.each do |p|
      num += (p[:alpha] * p[:t])**2 - (p[:x]**2 + p[:y]**2) + (p[:q] * p[:z])
      denom += Math.cos(p[:sigma] * Math::PI / 180.0)
    end
    
    return nil if denom.abs < 1e-6
    mass = num / denom
    (mass >= 41.0 && mass <= 43.0) ? mass : nil
  end
end

# LLM Client with Parallel Actor Impulse
class LLMClient
  attr_reader :gemini_keys, :groq_keys, :cerebras_keys

  def initialize(keys_file = "../dont_delete")
    @gemini_keys = []
    @groq_keys = []
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
        if section.include?("gemini")
          current_section = :gemini
        elsif section.include?("groq")
          current_section = :groq
        elsif section.include?("cerebras")
          current_section = :cerebras
        else
          current_section = nil
        end
      else
        case current_section
        when :gemini then @gemini_keys << line
        when :groq then @groq_keys << line
        when :cerebras then @cerebras_keys << line
        end
      end
    end
  rescue => e
    puts "\e[33m[Warning] Failed to load keys from #{filepath}: #{e.message}\e[0m"
  end

  def call_gemini(prompt, key_index = 0)
    raise "No Gemini keys found" if @gemini_keys.empty?
    key_index = 0 if key_index >= @gemini_keys.size
    key = @gemini_keys[key_index]

    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=#{key}")
    payload = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.7 }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.request_uri)
    request.body = payload.to_json
    request.content_type = "application/json"

    response = http.request(request)

    if response.code == "200"
      res_data = JSON.parse(response.body)
      res_data.dig("candidates", 0, "content", "parts", 0, "text")
    else
      puts "\e[31m[Gemini Error] Key Index #{key_index} HTTP #{response.code}: #{response.body[0..150]}\e[0m"
      if key_index + 1 < @gemini_keys.size
        puts "[Gemini] Trying next key..."
        call_gemini(prompt, key_index + 1)
      else
        raise "Gemini API call failed: #{response.body}"
      end
    end
  end

  def call_groq(prompt, key_index = 0)
    raise "No Groq keys found" if @groq_keys.empty?
    key_index = 0 if key_index >= @groq_keys.size
    key = @groq_keys[key_index]

    uri = URI("https://api.groq.com/openai/v1/chat/completions")
    payload = {
      model: "llama-3.3-70b-versatile",
      messages: [{ role: "user", content: prompt }],
      temperature: 0.7
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
    else
      puts "\e[31m[Groq Error] Key Index #{key_index} HTTP #{response.code}: #{response.body[0..150]}\e[0m"
      if key_index + 1 < @groq_keys.size
        puts "[Groq] Trying next key..."
        call_groq(prompt, key_index + 1)
      else
        raise "Groq API call failed: #{response.body}"
      end
    end
  end

  def call_cerebras(prompt, key_index = 0)
    raise "No Cerebras keys found" if @cerebras_keys.empty?
    key_index = 0 if key_index >= @cerebras_keys.size
    key = @cerebras_keys[key_index]

    uri = URI("https://api.cerebras.ai/v1/chat/completions")
    payload = {
      model: "llama3.1-8b",
      messages: [{ role: "user", content: prompt }],
      temperature: 0.7
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
    else
      puts "\e[31m[Cerebras Error] Key Index #{key_index} HTTP #{response.code}: #{response.body[0..150]}\e[0m"
      if key_index + 1 < @cerebras_keys.size
        puts "[Cerebras] Trying next key..."
        call_cerebras(prompt, key_index + 1)
      else
        raise "Cerebras API call failed: #{response.body}"
      end
    end
  end

  def generate_impulse(prompt)
    ideas = []

    # Gemini
    if !@gemini_keys.empty?
      begin
        puts "\e[36m[LLM Actor: Gemini] Querying gemini-3.5-flash...\e[0m"
        res = call_gemini(prompt)
        extracted = extract_code_blocks(res)
        puts "  -> Gemini supplied #{extracted.size} templates."
        ideas += extracted
      rescue => e
        puts "\e[33m[LLM Actor: Gemini] Failed: #{e.message}\e[0m"
      end
    end

    # Groq
    if !@groq_keys.empty?
      begin
        puts "\e[36m[LLM Actor: Groq] Querying llama-3.3-70b-versatile...\e[0m"
        res = call_groq(prompt)
        extracted = extract_code_blocks(res)
        puts "  -> Groq supplied #{extracted.size} templates."
        ideas += extracted
      rescue => e
        puts "\e[33m[LLM Actor: Groq] Failed: #{e.message}\e[0m"
      end
    end

    # Cerebras
    if !@cerebras_keys.empty?
      begin
        puts "\e[36m[LLM Actor: Cerebras] Querying llama3.1-8b...\e[0m"
        res = call_cerebras(prompt)
        extracted = extract_code_blocks(res)
        puts "  -> Cerebras supplied #{extracted.size} templates."
        ideas += extracted
      rescue => e
        puts "\e[33m[LLM Actor: Cerebras] Failed: #{e.message}\e[0m"
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

# AST DNA Splicer & Mutator using parser/unparser
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
      return Parser::AST::Node.new(tree.type, [new_val])
    end

    new_children = tree.children.map do |child|
      child.is_a?(Parser::AST::Node) ? mutate_constant(child, target_const_node, new_val) : child
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

# Isolated Physics Sandbox with custom Chronos invariants validator
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
      particles = tc[:particles]
      
      # Determine absolute mathematical reference mass
      ground_truth_mass = ChronosGenerator.calculate_chronon_mass(particles)

      begin
        output = nil
        Timeout.timeout(1.0) do
          output = instance.send(method_name, particles)
        end

        if ground_truth_mass
          # Signal Event: Reconstructed mass must match ground truth exactly!
          # Allow extremely small error tolerance (0.02)
          if output.is_a?(Numeric) && (output - ground_truth_mass).abs < 0.02
            passed_count += 1
            error = (output - ground_truth_mass).abs
            precision_bonus = [0.0, (0.02 - error) * 5000.0].max
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

# Version 2 Physics Orchestrator: Genetic Programming
class GeneticPrism
  def initialize(llm_client, population_size = 20, generations = 5)
    @llm = llm_client
    @pop_size = population_size
    @generations = generations
  end

  def evolve_solution(task_description, method_name, test_cases)
    puts "\e[32;1m=== Starting Quantum-Cognitive Prism v2 (Chronos Physics Challenge) ===\e[0m"
    puts "Task: #{task_description}"
    puts "Population Size: #{@pop_size} | Generations per Epoch: #{@generations}"

    # Setup the Physics Relativistic prompt
    prompt = <<~PROMPT
      You are the Physicist in the alternative universe of Chronos Space.
      Your task is to write a Ruby method called '#{method_name}(particles)' that reconstructs the Chronon Fusion mass.
      
      Input `particles` is an array of 4 chronon hashes, each with the format:
      { alpha: Float, t: Float, x: Float, y: Float, z: Float, q: Integer, sigma: Float }

      Your method must:
      1. Check charge conservation: The sum of charges (q) of the four particles must be exactly equal to 6.
         If sum(q) is not 6, return nil (background event).
      2. Calculate the Chronos invariant mass M_C using the following custom parallel universe kinematics formula:
         
         M_C = Numerator / Denominator
         
         Where:
         Numerator = Sum over all 4 particles of: (alpha * t)^2 - (x^2 + y^2) + (q * z)
         Denominator = Sum over all 4 particles of: cos(sigma_radians)
         
         Note: The polarization field `sigma` is provided in DEGREES. You must convert it to RADIANS using:
         sigma_rad = sigma * pi / 180.0
         Where pi = Math::PI.
      3. If the denominator is close to 0 (e.g. less than 1e-6), return nil.
      4. If the calculated M_C is within the target Chronon mass window [41.0, 43.0] GeV, return the calculated mass. Else return nil.

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

    puts "\n\e[35;1m=== [Epoch 1: LLM Chronos Physics Impulse] ===\e[0m"
    seed_ideas = @llm.generate_impulse(prompt)
    if seed_ideas.empty?
      raise "Could not retrieve any seed ideas from actors."
    end

    puts "\n\e[32m[LLM] Successfully compiled #{seed_ideas.size} seed physics templates.\e[0m"

    # Compile seeds into ASTs
    seed_asts = []
    seed_ideas.each_with_index do |code, idx|
      begin
        seed_asts << ASTMutator.parse(code)
      rescue => e
        puts "\e[33m[Warning] Seed physics template #{idx+1} failed AST parsing: #{e.message}\e[0m"
      end
    end

    raise "Not enough parseable seeds to start evolution." if seed_asts.size < 2

    # Evolve Epoch 1
    winner = run_evolution_epoch(seed_asts, method_name, test_cases, task_description)
    return winner if winner

    puts "\e[31m[Epoch 1] Chronon search exhausted without perfect reconstructor.\e[0m"
    raise "Chronos kinematics failed to converge."
  end

  private

  def run_evolution_epoch(seed_asts, method_name, test_cases, task_description)
    population = []
    while population.size < @pop_size
      ast = ASTMutator.deep_copy(seed_asts.sample)
      ast = apply_random_mutation(ast, seed_asts) if rand < 0.5
      population << Candidate.new(ast)
    end

    best_overall_candidate = nil

    @generations.times do |gen|
      puts "\n\e[35;1m--- Generation #{gen + 1} ---\e[0m"
      
      # Evaluate Fitness in Sandbox against Ground Truth
      population.each do |candidate|
        Sandbox.evaluate_candidate!(candidate, method_name, test_cases)
      end

      # Sort population by fitness
      population = population.sort_by { |c| -c.fitness }

      best_this_gen = population.first
      puts "  Best Candidate Fitness: #{best_this_gen.fitness.round(2)} | Passed Chronos Events: #{best_this_gen.score}/#{test_cases.size}"
      
      if best_this_gen.error && !best_this_gen.error.empty?
        puts "  \e[33mError trace: #{best_this_gen.error[0..120]}\e[0m"
      end

      if best_overall_candidate.nil? || best_this_gen.fitness > best_overall_candidate.fitness
        best_overall_candidate = best_this_gen
      end

      # Success condition: passes all events with absolute precision
      if best_this_gen.score == test_cases.size
        puts "\e[32;1m\n=== SUCCESS: Chronon Reconstruction Code Evolved! ===\e[0m"
        puts "\e[32mCode:\e[0m"
        puts best_this_gen.code
        return best_this_gen.code
      end

      population = breed_next_generation(population, seed_asts)
    end

    # Epochal Self-Reflection
    if best_overall_candidate
      puts "\n\e[33;1m=== [Epochal Self-Reflection] Custom invariants not met. Reflecting... ===\e[0m"
      puts "Best Candidate Score: #{best_overall_candidate.score}/#{test_cases.size}"
      puts "Code:\n#{best_overall_candidate.code}"
      puts "Error log: #{best_overall_candidate.error}"

      reflection_prompt = <<~PROMPT
        You are the Physicist in the alternative universe of Chronos Space.
        We ran an evolutionary genetic GP cycle to solve the Chronos Reconstruction challenge: #{task_description}

        Our best candidate code was:
        ```ruby
        #{best_overall_candidate.code}
        ```

        It failed with the following detector/compilation error:
        #{best_overall_candidate.error}

        Please analyze why this candidate failed. Using this feedback, please output THREE completely new, highly refined, and mathematically corrected Ruby implementations of the method '#{method_name}'.
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

      puts "\n\e[35;1m=== [Self-Reflection] Querying All Actors for Refined Chronos Impulse ===\e[0m"
      gen2_ideas = @llm.generate_impulse(reflection_prompt)
      
      gen2_asts = []
      gen2_ideas.each_with_index do |code, idx|
        begin
          gen2_asts << ASTMutator.parse(code)
        rescue => e
          puts "\e[33m[Warning] Gen 2 Chronos AST failed parsing: #{e.message}\e[0m"
        end
      end

      if gen2_asts.size >= 2
        puts "\n\e[35;1m=== Starting Gen 2 Chronos Evolutionary Cycle ===\e[0m"
        return run_evolution_epoch(gen2_asts, method_name, test_cases, task_description)
      end
    end

    nil
  end

  def breed_next_generation(population, seed_asts)
    next_gen = []
    elite_count = (population.size * 0.2).to_i
    elite_count = 1 if elite_count < 1
    
    population.first(elite_count).each do |elite|
      next_gen << Candidate.new(ASTMutator.deep_copy(elite.ast))
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

      if rand < 0.3
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
    mut_type = [:op_swap, :const_mutate].sample
    
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
      new_val = [0, 1, 2, 3, 5, 10, 100].sample
      ASTMutator.mutate_constant(ast, target_const, new_val)
    else
      ast
    end
  end
end

# 6. Self-Running Physics Challenge Demo
if __FILE__ == $0
  client = LLMClient.new("../dont_delete")
  # Population size: 20, Generations: 5
  prism = GeneticPrism.new(client, 20, 5)

  task = "Write a Ruby method 'reconstruct_chronon(particles)' to reconstruct the Chronon Fusion mass M_C. " \
         "It must check that sum(q) of the 4 particles is exactly 6, calculate M_C using our custom " \
         "Chronos vector kinematics formula, and if M_C is within [41.0, 43.0] GeV, return the mass. Else return nil."

  method_name = "reconstruct_chronon"
  
  # Generate 30 simulated Chronon collision events for GP evaluation
  test_events = ChronosGenerator.generate_dataset(30)

  begin
    winning_code = prism.evolve_solution(task, method_name, test_events)
    
    File.write("winning_solution_v2.rb", winning_code)
    puts "\n\e[32;1m[Prism v2] Evolved Chronon Reconstructor saved to winning_solution_v2.rb\e[0m"
  rescue => e
    puts "\n\e[31;1m[Prism v2 Chronos Physics Challenge Terminated] #{e.message}\e[0m"
  end
end
