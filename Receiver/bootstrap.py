import sys
sys.dont_write_bytecode = True
import runpy
from pathlib import Path
base = Path(__file__).resolve().parent
sys.path.insert(0, str(base / "vendor"))
runpy.run_path(str(base / "receiver.py"), run_name="__main__")
