import os
import sys

# Make the collector package importable when pytest is invoked from any cwd.
sys.path.insert(0, os.path.dirname(__file__))
