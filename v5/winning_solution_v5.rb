def mlkem_decrypt(s, u, v)
  q = 3329
  (s1, s2) = s
  (u1, u2) = u
  w = Array.new(256, 0)
  (0..255).each { |i,|
    (0..255).each { |j,|
      coeff = (s1.[](i) * u1.[](j) + s2.[](i).*(u2.[](j))) % q
      k = i + j
      if k < 256
        w.[]=(k, (w.[](k) + coeff) % q)
      else
        w.[]=(k - 256, (w.[](k - 256) - coeff + q) % q)
      end
    }
  }
  (0..255).each { |i,|
    w.[]=(i, (v.[](i) - w.[](i)) % q)
  }
  decoded = Array.new(256, 0)
  (0..255).each { |i,|
    w.[]=(i, w.[](i) % q)
    d_0 = [w.[](i), q - w.[](i)].min
    d_1664 = (w.[](i) - q./(2)).abs
    decoded.[]=(i, if d_0 < d_1664
      0
    else
      1
    end)
  }
  decoded
end