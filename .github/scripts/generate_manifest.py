#!/usr/bin/env python3
"""
Gera o manifest.json a partir da raiz do repositório do client.

Para cada arquivo registra: caminho relativo (com '/'), SHA256 e tamanho.
Usado pela GitHub Action .github/workflows/generate-manifest.yml.
"""

import hashlib
import json
import os
from datetime import datetime, timezone

ROOT = "."

# Pastas ignoradas (no nível raiz) e arquivos que não fazem parte do client.
EXCLUDE_DIRS = {".git", ".github"}
EXCLUDE_NAMES = {
    "manifest.json",
    "launcher.log",
    ".launcher_cache.json",
    "config.json",
    "ValdrakenLauncher.exe",
    "ValdrakenLauncher.pdb",
}


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    files = []

    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = ""
            # Não desce em .git/.github (só existem na raiz).
            dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]

        for name in filenames:
            if name in EXCLUDE_NAMES:
                continue
            rel = f"{rel_dir}/{name}" if rel_dir else name
            full = os.path.join(dirpath, name)
            files.append({
                "path": rel,
                "sha256": sha256_of(full),
                "size": os.path.getsize(full),
            })

    files.sort(key=lambda x: x["path"])

    now = datetime.now(timezone.utc)
    manifest = {
        "version": now.strftime("%Y%m%d-%H%M%S"),
        "generated": now.isoformat(),
        "count": len(files),
        "files": files,
    }

    with open("manifest.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    print(f"Manifest gerado: {len(files)} arquivos, versao {manifest['version']}")


if __name__ == "__main__":
    main()
