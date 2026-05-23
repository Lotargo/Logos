def reconstruct_weyl(particles)
  unless charge_conservation(particles)
    return nil
  end
  unless spin_resonance_projection(particles)
    return nil
  end
  numerator = particles.map { |p,|
    (p.[](:w) * p.[](:q)) ** 3 - (p.[](:x) ** 2 - p.[](:y).**(2)).*(Math.sin(p.[](:theta) * Math::PI / 180.0))
  }.sum
  denominator = particles.map { |p,|
    (p.[](:z) ** 2 + 1.0) * Math.cos(p.[](:spin) * Math::PI / 180.0)
  }.sum
  if denominator.abs < 1 || numerator / denominator < 0
    return nil
  end
  mass = Math.sqrt(numerator / denominator)
  if mass >= 83.0 && mass <= 85.0
    mass
  else
    nil
  end
end

def charge_conservation(particles)
  particles.map { |p,|
    p.[](:q)
  }.sum == 0
end

def spin_resonance_projection(particles)
  spin_rads = particles.map { |p,|
    p.[](:spin) * Math::PI / 180.0
  }
  spin_rads.sum >= 0.0
end
