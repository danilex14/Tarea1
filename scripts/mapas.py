#!/usr/bin/env python3
"""
Mapas del informe, desde los GeoJSON que deja scripts/exportar.sh (salidas/geojson/).

    pip install matplotlib        # única dependencia
    python3 scripts/mapas.py      # → salidas/mapas/*.png

No se conecta a la base: lee archivos exportados, así cualquiera puede rehacer los
mapas sin levantar Docker. Cada mapa lleva título, barra de color y la fecha/versión de
las fuentes (salidas/fuentes.json, lo escribe cargar.sh).
"""
import json
import math
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection, PolyCollection
from matplotlib.colors import Normalize
from matplotlib.cm import ScalarMappable

AQUI = os.path.dirname(os.path.abspath(__file__))
SAL = os.path.join(AQUI, "..", "salidas")
GJ = os.path.join(SAL, "geojson")
OUT = os.path.join(SAL, "mapas")
os.makedirs(OUT, exist_ok=True)

with open(os.path.join(SAL, "fuentes.json"), encoding="utf-8") as f:
    FUENTES = json.load(f)
PIE = f"Fuentes: OSM {FUENTES['osm']} · GTFS {FUENTES['gtfs']} · {FUENTES['dpa']}. SRID de cálculo 5361."
ASPECTO = 1 / math.cos(math.radians(33.44))   # 1° lon ≈ 0,83° lat a 33,4° S


def leer(capa):
    with open(os.path.join(GJ, f"{capa}.geojson"), encoding="utf-8") as f:
        return json.load(f)["features"]


def anillos(geom):
    t, c = geom["type"], geom["coordinates"]
    polys = c if t == "MultiPolygon" else [c]
    return [p[0] for p in polys]


def lineas(geom):
    t, c = geom["type"], geom["coordinates"]
    return c if t == "MultiLineString" else [c]


def poligonos(ax, feats, valor=None, cmap="viridis", norm=None, fc="none", ec="#555", lw=0.4, alpha=1.0, z=1):
    polys, vals = [], []
    for f in feats:
        if not f["geometry"]:
            continue
        for r in anillos(f["geometry"]):
            polys.append(r)
            vals.append(f["properties"].get(valor) if valor else 0)
    if valor:   # con valor: el color de relleno lo pone el colormap (no pasar facecolors)
        pc = PolyCollection(polys, edgecolors=ec, linewidths=lw, alpha=alpha, zorder=z)
    else:
        pc = PolyCollection(polys, facecolors=fc, edgecolors=ec, linewidths=lw, alpha=alpha, zorder=z)
    if valor:
        pc.set_array([v if v is not None else float("nan") for v in vals])
        pc.set_cmap(cmap)
        pc.set_norm(norm)
    ax.add_collection(pc)
    return pc


def lineas_col(ax, feats, color, lw=0.6, alpha=1.0, z=2):
    segs = [l for f in feats if f["geometry"] for l in lineas(f["geometry"])]
    ax.add_collection(LineCollection(segs, colors=color, linewidths=lw, alpha=alpha, zorder=z))


def puntos(ax, feats, color, s=4, z=3, label=None):
    xs = [f["geometry"]["coordinates"][0] for f in feats if f["geometry"]]
    ys = [f["geometry"]["coordinates"][1] for f in feats if f["geometry"]]
    ax.scatter(xs, ys, s=s, c=color, zorder=z, label=label, linewidths=0)


def marco(ax, titulo):
    z = leer("zona")[0]["geometry"]
    xs = [p[0] for p in anillos(z)[0]]; ys = [p[1] for p in anillos(z)[0]]
    ax.set_xlim(min(xs) - 0.005, max(xs) + 0.005); ax.set_ylim(min(ys) - 0.005, max(ys) + 0.005)
    ax.set_aspect(ASPECTO)
    ax.set_title(titulo, fontsize=11)
    ax.tick_params(labelsize=7)
    # barra de escala de 2 km
    x0, y0 = min(xs) + 0.01, min(ys) + 0.008
    dlon = 2000 / (111320 * math.cos(math.radians(33.44)))
    ax.plot([x0, x0 + dlon], [y0, y0], color="k", lw=2, zorder=10)
    ax.text(x0 + dlon / 2, y0 + 0.003, "2 km", ha="center", fontsize=7, zorder=10)


def etiquetas_comunas(ax, feats, minimo=0):
    for f in feats:
        r = max(anillos(f["geometry"]), key=len)
        x = sum(p[0] for p in r) / len(r); y = sum(p[1] for p in r) / len(r)
        ax.text(x, y, f["properties"]["comuna"], fontsize=5.5, ha="center", color="#222", zorder=6)


def guardar(fig, nombre):
    fig.text(0.01, 0.01, PIE, fontsize=6.5, color="#444")
    fig.savefig(os.path.join(OUT, nombre), dpi=170, bbox_inches="tight")
    plt.close(fig)
    print("✓", os.path.join("salidas", "mapas", nombre))


