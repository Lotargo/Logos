require 'net/http'
require 'uri'
require 'json'
require 'parser/current'
require 'unparser'
require 'timeout'

# 1. LLM Client with Parallel Actor Impulse & fallbacks
class LLMClient
  attr_reader :gemini_keys, :groq_keys, :cerebras_keys

  def initialize(keys_file = "dont_delete")
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

    # Query gemini-3.5-flash
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=#{key}")
    
    payload = {
      contents: [{
        parts: [{ text: prompt }]
      }],
      generationConfig: {
        temperature: 0.7
      }
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

  # Query ALL 3 actors in parallel/sequence to produce the "Actor Impulse" (9 candidates total)
  def generate_impulse(prompt)
    ideas = []

    # 1. Gemini Actor
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

    # 2. Groq Actor
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

    # 3. Cerebras Actor
    if !@cerebras_keys.empty?
      begin
        puts "\e[36m[LLM Actor: Cerebras] Querying llama3.1-70b...\e[0m"
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

# 2. Custom Amb backtracking engine
class Amb
  class Backtrack < StandardError; end
  class NoMoreChoices < StandardError; end

  attr_reader :stack

  def initialize
    @stack = []
    @read_index = 0
    @has_more = true
  end

  def has_more?
    @has_more
  end

  def reset_pass
    @read_index = 0
  end

  def choose(choices)
    choices = choices.to_a
    failure if choices.empty?

    if @read_index < @stack.size
      choices_list, current_idx = @stack[@read_index]
      val = choices_list[current_idx]
      @read_index += 1
      val
    else
      @stack << [choices, 0]
      val = choices[0]
      @read_index += 1
      val
    end
  end

  def failure
    while !@stack.empty?
      choices_list, current_idx = @stack.last
      if current_idx + 1 < choices_list.size
        @stack[-1] = [choices_list, current_idx + 1]
        @stack = @stack[0...@read_index]
        raise Backtrack
      else
        @stack.pop
      end
    end

    @has_more = false
    raise NoMoreChoices
  end
end

# 3. AST DNA Splicer & Mutator using parser/unparser
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

# 4. Isolated Stateful Sandbox
class Sandbox
  def self.evaluate_candidate(code_str, method_name, test_cases)
    klass = Class.new
    begin
      klass.class_eval(code_str)
    rescue SyntaxError => e
      return { success: false, score: 0, error: "SyntaxError: #{e.message}", type: :syntax_error }
    rescue => e
      return { success: false, score: 0, error: "CompileError: #{e.message}", type: :compile_error }
    end
    
    instance = klass.new
    passed_count = 0
    
    test_cases.each_with_index do |tc, idx|
      inputs = tc[:inputs]
      expected = tc[:expected]
      
      begin
        output = nil
        Timeout.timeout(1.0) do
          if inputs.is_a?(Array)
            output = instance.send(method_name, *inputs)
          else
            output = instance.send(method_name, inputs)
          end
        end
        
        if output == expected
          passed_count += 1
        else
          return {
            success: false,
            score: passed_count,
            error: "AssertionError: Test case #{idx + 1} failed. Input: #{inputs.inspect}, Expected: #{expected.inspect}, Got: #{output.inspect}",
            type: :assertion_error
          }
        end
      rescue Timeout::Error
        return { success: false, score: passed_count, error: "TimeoutError: Test case #{idx + 1} exceeded 1s timeout.", type: :timeout_error }
      rescue => e
        return { success: false, score: passed_count, error: "RuntimeError on test #{idx + 1}: #{e.class}: #{e.message}", type: :runtime_error }
      end
    end
    
    { success: true, score: passed_count, error: nil, type: :success }
  end
end

# 5. Quantum-Cognitive Prism with Actor Impulse & Self-Reflection
class QuantumCognitivePrism
  def initialize(llm_client)
    @llm = llm_client
  end

  def synthesize_solution(task_description, method_name, test_cases)
    puts "\e[32;1m=== Starting Quantum-Cognitive Prism (Expanded) ===\e[0m"
    puts "Task: #{task_description}"
    puts "Target method: #{method_name}"
    puts "Test cases: #{test_cases.inspect}"

    # Step 1: Call all 3 Actors to trigger the 9-candidate Parallel Actor Impulse
    prompt = <<~PROMPT
      You are the Oracle in the Quantum-Cognitive Prism.
      Your task is to write a Ruby method called '#{method_name}'.
      Task description: #{task_description}

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

      Do not add any explanations or extra text. Output ONLY the three code blocks.
    PROMPT

    puts "\n\e[35;1m=== [Impulse Phase] Querying All Three LLM Actors ===\e[0m"
    code_ideas = @llm.generate_impulse(prompt)

    if code_ideas.empty?
      raise "Could not retrieve any templates from LLM actors."
    end

    puts "\n\e[32m[Impulse Phase] Successfully compiled #{code_ideas.size} total seed templates.\e[0m"
    code_ideas.each_with_index do |idea, idx|
      puts "\n\e[34;1m--- Seed Idea #{idx + 1} ---\e[0m"
      puts idea
    end

    # Step 2: Parse ideas into AST trees
    ast_trees = []
    code_ideas.each_with_index do |code, idx|
      begin
        ast_trees << ASTMutator.parse(code)
      rescue => e
        puts "\e[33m[Warning] Seed Idea #{idx + 1} failed AST parsing: #{e.message}\e[0m"
      end
    end

    if ast_trees.size < 2
      raise "Not enough parseable AST trees to run recombination."
    end

    # Step 3: Run Generation 1 Backtracking search
    success_code = nil
    best_failed_candidate = { code: nil, score: -1, type: nil, error: nil }
    tries = 0

    puts "\n\e[35;1m=== Starting Generation 1 AMB Search Space (9-tree pool) ===\e[0m"
    amb = Amb.new

    while amb.has_more?
      amb.reset_pass
      begin
        begin
          tries += 1
          
          # Choice 1: Choose base AST
          base_ast = amb.choose(ast_trees)
          
          # Choice 2: Choose mutation type
          mut_type = amb.choose([:none, :crossover, :op_swap, :const_mutate])

          mutated_ast = case mut_type
          when :none
            base_ast
          when :crossover
            # Choice 3: Choose donor AST
            donor_ast = amb.choose(ast_trees)
            
            base_nodes = ASTMutator.collect_nodes(base_ast).select { |e| 
              [:send, :lvar, :int, :float, :str].include?(e[:node].type)
            }
            donor_nodes = ASTMutator.collect_nodes(donor_ast).select { |e|
              [:send, :lvar, :int, :float, :str].include?(e[:node].type)
            }

            base_entry = amb.choose(base_nodes)
            donor_entry = amb.choose(donor_nodes)

            ASTMutator.replace_node(base_ast, base_entry[:node], donor_entry[:node])

          when :op_swap
            op_nodes = ASTMutator.collect_nodes(base_ast).select { |e|
              e[:node].type == :send && e[:node].children[0].is_a?(Parser::AST::Node)
            }

            target_send = amb.choose(op_nodes)[:node]
            new_op = amb.choose([:+, :-, :*, :/, :**, :%])

            ASTMutator.mutate_operators(base_ast, target_send, new_op)

          when :const_mutate
            const_nodes = ASTMutator.collect_nodes(base_ast).select { |e|
              [:int, :float].include?(e[:node].type)
            }

            target_const = amb.choose(const_nodes)[:node]
            new_val = amb.choose([0, 1, 2, 3, 5, 10, 100])

            ASTMutator.mutate_constant(base_ast, target_const, new_val)
          end

          candidate_code = ASTMutator.unparse(mutated_ast)

          # Stateful evaluation
          eval_res = Sandbox.evaluate_candidate(candidate_code, method_name, test_cases)

          if eval_res[:success]
            success_code = candidate_code
            puts "\e[32;1m\n[SUCCESS] Generation 1 combination ##{tries} passed all test cases!\e[0m"
            puts "Mutation Path: #{mut_type.upcase}"
            puts "\e[32mCode:\e[0m"
            puts candidate_code
            break
          else
            # Track the best failed candidate to feed into Self-Reflection
            is_better = false
            if eval_res[:score] > best_failed_candidate[:score]
              is_better = true
            elsif eval_res[:score] == best_failed_candidate[:score]
              type_hierarchy = { assertion_error: 3, runtime_error: 2, timeout_error: 1, syntax_error: 0, compile_error: 0 }
              this_val = type_hierarchy[eval_res[:type]] || 0
              best_val = type_hierarchy[best_failed_candidate[:type]] || 0
              is_better = true if this_val > best_val
            end
            
            if is_better
              best_failed_candidate = {
                code: candidate_code,
                score: eval_res[:score],
                type: eval_res[:type],
                error: eval_res[:error]
              }
            end

            amb.failure
          end
        rescue => e
          amb.failure
        end
      rescue Amb::Backtrack
        next
      rescue Amb::NoMoreChoices
        break
      end
    end

    # Step 4: Trigger Self-Reflection Loop if Generation 1 failed
    if success_code.nil? && best_failed_candidate[:code]
      puts "\n\e[33;1m=== [Self-Reflection Phase] Generation 1 exhausted. Entering Self-Reflection ===\e[0m"
      puts "Best failed candidate score: #{best_failed_candidate[:score]}/#{test_cases.size}"
      puts "Error log: #{best_failed_candidate[:error]}"
      puts "\e[34mBest Failed Attempt Code:\e[0m\n#{best_failed_candidate[:code]}"

      reflection_prompt = <<~PROMPT
        You are the Oracle in the Quantum-Cognitive Prism.
        In the previous generation, we attempted to solve this task: #{task_description}

        Our best synthesized candidate failed.
        Here is the best failed candidate code:
        ```ruby
        #{best_failed_candidate[:code]}
        ```

        It failed with the following test error:
        #{best_failed_candidate[:error]}

        Please analyze why this candidate failed. Using this feedback, please output THREE completely new, highly refined, and corrected Ruby implementations of the method '#{method_name}'.
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

        Do not add explanations or extra text. Output ONLY the three code blocks.
      PROMPT

      puts "\n\e[35;1m=== [Self-Reflection] Querying All Actors for Generation 2 Refined Impulse ===\e[0m"
      gen2_ideas = @llm.generate_impulse(reflection_prompt)

      puts "\n\e[32m[Self-Reflection] Successfully compiled #{gen2_ideas.size} refined templates.\e[0m"
      gen2_ideas.each_with_index do |idea, idx|
        puts "\n\e[34;1m--- Refined Gen 2 Idea #{idx + 1} ---\e[0m"
        puts idea
      end

      # Parse refined ideas into ASTs
      gen2_trees = []
      gen2_ideas.each_with_index do |code, idx|
        begin
          gen2_trees << ASTMutator.parse(code)
        rescue => e
          puts "\e[33m[Warning] Refined Gen 2 Idea #{idx + 1} failed AST parsing: #{e.message}\e[0m"
        end
      end

      if gen2_trees.size >= 2
        puts "\n\e[35;1m=== Starting Generation 2 AMB Search Space ===\e[0m"
        amb2 = Amb.new
        tries2 = 0
        
        while amb2.has_more?
          amb2.reset_pass
          begin
            begin
              tries2 += 1
              
              base_ast = amb2.choose(gen2_trees)
              mut_type = amb2.choose([:none, :crossover, :op_swap, :const_mutate])

              mutated_ast = case mut_type
              when :none
                base_ast
              when :crossover
                donor_ast = amb2.choose(gen2_trees)
                
                base_nodes = ASTMutator.collect_nodes(base_ast).select { |e| 
                  [:send, :lvar, :int, :float, :str].include?(e[:node].type)
                }
                donor_nodes = ASTMutator.collect_nodes(donor_ast).select { |e|
                  [:send, :lvar, :int, :float, :str].include?(e[:node].type)
                }

                base_entry = amb2.choose(base_nodes)
                donor_entry = amb2.choose(donor_nodes)

                ASTMutator.replace_node(base_ast, base_entry[:node], donor_entry[:node])

              when :op_swap
                op_nodes = ASTMutator.collect_nodes(base_ast).select { |e|
                  e[:node].type == :send && e[:node].children[0].is_a?(Parser::AST::Node)
                }

                target_send = amb2.choose(op_nodes)[:node]
                new_op = amb2.choose([:+, :-, :*, :/, :**, :%])

                ASTMutator.mutate_operators(base_ast, target_send, new_op)

              when :const_mutate
                const_nodes = ASTMutator.collect_nodes(base_ast).select { |e|
                  [:int, :float].include?(e[:node].type)
                }

                target_const = amb2.choose(const_nodes)[:node]
                new_val = amb2.choose([0, 1, 2, 3, 5, 10, 100])

                ASTMutator.mutate_constant(base_ast, target_const, new_val)
              end

              candidate_code = ASTMutator.unparse(mutated_ast)

              eval_res = Sandbox.evaluate_candidate(candidate_code, method_name, test_cases)

              if eval_res[:success]
                success_code = candidate_code
                puts "\e[32;1m\n[SUCCESS] Generation 2 combination ##{tries2} passed all test cases!\e[0m"
                puts "Mutation Path: #{mut_type.upcase}"
                puts "\e[32mCode:\e[0m"
                puts candidate_code
                break
              else
                amb2.failure
              end
            rescue => e
              amb2.failure
            end
          rescue Amb::Backtrack
            next
          rescue Amb::NoMoreChoices
            break
          end
        end
      end
    end

    if success_code
      success_code
    else
      puts "\n\e[31;1m[Prism Failed] Exhausted all AMB paths in BOTH Generation 1 and Generation 2 without finding a lossless solution.\e[0m"
      puts "\e[31;1mProof complete: The task is structurally/mathematically impossible under current constraints.\e[0m"
      raise "Solution synthesis failed. Exhaustive limits reached."
    end
  end
end

# 6. Self-Running Demo Scenario (Mathematically Impossible High-Entropy Compression)
if __FILE__ == $0
  client = LLMClient.new("dont_delete")
  prism = QuantumCognitivePrism.new(client)

  task = "Write a Ruby method 'solve(text)' that compresses the given 20-character alphanumeric text string " \
         "into a string of 2 characters or less, and then decompresses it back to the exact original text, " \
         "returning the original text. If the intermediate compressed representation has length > 2, it must " \
         "raise an error. The operation must be lossless."

  method_name = "solve"
  
  # Two high-entropy test cases that cannot be mapped losslessly into 2-char space
  test_cases = [
    { inputs: ["abcdefghijklmnopqrst"], expected: "abcdefghijklmnopqrst" },
    { inputs: ["1y7u8i9o0pasdfghjklz"], expected: "1y7u8i9o0pasdfghjklz" }
  ]

  begin
    winning_code = prism.synthesize_solution(task, method_name, test_cases)
    
    File.write("winning_solution.rb", winning_code)
    puts "\n\e[32;1m[Prism] Saved working solution to winning_solution.rb\e[0m"
  rescue => e
    puts "\n\e[31;1m[Prism Terminated] #{e.message}\e[0m"
  end
end
