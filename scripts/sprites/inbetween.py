#!/usr/bin/env python3
"""Промежуточные кадры между кадрами действия — без размытия и без новых цветов.

    python3 scripts/sprites/inbetween.py <пак> <действие> <куда> [--target 5] [--loop]

Читает <пак>/<действие>_NN.png, пишет в <куда> полный новый цикл
<действие>_NN.png (исходные кадры копируются байт в байт, только с новыми
номерами) и печатает, сколько кадров вставлено в каждый промежуток.
В пак ничего не пишет — переносить кадры отдельно, с резервной копией.

Сколько кадров вставлять, решает расстояние между соседями: 90-й перцентиль
длины оптического потока по силуэту, в пикселях. У ходьбы оно ~1.8, у бега
~5.7 — при 12 кадрах в секунду оба смотрятся плавно, поэтому по умолчанию
цель 5: промежуток делится так, чтобы шаг между кадрами не превышал её.

Почему не смешивание. Наложение двух кадров с прозрачностью даёт двоение и
мыло. Здесь каждый пиксель нового кадра — это пиксель одного из исходных
кадров, сдвинутый вдоль потока выборкой «ближайший сосед». Поэтому цвета
остаются из палитры кадров, а контур и альфа на кромке — такими же резкими.
Источник выбирается по времени (до середины — левый кадр, после — правый),
а там, где точка в нём заслонена, берётся из другого.

Нужны numpy, Pillow и opencv-contrib-python-headless (DeepFlow).
"""
import argparse
import glob
import os
import re
import shutil
import sys

import numpy as np
from PIL import Image

try:
    import cv2
except ImportError:
    sys.exit("нужен OpenCV: pip install opencv-contrib-python-headless")

SOLID = 32  # с какой альфы пиксель считается частью рисунка, а не ореолом
UP = 4  # поток считается на увеличенном кадре: спрайт мелкий, нужна точность до долей пикселя


def load_action(pack, action):
    paths = glob.glob(os.path.join(pack, f"{action}_*.png"))
    paths = [p for p in paths if re.fullmatch(rf"{re.escape(action)}_\d+\.png", os.path.basename(p))]
    paths.sort(key=lambda p: int(re.findall(r"(\d+)\.png$", p)[0]))
    return paths, [np.array(Image.open(p).convert("RGBA")) for p in paths]


def flow_image(a):
    """Серое изображение для потока: яркость по силуэту, фон чёрный, кромка силуэта видна."""
    rgb = a[..., :3].astype(np.float32)
    al = a[..., 3].astype(np.float32) / 255
    g = rgb.mean(axis=2) * al * 0.8 + al * 50
    g = np.clip(g, 0, 255).astype(np.uint8)
    return cv2.resize(g, None, fx=UP, fy=UP, interpolation=cv2.INTER_CUBIC)


def dense_flow(a, b):
    """Поток a->b в пикселях исходного размера.

    DeepFlow из opencv-contrib: на поворотах деталей (уши) он держит форму
    заметно лучше DIS, а кадры мелкие — медлительность не мешает.
    """
    if hasattr(cv2, "optflow"):
        f = cv2.optflow.createOptFlow_DeepFlow().calc(flow_image(a), flow_image(b), None)
    else:
        print("нет opencv-contrib, беру DIS — уши будут хуже", file=sys.stderr)
        dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
        dis.setFinestScale(0)
        f = dis.calc(flow_image(a), flow_image(b), None)
    return cv2.resize(f, (a.shape[1], a.shape[0]), interpolation=cv2.INTER_AREA) / UP


def centroid(a):
    ys, xs = np.nonzero(a[..., 3] > 127)
    return np.array([xs.mean(), ys.mean()])


