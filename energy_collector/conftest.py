"""conftest raiz do energy_collector.

Garante que a pasta do projeto esteja no ``sys.path`` para que os testes
consigam importar o pacote ``collector`` independentemente do diretorio
de onde o pytest for invocado.
"""

from __future__ import annotations

import sys
from pathlib import Path

_ROOT = str(Path(__file__).resolve().parent)
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
