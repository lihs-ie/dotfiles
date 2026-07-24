import Tests

def main : IO UInt32 :=
  Idchain.Tests.runAll [
    Idchain.Tests.IdTests.suite
  ]