def pair_flow(a, b):
    """Поток a->b: общий сдвиг тела плюс локальная часть, посчитанная после выравнивания."""
    s = np.round(centroid(b) - centroid(a)).astype(int)
    m = np.float32([[1, 0, -s[0]], [0, 1, -s[1]]])
    b_al = cv2.warpAffine(b, m, (b.shape[1], b.shape[0]), flags=cv2.INTER_NEAREST, borderValue=0)
    f = dense_flow(a, b_al)
    f[..., 0] += s[0]
    f[..., 1] += s[1]
    return f


def gap(a, b):
    f = pair_flow(a, b)
    mask = (a[..., 3] > 127) | (b[..., 3] > 127)
    return float(np.percentile(np.linalg.norm(f, axis=2)[mask], 90))


def sample(img, fx, fy):
    """Выборка «ближайший сосед»; координаты вне холста дают прозрачный пиксель."""
    h, w = img.shape[:2]
    xi = np.rint(fx).astype(int)
    yi = np.rint(fy).astype(int)
    ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
    out = np.zeros((h, w) + img.shape[2:], img.dtype)
    out[ok] = img[yi[ok], xi[ok]]
    return out


def splat_back(f, mask, t):
    """Для каждой точки кадра t — смещение назад, к пикселю источника.

    Непрозрачные пиксели источника летят в x + t·f; в точку прилёта
    записывается обратное смещение. Дыры от растяжения заполняются
    смещением ближайшей точки, куда что-то прилетело.
    """
    h, w = mask.shape
    ys, xs = np.nonzero(mask)
    tx = np.rint(xs + t * f[ys, xs, 0]).astype(int)
    ty = np.rint(ys + t * f[ys, xs, 1]).astype(int)
    ok = (tx >= 0) & (tx < w) & (ty >= 0) & (ty < h)
    back = np.zeros((h, w, 2), np.float32)
    hit = np.zeros((h, w), bool)
    back[ty[ok], tx[ok]] = -t * f[ys[ok], xs[ok]]
    hit[ty[ok], tx[ok]] = True
    if hit.any() and not hit.all():
        _, lab = cv2.distanceTransformWithLabels((~hit).astype(np.uint8), cv2.DIST_L2, 3,
                                                 labelType=cv2.DIST_LABEL_PIXEL)
        lut = np.zeros((lab.max() + 1, 2), np.float32)
        lut[lab[hit]] = back[hit]
        back = lut[lab]
    # дыры внутри силуэта закрываем, снаружи оставляем пустыми
    hit = cv2.morphologyEx(hit.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)) > 0
    return back, hit


def visible(fwd, bwd):
    """Пиксель виден в другом кадре, если путь туда и обратно возвращает в ту же точку."""
    h, w = fwd.shape[:2]
    gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
    xs, ys = gx + fwd[..., 0], gy + fwd[..., 1]
    bx = cv2.remap(bwd[..., 0], xs, ys, cv2.INTER_LINEAR, borderValue=1e3)
    by = cv2.remap(bwd[..., 1], xs, ys, cv2.INTER_LINEAR, borderValue=1e3)
    err = np.hypot(fwd[..., 0] + bx, fwd[..., 1] + by)
    return err < 1.5 + 0.15 * np.hypot(fwd[..., 0], fwd[..., 1])


def steady(f, ok, sigma=4.0):
    """Поток, где он ненадёжен, заменяется плавным потоком надёжной окрестности.

    Деталь, которая меняет форму (ухо из прижатого становится торчащим),
    не имеет пары в другом кадре; сырой поток её рвёт, и на её месте
    вырастает «мех». Такой участок лучше не деформировать, а нести целиком
    вместе с окружением — тогда он чисто сменится на середине перехода.
    """
    w = ok.astype(np.float32)
    k = (0, 0)
    den = cv2.GaussianBlur(w, k, sigma) + 1e-6
    sm = np.dstack([cv2.GaussianBlur(f[..., c] * w, k, sigma) / den for c in (0, 1)])
    # где надёжных соседей нет совсем — средний надёжный поток кадра
    far = den < 0.05
    if far.any() and ok.any():
        sm[far] = f[ok].mean(axis=0)
    return np.where(ok[..., None], f, sm)


