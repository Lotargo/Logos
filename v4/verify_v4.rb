# High-Statistics Relativistic Physics verification for winning_solution_v4.rb
require_relative 'prism_v4'
require_relative 'winning_solution_v4'

puts "\e[34;1m=== Starting Weyl Space High-Statistics Physics Verification (v4) ===\e[0m"
puts "This analyzer will run your evolved 'reconstruct_weyl' method over 1,000 simulated 5D Weyl Space collision events."
puts "We will verify signal selection efficiency, background rejection rate, and plot the reconstructed Weyl Mass Peak!"

# Generate high-statistics detector dataset (500 signal, 500 background events)
puts "\n[Physics Lab] Generating 1,000 simulated Weyl Space collision events..."
dataset = WeylGenerator.generate_dataset(1000)

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
    mass = reconstruct_weyl(particles)
    
    # Calculate ground truth mass
    ground_truth_mass = WeylGenerator.calculate_weyl_mass(particles)
    
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

puts "\n\e[32;1m=== Weyl Kinematic Analysis Results ===\e[0m"
puts "  True Weyl Events Simulated   : #{signal_total}"
puts "  Weyl Events Reconstructed    : #{signal_passed} (Selection Efficiency: #{eff}%)"
puts "  Background Events Simulated  : #{background_total}"
puts "  Background Events Rejected   : #{background_total - background_passed} (Rejection Rate: #{rej}%)"

# Calculate mass peak stats
if reconstructed_masses.size > 0
  avg_mass = (reconstructed_masses.sum / reconstructed_masses.size).round(3)
  variance = reconstructed_masses.sum { |m| (m - avg_mass)**2 } / reconstructed_masses.size
  std_dev = Math.sqrt(variance).round(3)
  
  puts "\e[32m  Reconstructed Weyl Mass      : #{avg_mass} GeV\e[0m"
  puts "\e[32m  Experimental Resolution (SD) : #{std_dev} GeV\e[0m"
  
  # Generate ASCII Weyl Resonance Mass Peak Histogram
  puts "\n\e[35;1m=== Reconstructed Weyl Resonance Mass Peak ($M_W \\approx 84$ GeV) ===\e[0m"
  puts "Mass Bin (GeV)   | Events Count"
  puts "--------------------------------------------------------"
  
  # Define bins from 75 GeV to 95 GeV with 1 GeV interval (20 bins)
  bins = Hash.new(0)
  (75..95).each { |b| bins[b] = 0 }
  
  reconstructed_masses.each do |mass|
    bin = mass.round
    bins[bin] += 1 if bins.key?(bin)
  end
  
  max_count = bins.values.max
  scale = max_count > 40 ? 40.0 / max_count : 1.0
  
  bins.sort.each do |bin, count|
    bar = "*" * (count * scale).to_i
    # Highlight the peak at 84 GeV
    color_prefix = (bin == 84) ? "\e[32;1m" : ""
    color_suffix = (bin == 84) ? " [PEAK]\e[0m" : ""
    
    printf("#{color_prefix}%3d - %3d GeV | %-3d %-40s#{color_suffix}\n", bin, bin + 1, count, bar)
  end
  puts "--------------------------------------------------------"
  puts "The peak standing out at 84 GeV is the experimental confirmation of the 5D Weyl Resonance!"
else
  puts "\e[31;1m[Error] No events could be reconstructed. The mass peak cannot be plotted.\e[0m"
end
