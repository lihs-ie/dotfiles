import Idchain
import Idchain.Cli

def main (args : List String) : IO UInt32 :=
  Idchain.Cli.run Idchain.Registry.empty args
