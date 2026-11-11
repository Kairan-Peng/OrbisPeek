from pathlib import Path

def preview(path: Path) -> str:
    """仅预览，不执行。"""
    return path.name