def reliable(fwd, bwd, solid):
    """Участки силуэта, где потоку можно верить.

    Два признака беды. Проверка «туда и обратно» не сходится — у детали
    нет пары (ухо сменило форму). Или поток выворачивает участок: якобиан
    почти ноль или отрицательный — так большой поднятый хвост сжимается
    в маленький опущенный, и в промежутке он рвётся в тонкий крючок с
    дырами, хотя поток туда-обратно согласован. На обычных парах якобиан
    не опускается ниже ~0.25.

    Ненадёжным считается только связное пятно: одиночные промахи на
    кромке — обычный шум, а не деталь без пары.
    """
    fs = cv2.GaussianBlur(fwd, (0, 0), 1.5)
    ux, uy = np.gradient(fs[..., 0], axis=1), np.gradient(fs[..., 0], axis=0)
    vx, vy = np.gradient(fs[..., 1], axis=1), np.gradient(fs[..., 1], axis=0)
    det = (1 + ux) * (1 + vy) - uy * vx
    folds = (det < 0.2) | (det > 4)
    bad = ((~visible(fwd, bwd) | folds) & solid).astype(np.uint8)
    bad = cv2.morphologyEx(bad, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    bad = cv2.dilate(bad, np.ones((5, 5), np.uint8)) > 0
    return ~bad


def inbetween(a, b, fab, fba, t):
    """Кадр в момент t (0..1) между a и b."""
    h, w = a.shape[:2]
    gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)

    ok_a = reliable(fab, fba, a[..., 3] >= SOLID)
    ok_b = reliable(fba, fab, b[..., 3] >= SOLID)
    fab, fba = steady(fab, ok_a), steady(fba, ok_b)

    # летят только плотные пиксели: у кадров вокруг силуэта есть почти
    # невидимый ореол (альфа 1–6, след Ланцоша), поток в нём бессмыслен,
    # и он рисовал непрозрачные нитки под лапами
    back_a, hit_a = splat_back(fab, a[..., 3] >= SOLID, t)
    back_b, hit_b = splat_back(fba, b[..., 3] >= SOLID, 1 - t)
    ring = np.ones((3, 3), np.uint8)
    hit_a = cv2.dilate(hit_a.astype(np.uint8), ring) > 0  # кромка сглаживания вокруг
    hit_b = cv2.dilate(hit_b.astype(np.uint8), ring) > 0
    ax, ay = gx + back_a[..., 0], gy + back_a[..., 1]
    bx, by = gx + back_b[..., 0], gy + back_b[..., 1]
    from_a = sample(a, ax, ay)
    from_b = sample(b, bx, by)
    good_a = hit_a & sample(ok_a, ax, ay)
    good_b = hit_b & sample(ok_b, bx, by)

    # основной кадр (ближний по времени) даёт всё, что до него долетело;
    # второй — только надёжные пиксели, иначе кончик прижатого уха из
    # одного кадра торчал бы рядом с поднятым ухом из другого
    # и только там, куда основной не долетел (открывшиеся участки)
    if t < 0.5:
        use_a = hit_a
        covered = hit_a | good_b
    else:
        use_a = ~hit_b & good_a
        covered = hit_b | good_a
    out = np.where(use_a[..., None], from_a, from_b)
    out[~covered] = 0
    out = clean(out)
    if t < 0.5:
        return smooth_edge(out, outline_field(a), ax, ay)
    return smooth_edge(out, outline_field(b), bx, by)


def outline_field(src):
    """Для каждой точки кадра — цвет ближайшего пикселя его внешней обводки."""
    m = (src[..., 3] >= 128).astype(np.uint8)
    ring = (m > 0) & ~(cv2.erode(m, np.ones((3, 3), np.uint8)) > 0)
    _, lab = cv2.distanceTransformWithLabels((~ring).astype(np.uint8), cv2.DIST_L2, 3,
                                             labelType=cv2.DIST_LABEL_PIXEL)
    lut = np.zeros((lab.max() + 1, 4), np.uint8)
    lut[lab[ring]] = src[ring]
    return lut[lab]


