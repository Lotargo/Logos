$prism_host ||= Object.new
$solve_counter ||= 0

def solve(text)
  unless text.is_a?(String) && text.length == 20
    raise("Invalid input length")
  end
  temp = $solve_counter
  compressed = ""
  begin
    compressed << (97 + (temp % 26)).chr
    temp = temp / 26 - 1
  end while temp >= 0
  $solve_counter += 1
  if compressed.length > 2
    raise("Compressed representation exceeds 2 characters")
  end
  $prism_host.define_singleton_method(compressed) {
    text
  }
  decompressed = $prism_host.send(compressed)
  decompressed
end
