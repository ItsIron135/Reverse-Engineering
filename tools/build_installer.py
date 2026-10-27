"""Generate install/Install.luau, a Studio command-bar installer embedding the sources in src/.

Usage: python tools/build_installer.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODULES = ["Config", "Unreal", "UnrealPerlin", "CameraShake", "SpringArm", "Movement", "LensEffects"]


def block(text):
    level = 1
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def main():
    src = ROOT / "src"
    template = (ROOT / "tools" / "Install.template.luau").read_text(encoding="utf-8")
    modules = ",\n".join(
        f'\t{{ "{name}", {block((src / "ReplicatedStorage" / "YHP" / f"{name}.luau").read_text(encoding="utf-8"))} }}'
        for name in MODULES
    )
    player = block((src / "StarterPlayerScripts" / "YHPPlayer.client.luau").read_text(encoding="utf-8"))
    out = template.replace("--@MODULES@", modules).replace("--@PLAYER@", player)
    (ROOT / "install").mkdir(exist_ok=True)
    (ROOT / "install" / "Install.luau").write_text(out, encoding="utf-8", newline="\n")
    print("wrote install/Install.luau", len(out), "bytes")


if __name__ == "__main__":
    main()
