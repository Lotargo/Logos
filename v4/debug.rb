require_relative 'prism_v4'
require_relative 'winning_solution_v4'

# Generate one signal event
dataset = WeylGenerator.generate_dataset(10)
signal_event = dataset.find { |e| e[:signal] }
particles = signal_event[:particles]

puts "=== Particle Details ==="
particles.each_with_index do |p, i|
  puts "Particle #{i+1}: q=#{p[:q]}, spin=#{p[:spin]}, theta=#{p[:theta]}, w=#{p[:w]}, x=#{p[:x]}, y=#{p[:y]}, z=#{p[:z]}"
end

# Check ground truth
gt = WeylGenerator.calculate_weyl_mass(particles)
puts "\nGround Truth Mass: #{gt.inspect}"

# Trace reconstruct_weyl step-by-step
puts "\n--- Tracing reconstruct_weyl ---"
q_sum = particles.map { |p| p[:q] }.sum
puts "Weyl Charge sum: #{q_sum} (Expected 0)"

spin_radians = particles.flat_map { |p| [p[:spin]] }.map { |s| s * Math::PI / 180.0 }.sum
puts "Spin sum (radians): #{spin_radians} (Expected >= 0.0)"

numerator = particles.map { |p|
  (p[:w] * p[:q]) ** 3 - (p[:x] ** 2 - p[:y]**2) * Math.sin(p[:theta] * Math::PI / 180.0)
}.sum
puts "Numerator: #{numerator}"

denominator = particles.map { |p|
  (p[:z] ** 2 + 1.0) * Math.cos(p[:spin] * Math::PI / 180.0)
}.sum
puts "Denominator: #{denominator}"

val_under_sqrt = numerator / denominator
puts "Value under sqrt: #{val_under_sqrt}"

mass = Math.sqrt(val_under_sqrt) rescue nil
puts "Mass before round: #{mass.inspect}"

# Call the actual method
out = reconstruct_weyl(particles)
puts "\nActual Reconstructor Return: #{out.inspect}"
