module SwiftestTools
  def wait_until(delay=0.5)
	sleep delay until yield
  end
end
