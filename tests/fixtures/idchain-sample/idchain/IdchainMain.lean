import Canon
import Idchain.Cli

def main (args : List String) : IO UInt32 :=
  Idchain.Cli.run Canon.registry args
