"""
Test de module python

CEci est un test

"""

import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--message", type=str, default="yo", help="a afficher")
    args = parser.parse_args()
    print(args.message)
    