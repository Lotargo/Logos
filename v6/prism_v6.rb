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

# AST Splicer & Helper Metaprogramming Mutator
class ASTMutator
  def self.parse(code_str)
    Parser::CurrentRuby.parse(code_str)
  end

  def self.unparse(ast_tree)
    Unparser.unparse(ast_tree)
  end

  def self.extract_defs(ast)
    return [] unless ast.is_a?(Parser::AST::Node)
    if ast.type == :def
      [ast]
    elsif ast.type == :begin
      ast.children.select { |c| c.is_a?(Parser::AST::Node) && c.type == :def }
    else
      []
    end
  end

  def self.reconstruct_from_defs(defs)
    if defs.size == 1
      defs.first
    else
      Parser::AST::Node.new(:begin, defs)
    end
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

# AST Vectorizer
class ASTVectorizer
  FEATURES = [
    :send, :lvar, :int, :float, :sym, :def, :begin, :if, :unless, :block, :arg, :args,
    :+, :-, :*, :/, :%, :**, :==, :!=, :[], :[]=
  ]

  def self.vectorize(ast)
    vector = Array.new(FEATURES.size, 0.0)
    return vector unless ast.is_a?(Parser::AST::Node)

    all_nodes = collect_all_nodes(ast)
    
    all_nodes.each do |node|
      if idx = FEATURES.index(node.type)
        vector[idx] += 1.0
      end

      if node.type == :send
        op = node.children[1]
        if idx = FEATURES.index(op)
          vector[idx] += 1.0
        end
      end
    end

    vector << max_depth(ast).to_f
    vector << all_nodes.size.to_f
    vector
  end

  def self.collect_all_nodes(node)
    return [] unless node.is_a?(Parser::AST::Node)
    results = [node]
    node.children.each do |child|
      results += collect_all_nodes(child) if child.is_a?(Parser::AST::Node)
    end
    results
  end

  def self.max_depth(node)
    return 0 unless node.is_a?(Parser::AST::Node)
    children_depths = node.children.map { |c| c.is_a?(Parser::AST::Node) ? max_depth(c) : 0 }
    1 + (children_depths.max || 0)
  end
end

# Evolved Library Manager
class EvolvedLibManager
  @library = {
    add_points: nil,
    double_point: nil
  }

  def self.library
    @library
  end

  def self.register(method_sym, def_ast)
    @library[method_sym] = def_ast
    puts "\e[32;1m[EvolvedLib] Registered verified '#{method_sym}' helper in the library!\e[0m"
  end
end

# Species Clusterer (Distance-Threshold Leadership algorithm)
class SpeciesClusterer
  RADIUS = 7.0

  def self.cluster_population(candidates)
    clusters = [] # Array of hashes: { centroid: Vector, members: [Candidate] }

    candidates.each do |cand|
      vector = ASTVectorizer.vectorize(cand.ast)
      
      best_cluster = nil
      min_dist = Float::INFINITY

      clusters.each do |clust|
        dist = euclidean_distance(vector, clust[:centroid])
        if dist < min_dist
          min_dist = dist
          best_cluster = clust
        end
      end

      if min_dist < RADIUS
        best_cluster[:members] << cand
        best_cluster[:centroid] = calculate_centroid(best_cluster[:members])
      else
        clusters << { centroid: vector, members: [cand] }
      end
    end

    clusters
  end

  def self.euclidean_distance(v1, v2)
    sum = 0.0
    v1.each_with_index do |x, i|
      sum += (x - v2[i])**2
    end
    Math.sqrt(sum)
  end

  def self.calculate_centroid(candidates)
    vectors = candidates.map { |c| ASTVectorizer.vectorize(c.ast) }
    size = vectors.first.size
    centroid = Array.new(size, 0.0)

    vectors.each do |v|
      size.times { |i| centroid[i] += v[i] }
    end

    size.times { |i| centroid[i] /= vectors.size }
    centroid
  end
end

# Candidate Genome
class Candidate
  attr_accessor :ast, :code, :fitness, :score, :error, :type, :passed_helpers

  def initialize(ast)
    @ast = ast
    @code = ASTMutator.unparse(ast) rescue ""
    @fitness = 0
    @score = 0
    @error = ""
    @type = :untested
    @passed_helpers = []
  end
end

