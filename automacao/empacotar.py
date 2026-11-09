"""Regere o pacote de implantação após editar controle.py."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

folder = Path(__file__).resolve().parent
with ZipFile(folder / "controle.zip", "w") as package:
    package.writestr(ZipInfo("controle.py"), (folder / "controle.py").read_bytes(),
                     compress_type=ZIP_DEFLATED)
