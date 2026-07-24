import Tests

def main : IO UInt32 :=
  Idchain.Tests.runAll [
    Idchain.Tests.IdentifierTests.suite,
    Idchain.Tests.ArtifactTests.suite,
    Idchain.Tests.ChecksTests.suite,
    Idchain.Tests.CrosscheckTests.suite,
    Idchain.Tests.GenerationTests.suite
  ]
