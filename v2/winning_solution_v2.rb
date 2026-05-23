def reconstruct_chronon(particles)
  if particles.sum { |p,|
    p.[](:q)
  } != 6
    return nil
  end
  numerator = particles.sum { |p,|
    (p.[](:alpha) * p.[](:t)) ** 2 - (p.[](:x) ** 2 + p.[](:y).**(2)) + (p.[](:q) * p.[](:z))
  }
  denominator = particles.sum { |p,|
    Math.cos(p.[](:sigma) * Math::PI / 180.0)
  }
  if denominator.abs < 1.0e-06
    return nil
  end
  mass = numerator / denominator
  if mass >= 41.0 && mass <= 43.0
    mass
  else
    nil
  end
end