comunas = leer("comunas")

# ---------------------------------------------------------------- P6 · mapa principal
grilla = leer("q6_grilla")
top = leer("q6_top10")
fig, axs = plt.subplots(1, 2, figsize=(14, 6.2), layout="constrained")
for ax, campo, cmap, titulo in [
    (axs[0], "edificios", "magma_r", "Edificios OSM por hexágono (lado 500 m)"),
    (axs[1], "recorridos", "viridis", "Recorridos GTFS distintos que cruzan cada hexágono"),
]:
    vmax = max(f["properties"][campo] for f in grilla)
    norm = Normalize(0, vmax)
    pc = poligonos(ax, grilla, valor=campo, cmap=cmap, norm=norm, ec="white", lw=0.15)
    poligonos(ax, comunas, ec="#333", lw=0.5, z=4)
    poligonos(ax, top, ec="#00c2ff", lw=1.8, z=5)
    fig.colorbar(ScalarMappable(norm, cmap), ax=ax, shrink=0.75, label=campo)
    marco(ax, titulo)
fig.suptitle("P6 · Santiago centro: dónde hay muchos edificios y pocos recorridos "
             "(celeste: las 10 celdas con más edificios y menos recorridos)", fontsize=12)
guardar(fig, "p6_grilla_edificios_recorridos.png")

# ---------------------------------------------------------------- P2 · cobertura por comuna
cob = leer("q2_cobertura")
fig, axs = plt.subplots(1, 2, figsize=(14, 6.2), layout="constrained")
vmax = max(max(f["properties"]["pct_lejos_gtfs"], f["properties"]["pct_lejos_osm"]) for f in cob)
norm = Normalize(0, vmax)
for ax, campo, titulo in [(axs[0], "pct_lejos_gtfs", "Según paraderos GTFS (DTPM)"),
                          (axs[1], "pct_lejos_osm", "Según paraderos OSM (highway=bus_stop)")]:
    poligonos(ax, cob, valor=campo, cmap="OrRd", norm=norm, ec="#333", lw=0.5)
    etiquetas_comunas(ax, cob)
    fig.colorbar(ScalarMappable(norm, "OrRd"), ax=ax, shrink=0.75, label="% de edificios a más de 500 m")
    marco(ax, titulo)
fig.suptitle("P2 · % de edificios (OSM) a más de 500 m de cualquier paradero, por comuna", fontsize=12)
guardar(fig, "p2_cobertura_500m.png")

# ---------------------------------------------------------------- P3 · dos fuentes
fig, ax = plt.subplots(figsize=(8.5, 7))
poligonos(ax, comunas, ec="#999", lw=0.4)
puntos(ax, leer("q3_gtfs_sin_osm"), "#d62728", s=5, label="Paradero GTFS sin bus_stop OSM a 50 m")
puntos(ax, leer("q3_osm_sin_gtfs"), "#1f77b4", s=5, label="bus_stop OSM sin paradero GTFS a 50 m")
ax.legend(loc="upper right", fontsize=8, markerscale=3)
marco(ax, "P3 · Paraderos que solo existen en una de las dos fuentes (umbral 50 m)")
guardar(fig, "p3_dos_fuentes.png")

# ---------------------------------------------------------------- P7 · vías principales sin bus
vias = leer("q7_vias")
fig, ax = plt.subplots(figsize=(8.5, 7))
poligonos(ax, comunas, ec="#bbb", lw=0.4)
lineas_col(ax, [f for f in vias if f["properties"]["con_bus"]], "#9ecae1", lw=0.8)
lineas_col(ax, [f for f in vias if not f["properties"]["con_bus"]], "#e6550d", lw=1.2, z=3)
ax.plot([], [], color="#9ecae1", label="con recorrido de bus a ≤ 25 m")
ax.plot([], [], color="#e6550d", label="sin recorrido de bus")
ax.legend(loc="upper right", fontsize=8)
marco(ax, "P7 · Vías principales OSM (trunk–tertiary) con y sin buses GTFS")
guardar(fig, "p7_vias_sin_bus.png")

# ---------------------------------------------------------------- P1 · densidad de paraderos
q1 = leer("q1_comunas")
fig, ax = plt.subplots(figsize=(8.5, 7))
norm = Normalize(0, max(f["properties"]["por_km2"] for f in q1 if f["properties"]["pct_en_caja"] >= 50))
poligonos(ax, q1, valor="por_km2", cmap="YlGnBu", norm=norm, ec="#333", lw=0.5)
etiquetas_comunas(ax, q1)
lineas_col(ax, leer("rutas"), "#444", lw=0.15, alpha=0.5, z=3)
fig.colorbar(ScalarMappable(norm, "YlGnBu"), ax=ax, shrink=0.75, label="paraderos GTFS por km²")
marco(ax, "P1 · Densidad de paraderos GTFS por comuna (área dentro de la caja)")
guardar(fig, "p1_densidad_paraderos.png")