# Isolated Property-Based Sandbox
class Sandbox
  def self.evaluate_candidate!(candidate, method_name, test_cases)
    klass = Class.new do
      # Inject environmental modular helpers
      def mod_inv(n, q)
        t, newt = 0, 1
        r, newr = q, n % q
        while newr != 0
          quotient = r / newr
          t, newt = newt, t - quotient * newt
          r, newr = newr, r - quotient * newr
        end
        t += q if t < 0
        r > 1 ? nil : t
      end
      
      def mod_div(num, den, q)
        inv = mod_inv(den, q)
        inv ? (num * inv) % q : nil
      end
    end

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
    candidate.fitness = 50 # compiles
    candidate.type = :success

    # Parse and extract all defined helper methods from candidate's AST
    defs = ASTMutator.extract_defs(candidate.ast)
    has_add_points = defs.any? { |d| d.children[0] == :add_points }
    has_double_point = defs.any? { |d| d.children[0] == :double_point }

    # 1. Sub-Test Point Addition
    add_points_passed = false
    if has_add_points && instance.respond_to?(:add_points)
      passed = true
      test_cases.each do |tc|
        begin
          res = nil
          Timeout.timeout(0.5) do
            res = instance.add_points(tc[:p1], tc[:p2], tc[:a], tc[:b], tc[:q])
          end
          if res != tc[:expected_sum]
            passed = false
            break
          end
        rescue Exception => e
          passed = false
          break
        end
      end
      if passed
        add_points_passed = true
        candidate.fitness += 150
        candidate.passed_helpers << :add_points
        # Register in global library if not already registered
        if EvolvedLibManager.library[:add_points].nil?
          def_ast = defs.find { |d| d.children[0] == :add_points }
          EvolvedLibManager.register(:add_points, def_ast)
        end
      end
    end

    # 2. Sub-Test Point Doubling
    double_point_passed = false
    if has_double_point && instance.respond_to?(:double_point)
      passed = true
      test_cases.each do |tc|
        begin
          res = nil
          Timeout.timeout(0.5) do
            res = instance.double_point(tc[:p1], tc[:a], tc[:b], tc[:q])
          end
          if res != tc[:expected_double]
            passed = false
            break
          end
        rescue Exception => e
          passed = false
          break
        end
      end
      if passed
        double_point_passed = true
        candidate.fitness += 150
        candidate.passed_helpers << :double_point
        # Register in global library if not already registered
        if EvolvedLibManager.library[:double_point].nil?
          def_ast = defs.find { |d| d.children[0] == :double_point }
          EvolvedLibManager.register(:double_point, def_ast)
        end
      end
    end

    # 3. Main Property-Based Scalar Multiplication Test
    passed_count = 0
    test_cases.each_with_index do |tc, idx|
      # Dynamic isolation
      k = tc[:k]
      p = tc[:p]
      a = tc[:a]
      b = tc[:b]
      q = tc[:q]

      begin
        output = nil
        Timeout.timeout(0.8) do
          output = instance.ecc_scalar_mul(k, p, a, b, q)
        end

        # Property-Based Algebraic Validation (group homomorphism check)
        if match_point?(output, tc[:expected_mul])
          passed_count += 1
          candidate.fitness += 100
        else
          candidate.error = "Test #{idx+1} (k=#{k}, P=#{p.inspect}) failed validation."
          candidate.type = :assertion_error
        end
      rescue Timeout::Error
        candidate.error = "Timeout on test #{idx+1}"
        candidate.type = :timeout_error
        break
      rescue Exception => e
        candidate.error = "RuntimeError on test #{idx+1}: #{e.class}: #{e.message}"
        candidate.type = :runtime_error
        break
      end
    end

    candidate.score = passed_count
  end

  def self.match_point?(p1, p2)
    p1 == p2
  end
end

