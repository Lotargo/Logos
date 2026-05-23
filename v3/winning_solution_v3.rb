def reconstruct_chronon(particles)
  total_charge = particles.sum { |p,|
    p.[](:q)
  }
  unless total_charge == 6
    return nil
  end
  numerator = 0.0
  denominator = 0.0
  particles.each { |p,|
    (alpha, t, x, y, z, q, sigma) = [p.[](:alpha), p.[](:t), p.[](:x), p.[](:y), p.[](:z), p.[](:q), p.[](:sigma)]
    numerator += (alpha * t) ** 2 - (x ** 2 + y.**(2)) + (q * z)
    sigma_rad = sigma * Math::PI / 180.0
    denominator += Math.cos(sigma_rad)
  }
  if denominator.abs < 1.0e-06
    return nil
  end
  m_c = numerator / denominator
  if (41.0..43.0).cover?(m_c)
    m_c
  else
    nil
  end
end