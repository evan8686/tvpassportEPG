#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# TV Passport → XMLTV
# Spectrum - Manhattan, NY
# ============================================================

IMAGE="wgmaker/wgpp:latest"

LINEUP_ID="95433D"
LINEUP_NAME="Spectrum - Manhattan, NY"
DAYS="7"

WORKDIR="${GITHUB_WORKSPACE}/wgconfig"
WGDIR="${WORKDIR}/.wg++"
OUTDIR="${WORKDIR}/wg++"
FINAL_XML="${GITHUB_WORKSPACE}/output/tvpassport.xml"

CONTAINER="wgpp-epg"

cleanup() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf "${WORKDIR}"
mkdir -p "${WGDIR}" "${OUTDIR}"

echo "==> Using WebGrab+Plus image: ${IMAGE}"
docker pull "${IMAGE}"

# ------------------------------------------------------------
# Stage 1:
# Ask WebGrab+Plus to generate the TV Passport c2 channel list
# for the fixed Spectrum - Manhattan lineup.
#
# The current tvpassport.com.ini supports the c2 channel-list
# generation stage. The lineup ID is passed as site_id and the
# lineup name is passed as xmltv_id because the siteini uses
# config_xmltv_id as the lineupname parameter.
# ------------------------------------------------------------

cat > "${WGDIR}/WebGrab++.config.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<settings>
  <filename>/config/wg++/guide.xml</filename>
  <mode>n</mode>
  <user-agent>Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0 Safari/537.36</user-agent>
  <logging>on</logging>
  <retry time-out="15">4</retry>
  <timespan>0</timespan>
  <update>c2</update>

  <channel update="c2"
           site="tvpassport.com"
           site_id="${LINEUP_ID}"
           xmltv_id="${LINEUP_NAME}">${LINEUP_NAME}</channel>
</settings>
EOF

echo "==> Starting WebGrab+Plus container"

docker run --rm \
  --shm-size=1gb \
  -v "$WORKDIR/config:/config" \
  -v "$WORKDIR/output:/data" \
  "$IMAGE"
  tail -f /dev/null

echo "==> Generating TV Passport channel list (c2)"

docker exec "${CONTAINER}" bash -lc \
  'cd /config/.wg++ && ./run.net.sh'

C2_FILE="$(find "${OUTDIR}" -maxdepth 1 -type f -name 'tvpassport.com.channels.c2.xml' -print -quit || true)"

if [[ -z "${C2_FILE}" ]]; then
  echo "::error::WebGrab did not generate tvpassport.com.channels.c2.xml"
  echo "Generated files:"
  find "${WORKDIR}" -maxdepth 3 -type f -print | sort
  exit 1
fi

echo "==> Generated channel list: ${C2_FILE}"

CHANNEL_COUNT="$(grep -c '<channel ' "${C2_FILE}" || true)"

if [[ "${CHANNEL_COUNT}" -lt 10 ]]; then
  echo "::error::Only ${CHANNEL_COUNT} channels were generated. Refusing to continue."
  cat "${C2_FILE}"
  exit 1
fi

echo "==> Detected ${CHANNEL_COUNT} channels"

# ------------------------------------------------------------
# Stage 2:
# Convert the generated c2 channel list into the normal WG++
# configuration used for the actual EPG grab.
# ------------------------------------------------------------

python3 - "${C2_FILE}" "${WGDIR}/WebGrab++.config.xml" "${DAYS}" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

src, dst, days = sys.argv[1], sys.argv[2], sys.argv[3]

tree = ET.parse(src)
root = tree.getroot()

channels = root.findall(".//channel")
if not channels:
    raise SystemExit("No <channel> elements found in generated c2 file")

lines = []
for ch in channels:
    attrs = ch.attrib
    site = attrs.get("site")
    site_id = attrs.get("site_id")
    xmltv_id = attrs.get("xmltv_id")
    name = ch.text or xmltv_id or ""

    if not all((site, site_id, xmltv_id)):
        continue

    # XML ElementTree gives us safe XML escaping when constructing
    # the final document below.
    lines.append((site, site_id, xmltv_id, name))

def esc(value):
    return (value
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;"))

with open(dst, "w", encoding="utf-8") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
    f.write("<settings>\n")
    f.write("  <filename>/config/wg++/guide.xml</filename>\n")
    f.write("  <mode>n</mode>\n")
    f.write("  <user-agent>Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0 Safari/537.36</user-agent>\n")
    f.write("  <logging>on</logging>\n")
    f.write("  <retry time-out=\"15\">4</retry>\n")
    f.write(f"  <timespan>{esc(days)}</timespan>\n")
    f.write("  <update>i</update>\n\n")

    for site, site_id, xmltv_id, name in lines:
        f.write(
            f'  <channel update="i" site="{esc(site)}" '
            f'site_id="{esc(site_id)}" xmltv_id="{esc(xmltv_id)}">'
            f'{esc(name)}</channel>\n'
        )

    f.write("</settings>\n")

print(f"Wrote {len(lines)} channels to {dst}")
PY

# ------------------------------------------------------------
# Stage 3:
# Actual EPG grab.
# ------------------------------------------------------------

echo "==> Grabbing ${DAYS} days of EPG"

docker exec "${CONTAINER}" bash -lc \
  'cd /config/.wg++ && ./run.net.sh'

GUIDE="${OUTDIR}/guide.xml"

if [[ ! -s "${GUIDE}" ]]; then
  echo "::error::guide.xml was not generated or is empty."
  find "${WORKDIR}" -maxdepth 3 -type f -print | sort
  exit 1
fi

# ------------------------------------------------------------
# Stage 4:
# Validate before publishing.
# ------------------------------------------------------------

python3 - "${GUIDE}" "${FINAL_XML}" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

try:
    tree = ET.parse(src)
except Exception as e:
    raise SystemExit(f"Generated XMLTV is invalid XML: {e}")

root = tree.getroot()

channels = root.findall("channel")
programmes = root.findall("programme")

if len(channels) < 10:
    raise SystemExit(f"Only {len(channels)} channels in final XMLTV; refusing to publish")

if len(programmes) < 100:
    raise SystemExit(f"Only {len(programmes)} programmes in final XMLTV; refusing to publish")

dst.parent.mkdir(parents=True, exist_ok=True)
tree.write(dst, encoding="utf-8", xml_declaration=True)

print(f"Validated XMLTV: {len(channels)} channels, {len(programmes)} programmes")
PY

SIZE="$(stat -c%s "${FINAL_XML}")"

if [[ "${SIZE}" -lt 10000 ]]; then
  echo "::error::Final XMLTV is suspiciously small (${SIZE} bytes)."
  exit 1
fi

echo "=========================================="
echo "EPG update succeeded"
echo "Channels:  ${CHANNEL_COUNT}"
echo "File:      ${FINAL_XML}"
echo "Size:      ${SIZE} bytes"
echo "=========================================="
