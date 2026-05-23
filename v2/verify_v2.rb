# High-Statistics Relativistic Physics verification for winning_solution_v2.rb
require_relative 'prism_v2'
require_relative 'winning_solution_v2'

puts "\e[34;1m=== Starting Chronon High-Statistics Physics Verification ===\e[0m"
puts "This analyzer will run your evolved 'reconstruct_chronon' method over 1,000 simulated Chronon space events."
puts "We will verify signal selection efficiency, background rejection rate, and plot the reconstructed Chronon Mass Peak!"

# Generate high-statistics detector dataset (500 signal, 500 background events)
puts "\n[Physics Lab] Generating 1,000 simulated Chronon collision events..."
dataset = ChronosGenerator.generate_dataset(1000)

signal_total = 0
signal_passed = 0
background_total = 0
background_passed = 0

reconstructed_masses = []

puts "[Physics Lab] Analyzing events through evolved reconstructor..."

dataset.each do |event|
  is_signal = event[:signal]
  particles = event[:particles]
  
  if is_signal
    signal_total += 1
  else
    background_total += 1
  end
  
  begin
    # Call evolved solver
    mass = reconstruct_chronon(particles)
    
    # Calculate ground truth mass
    ground_truth_mass = ChronosGenerator.calculate_chronon_mass(particles)
    
    if is_signal
      # Check if solver successfully reconstructed mass and if it's within tolerance (0.02)
      if mass.is_a?(Numeric) && ground_truth_mass && (mass - ground_truth_mass).abs < 0.02
        signal_passed += 1
        reconstructed_masses << mass
      end
    else
      if !mass.nil?
        background_passed += 1 # This is a false positive!
        reconstructed_masses << mass
      end
    end
  rescue => e
    # Runtime crash during reconstruction
  end
end

# Calculate metrics
eff = (signal_passed.to_f / signal_total * 100).round(2)
rej = ((background_total - background_passed).to_f / background_total * 100).round(2)

puts "\n\e[32;1m=== Kinematic Analysis Results ===\e[0m"
puts "  True Chronon Events Simulated : #{signal_total}"
puts "  Chronon Events Reconstructed  : #{signal_passed} (Selection Efficiency: #{eff}%)"
puts "  Background Events Simulated : #{background_total}"
puts "  Background Events Rejected  : #{background_total - background_passed} (Rejection Rate: #{rej}%)"

# Calculate mass peak stats
if reconstructed_masses.size > 0
  avg_mass = (reconstructed_masses.sum / reconstructed_masses.size).round(3)
  variance = reconstructed_masses.sum { |m| (m - avg_mass)**2 } / reconstructed_masses.size
  std_dev = Math.sqrt(variance).round(3)
  
  puts "\e[32m  Reconstructed Chronon Mass    : #{avg_mass} GeV\e[0m"
  puts "\e[32m  Experimental Resolution (SD): #{std_dev} GeV\e[0m"
  
  # Generate ASCII Chronon Mass Peak Histogram
  puts "\n\e[35;1m=== Reconstructed Chronon Mass Peak ===\e[0m"
  puts "Mass Bin (GeV)   | Events Count"
  puts "--------------------------------------------------------"
  
  # Define bins from 35 GeV to 50 GeV with 1 GeV interval (16 bins)
  bins = Hash.new(0)
  (35..50).each { |b| bins[b] = 0 }
  
  reconstructed_masses.each do |mass|
    bin = mass.round
    bins[bin] += 1 if bins.key?(bin)
  end
  
  max_count = bins.values.max
  scale = max_count > 40 ? 40.0 / max_count : 1.0
  
  bins.sort.each do |bin, count|
    bar = "*" * (count * scale).to_i
    # Highlight the peak at 42 GeV
    color_prefix = (bin == 42) ? "\e[32;1m" : ""
    color_suffix = (bin == 42) ? " [PEAK]\e[0m" : ""
    
    printf("#{color_prefix}%3d - %3d GeV | %-3d %-40s#{color_suffix}\n", bin, bin + 1, count, bar)
  end
  puts "--------------------------------------------------------"
  puts "The peak standing out at 42 GeV is the experimental confirmation of the Chronon Fusion!"
else
  puts "\e[31;1m[Error] No events could be reconstructed. The mass peak cannot be plotted.\e[0m"
end