def smooth_edge(f, field, sx, sy):
    """Ровный край силуэта вместо ступенек от выборки «ближайший сосед».

    Силуэт сглаживается на увеличенной маске, кромка получает альфу по
    доле покрытия, а цвет — обводки исходного кадра (из той точки, откуда
    пришёл пиксель). Так возвращается тёмный контур, который выборка рвала,
    и новых цветов не появляется. Внутренность силуэта не трогается.
    """
    h, w = f.shape[:2]
    up = 4
    m = (f[..., 3] >= 128).astype(np.float32)
    big = cv2.resize(m, (w * up, h * up), interpolation=cv2.INTER_LINEAR)
    big = cv2.GaussianBlur(big, (0, 0), up * 0.8)
    cov = cv2.resize((big > 0.5).astype(np.float32), (w, h), interpolation=cv2.INTER_AREA)
    inside = cov >= 0.5
    k3 = np.ones((3, 3), np.uint8)
    ring = inside & ~(cv2.erode(inside.astype(np.uint8), k3) > 0)
    edge = ring | ((cov > 0) & ~inside)
    out = f.copy()
    # внутрь, куда при сглаживании добавились пиксели, — цвет ближайшего соседа
    hole = inside & ~ring & (f[..., 3] < 128)
    if hole.any():
        solid = f[..., 3] >= 128
        _, lab = cv2.distanceTransformWithLabels((~solid).astype(np.uint8), cv2.DIST_L2, 3,
                                                 labelType=cv2.DIST_LABEL_PIXEL)
        lut = np.zeros((lab.max() + 1, 4), np.uint8)
        lut[lab[solid]] = f[solid]
        out[hole] = lut[lab][hole]
    col = sample(field, sx, sy)
    out[edge, :3] = col[edge, :3]
    out[edge, 3] = np.where(ring[edge], col[edge, 3],
                            np.clip(cov[edge] * 2, 0, 1) * col[edge, 3] * 0.5).astype(np.uint8)
    out[~inside & ~edge] = 0
    return out


