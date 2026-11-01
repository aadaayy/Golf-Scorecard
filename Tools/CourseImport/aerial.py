"""Fetch free US government aerial photos (USGS NAIP, public domain) and the
OpenStreetMap golf features around one course, for tracing its holes by hand.

    python3 aerial.py LAT LNG RADIUS_M OUT_DIR

Writes OUT_DIR/photo-<row>-<col>.png (natural color) and photo-cir-<row>-<col>.png
(near-infrared false color, grass shows bright red), OUT_DIR/tiles.json with each
tile's Web Mercator bounds, and OUT_DIR/osm.json with the map features."""
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

SERVICE = "https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPPlus/ImageServer"
PIXEL = 0.6       # Web Mercator meters per pixel
TILE = 2000       # pixels


def merc(lat, lng):
    x = math.radians(lng) * 6378137
    y = math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)) * 6378137
    return x, y


def get(url, data=None, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": "yardage-book-course-tracing"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            print("retry", i, e)
            time.sleep(2 ** i * 3)
    raise SystemExit(f"couldn't get {url[:120]}")


def main():
    lat, lng, radius, out = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
    os.makedirs(out, exist_ok=True)
    scale = 1 / math.cos(math.radians(lat))
    cx, cy = merc(lat, lng)
    half = radius * scale
    span = TILE * PIXEL
    n = max(1, math.ceil(2 * half / span))
    x0, y1 = cx - n * span / 2, cy + n * span / 2
    info = json.loads(get(SERVICE + "?f=json"))
    print("Service:", info.get("name"), "max size", info.get("maxImageWidth"), info.get("maxImageHeight"))
    tiles = []
    for row in range(n):
        for col in range(n):
            bx0, by1 = x0 + col * span, y1 - row * span
            bbox = f"{bx0},{by1 - span},{bx0 + span},{by1}"
            for name, bands in (("photo", "0,1,2"), ("photo-cir", "3,0,1")):
                q = urllib.parse.urlencode({"bbox": bbox, "bboxSR": 3857, "imageSR": 3857, "size": f"{TILE},{TILE}",
                                            "format": "png", "bandIds": bands, "interpolation": "RSP_BilinearInterpolation",
                                            "f": "image"})
                body = get(SERVICE + "/exportImage?" + q)
                path = os.path.join(out, f"{name}-{row}-{col}.png")
                with open(path, "wb") as f:
                    f.write(body)
                print(path, len(body))
            tiles.append({"row": row, "col": col, "x0": bx0, "y1": by1, "pixel": PIXEL, "size": TILE})
    # When each photo was taken
    q = urllib.parse.urlencode({"geometry": f"{cx},{cy}", "geometryType": "esriGeometryPoint", "sr": 3857,
                                "returnGeometry": "false", "f": "json"})
    try:
        ident = json.loads(get(SERVICE + "/identify?" + q))
        print("Photo:", json.dumps(ident)[:600])
    except SystemExit:
        ident = None
    with open(os.path.join(out, "tiles.json"), "w") as f:
        json.dump({"lat": lat, "lng": lng, "tiles": tiles, "identify": ident}, f, indent=1)
    d = radius / 111320 * 1.2
    dl = d * scale
    box = f"{lat - d},{lng - dl},{lat + d},{lng + dl}"
    query = f"""[out:json][timeout:90];
(nwr["leisure"="golf_course"]({box});nwr["golf"]({box});nwr["natural"="water"]({box});
 nwr["water"]({box});nwr["building"]({box});nwr["highway"]({box}););out geom;"""
    body = get("https://overpass-api.de/api/interpreter", urllib.parse.urlencode({"data": query}).encode())
    with open(os.path.join(out, "osm.json"), "wb") as f:
        f.write(body)
    print("OSM features:", len(json.loads(body)["elements"]))


if __name__ == "__main__":
    main()
