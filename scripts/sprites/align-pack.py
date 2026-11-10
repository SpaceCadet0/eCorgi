#!/usr/bin/env python3
"""Выравнивание действий пака без пересэмплирования.

    python3 scripts/sprites/align-pack.py <пак> [--shift walk=1,run=1]
            [--tone walk,run --like idle] [--out <папка>] [--dry-run]

Две операции, обе попиксельные — ни один пиксель не интерполируется, поэтому
резкость кадров не меняется:

--shift  сдвигает кадры действия вверх на целое число пикселей (отрицательное —
         вниз). Отказывается работать, если при этом срезался бы рисунок.
--tone   приводит гамму действия к образцу (--like). Для каждого канала по
         сплошным пикселям обоих действий подбирается кривая «степень и
         усиление», совмещающая средние тона и света; чёрное не трогается.
         Кривая общая для всех кадров действия, так что мерцания нет.
         Образец должен быть похож по составу рисунка: ходьбу сравнивают со
         стойкой, а не со сном.

Без --out пишет поверх пака и сначала кладёт копию в
sprite-backups/<метка времени>/. С --dry-run только печатает числа.
"""
import argparse
import datetime
import glob
import os
import re
import shutil
import sys

import numpy as np
from PIL import Image

SOLID = 250


def frames(pack, action):
    found = [f for f in glob.glob(os.path.join(pack, action + "_*.png"))
             if re.fullmatch(re.escape(action) + r"_\d+", os.path.basename(f)[:-4])]
    if not found:
        sys.exit(f"нет кадров действия {action}")
    return sorted(found)


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).copy()


def solid_pixels(arrays):
    return np.concatenate([a[a[..., 3] >= SOLID][:, :3] for a in arrays])


def tone_curves(source, reference):
    """Кривая на канал: степень и усиление, v -> k * v^g.

    Подбирается по двум точкам — медиане и 95-му перцентилю канала. Чёрное
    остаётся чёрным: полное выравнивание распределений тянуло бы вверх и
    тени, а с ними глаза, нос и контур, которого в одном действии может быть
    больше, чем в другом.
    """
    curves = []
    x = np.arange(256) / 255.0
    for c in range(3):
        s50, s95 = np.percentile(source[:, c], [50, 95]) / 255.0
        r50, r95 = np.percentile(reference[:, c], [50, 95]) / 255.0
        g = np.log(r50 / r95) / np.log(s50 / s95) if s50 < s95 and r50 < r95 else 1.0
        g = float(np.clip(g, 0.5, 2.0))
        k = r95 / s95 ** g
        curves.append(np.clip(np.rint(255 * k * x ** g), 0, 255).astype(np.uint8))
    return curves


def describe(pixels):
    lum = pixels @ np.array([0.2126, 0.7152, 0.0722])
    p5, p50, p95 = np.percentile(lum, [5, 50, 95])
    sat = (pixels.max(1).astype(int) - pixels.min(1)).mean()
    return f"яркость {lum.mean():5.1f}  p5 {p5:3.0f}  p50 {p50:3.0f}  p95 {p95:3.0f}  насыщенность {sat:3.0f}"


def shifted_up(a, amount, name):
    if amount == 0:
        return a
    lost = a[:amount] if amount > 0 else a[amount:]
    if lost[..., 3].max() > 8:
        sys.exit(f"{name}: сдвиг на {amount} срезал бы рисунок")
    out = np.zeros_like(a)
    if amount > 0:
        out[:-amount] = a[amount:]
    else:
        out[-amount:] = a[:amount]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pack")
    ap.add_argument("--shift", default="")
    ap.add_argument("--tone", default="")
    ap.add_argument("--like", default="idle")
    ap.add_argument("--out")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    result = {}  # путь -> массив RGBA

    def current(path):
        return result[path] if path in result else load(path)

    for item in filter(None, args.shift.split(",")):
        action, amount = item.split("=")
        paths = frames(args.pack, action)
        for path in paths:
            result[path] = shifted_up(current(path), int(amount), os.path.basename(path))
        print(f"{action}: сдвиг вверх на {int(amount)} px, кадров {len(paths)}")

    if args.tone:
        reference = solid_pixels([load(p) for p in frames(args.pack, args.like)])
        print(f"образец {args.like:9}: {describe(reference)}")
        for action in args.tone.split(","):
            paths = frames(args.pack, action)
            source = solid_pixels([current(p) for p in paths])
            curves = tone_curves(source, reference)
            for path in paths:
                a = current(path)
                for c in range(3):
                    a[..., c] = curves[c][a[..., c]]
                # Полностью прозрачные пиксели оставляем нулевыми.
                a[a[..., 3] == 0] = 0
                result[path] = a
            print(f"{action:9} было   : {describe(source)}")
            print(f"{action:9} стало  : {describe(solid_pixels([result[p] for p in paths]))}")

    if args.dry_run or not result:
        print("ничего не записано")
        return

    if args.out:
        os.makedirs(args.out, exist_ok=True)

        def target(path):
            return os.path.join(args.out, os.path.basename(path))
    else:
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        backup = os.path.join(root, "sprite-backups", datetime.datetime.now().strftime("%Y-%m-%dT%H%M%S"))
        shutil.copytree(args.pack, backup)
        print(f"копия пака: {backup}")

        def target(path):
            return path

    for path, a in result.items():
        Image.fromarray(a, "RGBA").save(target(path), optimize=True)
    print(f"записано кадров: {len(result)}")


if __name__ == "__main__":
    main()