def clean(f):
    """Убирает мусор разбрасывания: одиночные пиксели, тонкие нитки и оторванные клочки.

    Там, где поток ошибся, отдельные пиксели кромки улетают от тела и рисуют
    тонкую линию под лапами или висящий кончик хвоста. Пиксель с двумя и
    меньше соседями — такая нитка; клочок много меньше тела — такой обрывок.
    """
    m = f[..., 3] >= SOLID
    k = np.ones((3, 3), np.float32)
    for _ in range(3):
        nb = cv2.filter2D(m.astype(np.float32), -1, k, borderType=cv2.BORDER_CONSTANT) - m
        m &= nb >= 3
    # клочки ищутся по плотным пикселям (альфа ≥ 128), связанным сторонами:
    # бугорок, который касается тела только по диагонали или через почти
    # прозрачный пиксель, иначе считался бы его частью. Остальное остаётся,
    # только если прилегает к уцелевшему телу. На 152 кадрах пака такая
    # чистка не снимает ни пикселя — настоящие детали она не трогает
    k3 = np.ones((3, 3), np.uint8)
    core = (f[..., 3] >= 128) & m
    n, lab, st, _ = cv2.connectedComponentsWithStats(core.astype(np.uint8), connectivity=4)
    if n > 1:
        areas = st[1:, cv2.CC_STAT_AREA]
        keep = np.zeros(n, bool)
        keep[1:] = areas >= max(areas.max() * 0.03, 12)
        core = keep[lab]
        m &= core | (cv2.dilate(core.astype(np.uint8), k3) > 0)
    # полупрозрачная кромка остаётся только вплотную к телу
    # (только почти прозрачная — иначе по цепочке вернулись бы и клочки)
    faint = (f[..., 3] > 0) & (f[..., 3] < SOLID)
    m |= faint & (cv2.dilate(m.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
    out = f.copy()
    out[~m] = 0
    return out


def color_keys(f):
    c = f[f[..., 3] == 255][:, :3].astype(np.int64)
    return (c[:, 0] << 16) | (c[:, 1] << 8) | c[:, 2]


def stats(frame, palette):
    al = frame[..., 3]
    keys = color_keys(frame)
    off = 1 - np.isin(keys, palette).mean() if len(keys) else 0.0
    cols = frame[al == 255][:, :3].astype(np.float32)
    dark = (cols.mean(axis=1) < 70).mean() if len(cols) else 0.0
    edge = ((al > 0) & (al < 255)).sum() / max((al > 0).sum(), 1)
    return off, dark, edge


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pack")
    ap.add_argument("action")
    ap.add_argument("out")
    ap.add_argument("--target", type=float, default=5.0,
                    help="предельный шаг между кадрами, px (ходьба ~1.8, бег ~5.7)")
    ap.add_argument("--loop", action="store_true", help="цикл: вставлять и между последним и первым")
    ap.add_argument("--fps", type=float, default=12)
    ap.add_argument("--dry-run", action="store_true", help="только посчитать промежутки")
    args = ap.parse_args()

    paths, frames = load_action(args.pack, args.action)
    if len(frames) < 2:
        sys.exit(f"нет кадров {args.action}_NN.png в {args.pack}")
    if os.path.realpath(args.out) == os.path.realpath(args.pack):
        sys.exit("писать прямо в пак нельзя: укажи отдельную папку")
    n = len(frames)
    pairs = [(i, (i + 1) % n) for i in range(n if args.loop else n - 1)]

    plan = []
    for i, j in pairs:
        g = gap(frames[i], frames[j])
        plan.append((i, j, g, max(int(np.ceil(g / args.target)) - 1, 0)))
    total = n + sum(p[3] for p in plan)
    print(f"{args.action}: {n} кадров -> {total}; при {args.fps:g} fps "
          f"{n / args.fps:.2f} с -> {total / args.fps:.2f} с")
    for i, j, g, k in plan:
        print(f"  {i:02d}->{j:02d}  шаг {g:5.1f}px  вставить {k}"
              + (f"  (шаг станет ~{g / (k + 1):.1f})" if k else ""))
    if args.dry_run:
        return

    palette = np.unique(np.concatenate([color_keys(f) for f in frames]))
    ks = np.array([stats(f, palette) for f in frames])
    print(f"исходные кадры: тёмного контура {ks[:, 1].mean():.1%}, "
          f"полупрозрачной кромки {ks[:, 2].mean():.1%}")

    os.makedirs(args.out, exist_ok=True)
    for old in glob.glob(os.path.join(args.out, f"{args.action}_*.png")):
        os.remove(old)
    idx = 0

    def name():
        return os.path.join(args.out, f"{args.action}_{idx:02d}.png")

    for i, j, g, k in plan:
        shutil.copyfile(paths[i], name())
        idx += 1
        if not k:
            continue
        fab = pair_flow(frames[i], frames[j])
        fba = pair_flow(frames[j], frames[i])
        for s in range(1, k + 1):
            t = s / (k + 1)
            f = inbetween(frames[i], frames[j], fab, fba, t)
            off, dark, edge = stats(f, palette)
            Image.fromarray(f, "RGBA").save(name())
            print(f"  {args.action}_{idx:02d}  {i:02d}->{j:02d} t={t:.2f}  вне палитры {off:.1%}  "
                  f"контур {dark:.1%}  кромка {edge:.1%}")
            idx += 1
    if not args.loop:
        shutil.copyfile(paths[n - 1], name())
        idx += 1
    print(f"записано {idx} кадров в {args.out}")


if __name__ == "__main__":
    main()