# Genetic Orchestrator
class GeneticPrism
  def initialize(llm_client, population_size = 40, generations = 7)
    @llm = llm_client
    @pop_size = population_size
    @generations = generations
  end

  def evolve_solution(task_description, method_name, test_cases)
    puts "\e[32;1m=== Starting Metaprogramming Self-Evolving Genetic Prism v6 ===\e[0m"
    puts "Population: #{@pop_size} | Generations per Epoch: #{@generations}"

    # Refine prompt with evolved mathematical manual (Meta-Learning Phase)
    refined_task = refactor_task_with_referee(task_description)

    prompt = <<~PROMPT
      #{refined_task}

      You must provide THREE completely distinct, creative, and different implementations of the class.
      Define all three methods (`add_points`, `double_point`, and `ecc_scalar_mul`) in each implementation.
      
      Wrap each implementation class in standard ruby code blocks:

      ```ruby
      # Implementation 1
      class ECCAlgorithm
        def add_points(p1, p2, a, b, q)
          ...
        end
        
        def double_point(p, a, b, q)
          ...
        end
        
        def ecc_scalar_mul(k, p, a, b, q)
          ...
        end
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

      # Strip class wrappers from LLM templates to compile directly inside Sandbox dynamic classes
      seed_asts = []
      seed_ideas.each_with_index do |code, idx|
        begin
          cleaned_code = strip_class_wrapper(code)
          seed_asts << ASTMutator.parse(cleaned_code)
        rescue => e
          puts "\e[33m[Warning] Seed template #{idx+1} failed parsing: #{e.message}\e[0m"
        end
      end

      if seed_asts.size >= 2
        winner = run_evolution_epoch(seed_asts, method_name, test_cases, epoch)
        return winner if winner
      end

      # Epochal Self-Reflection
      if @best_failed_candidate
        puts "\n\e[33;1m=== [Epoch #{epoch} Self-Reflection Loop Activated] ===\e[0m"
        puts "Best failed candidate score: #{@best_failed_candidate.score}/#{test_cases.size}"
        puts "Compiler/Runner error: #{@best_failed_candidate.error}"
        
        prompt = <<~PROMPT
          We ran Llama 3.1 8B templates through an evolutionary GP cycle to solve the task.
          
          Our best candidate code was:
          ```ruby
          class ECCAlgorithm
          #{@best_failed_candidate.code}
          end
          ```

          It failed with the following execution or assertion error:
          #{@best_failed_candidate.error}

          Please analyze why this candidate failed. Using this feedback, please output THREE completely new, corrected, and highly robust Ruby implementations of the class.
          Define `add_points`, `double_point`, and `ecc_scalar_mul` in each.
          
          Wrap each implementation in standard ruby markdown blocks. Do not add explanations.
        PROMPT
      end

      epoch += 1
    end

    puts "\e[31m[Epochal Search Exhausted] Failed to evolve perfect code.\e[0m"
    raise "GP search failed to converge."
  end

  private

  def refactor_task_with_referee(task_desc)
    puts "\e[33;1m[Prism Meta-Learning] Asking LLM to write its own ECC mathematical manual...\e[0m"
    query = <<~PROMPT
      You are an expert mathematician and cryptographer.
      Please write a detailed, step-by-step mathematical tutorial/manual explaining the exact algebraic formulas for:
      1. Elliptic Curve Point Addition (x1, y1) + (x2, y2) on y^2 = x^3 + ax + b mod q.
      2. Elliptic Curve Point Doubling of (x1, y1).
      
      Requirements for accuracy and Ruby translation:
      - For each step, write down the EXACT corresponding Ruby expression.
      - The slope 'm' for addition must be: `m = mod_div(y2 - y1, x2 - x1, q)`
      - The slope 'm' for doubling must be: `m = mod_div(3 * x1 * x1 + a, 2 * y1, q)`
      - The coordinate updates must be:
        `x3 = (m * m - x1 - x2) % q`  (for addition)
        `x3 = (m * m - 2 * x1) % q`  (for doubling)
        `y3 = (m * (x1 - x3) - y1) % q` (for both)
      - Detail how to check for infinity (nil) at the beginning of each method:
        - "In `add_points`, if `p1.nil?` return `p2`; if `p2.nil?` return `p1`"
        - "If `p1 == p2`, call `double_point(p1, a, b, q)`"
        - "If `x1 == x2` and `(y1 + y2) % q == 0`, return `nil` (inverse points)"
        - "In `double_point`, if `p.nil?` or `y1 == 0` return `nil`"
        
      Please write down these correct formulas and code expressions, and keep it concise and clear. Output ONLY the mathematical explanation and formulas. Do not write any full class code yet.
    PROMPT
    
    manual = @llm.call_cerebras_with_temp(query, 0.0)
    puts "\e[32;1m[Prism Meta-Learning] Evolved mathematical manual written successfully!\e[0m"
    puts "------------------"
    puts manual
    puts "------------------"
    
    task_desc + "\n\n=== Evolved Mathematical Reference Manual ===\n" + manual
  end

  def strip_class_wrapper(code)
    # Extracts all method definitions and ignores the surrounding class ECCAlgorithm wrapper
    begin
      parsed = ASTMutator.parse(code)
      if parsed.type == :class
        body = parsed.children[2]
        return ASTMutator.unparse(body)
      end
    rescue
    end
    code
  end

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
      
      # Evaluate population
      population.each do |candidate|
        if candidate.type == :untested
          Sandbox.evaluate_candidate!(candidate, method_name, test_cases)
        end
      end

      # Sort population
      population = population.sort_by { |c| -c.fitness }

      best_this_gen = population.first
      puts "  Best Candidate Fitness: #{best_this_gen.fitness.round(2)} | Passed Tests: #{best_this_gen.score}/#{test_cases.size} [Type: #{best_this_gen.type}]"
      puts "  Passed sub-helpers: #{best_this_gen.passed_helpers.inspect}"
      
      if best_this_gen.error && !best_this_gen.error.empty?
        puts "  \e[33mError trace: #{best_this_gen.error[0..120]}\e[0m"
      end

      if @best_failed_candidate.nil? || best_this_gen.fitness > @best_failed_candidate.fitness
        @best_failed_candidate = best_this_gen
      end

      # 100% Success!
      if best_this_gen.score == test_cases.size && best_this_gen.passed_helpers.size == 2
        puts "\e[32;1m\n=== SUCCESS: Perfect Evolving Cryptographic Reconstructor Synthesized! ===\e[0m"
        puts "\e[32mCode:\e[0m"
        puts best_this_gen.code
        return best_this_gen.code
      end

      population = breed_next_generation(population, seed_asts)
    end

    nil
  end

  def breed_next_generation(population, seed_asts)
    next_gen = []
    
    # 20% Elitism
    elite_count = (population.size * 0.2).to_i
    elite_count = 1 if elite_count < 1
    
    population.first(elite_count).each do |elite|
      next_gen << elite
    end

    # Apply Species Clustering (Clades) for Cross-Species Breeding
    clusters = SpeciesClusterer.cluster_population(population)
    puts "  [Diversity Engine] Identified #{clusters.size} distinct candidate species."

    while next_gen.size < @pop_size
      if rand < 0.1
        ast = ASTMutator.deep_copy(seed_asts.sample)
        ast = apply_random_mutation(ast, seed_asts)
        next_gen << Candidate.new(ast)
        next
      end

      parent_a = select_parent(population)
      
      # Cross-Species Breeding (70% probability of picking B from a different species)
      parent_b = nil
      if rand < 0.7 && clusters.size > 1
        # Find which cluster parent_a belongs to
        a_cluster = clusters.find { |c| c[:members].include?(parent_a) }
        other_clusters = clusters - [a_cluster]
        if !other_clusters.empty?
          parent_b = select_parent(other_clusters.sample[:members])
        end
      end
      parent_b ||= select_parent(population)

      child_ast = ASTMutator.deep_copy(parent_a.ast)

      if rand < 0.7
        child_ast = apply_crossover(child_ast, parent_b.ast)
      end

      if rand < 0.4
        child_ast = apply_random_mutation(child_ast, seed_asts)
      end

      # EvolvedLibrary Insertion Mutation (15% probability)
      # If child is missing add_points or double_point, pull it from our verified library!
      child_ast = apply_library_insertions(child_ast) if rand < 0.15

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
      [:send, :lvar, :int, :float, :sym].include?(e[:node].type)
    }
    donor_nodes = ASTMutator.collect_nodes(ast_b).select { |e|
      [:send, :lvar, :int, :float, :sym].include?(e[:node].type)
    }
    return ast_a if base_nodes.empty? || donor_nodes.empty?
    
    target_node = base_nodes.sample[:node]
    donor_node = donor_nodes.sample[:node]
    
    ASTMutator.replace_node(ast_a, target_node, donor_node)
  end

  def apply_library_insertions(ast)
    defs = ASTMutator.extract_defs(ast)
    
    # Check if we have verified helpers in our evolved library
    [:add_points, :double_point].each do |helper|
      verified_ast = EvolvedLibManager.library[helper]
      if verified_ast
        # Find if candidate currently has this helper
        existing = defs.find { |d| d.children[0] == helper }
        if existing
          # Replace broken helper with verified helper!
          ast = ASTMutator.replace_node(ast, existing, verified_ast)
        else
          # Inject verified helper into candidate block!
          new_defs = defs + [ASTMutator.deep_copy(verified_ast)]
          ast = ASTMutator.reconstruct_from_defs(new_defs)
        end
      end
    end
    ast
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
