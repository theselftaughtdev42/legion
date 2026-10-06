# Flatten skills/borrowed/SOURCES.yaml into one line per field:
#   <source> repo <url>
#   <source> ref <sha>
#   <source> skill <name> <upstream path>
# Usage: awk -f scripts/sources.awk skills/borrowed/SOURCES.yaml
/^[[:space:]]*(#|$)/ { next }
/^sources:/          { next }
/^  [^ ]/            { src = $1; sub(":$", "", src); in_skills = 0; next }
/^    skills:/       { in_skills = 1; next }
/^    [^ ]/          { key = $1; sub(":$", "", key); print src, key, $2; in_skills = 0; next }
/^      [^ ]/ && in_skills { name = $1; sub(":$", "", name); print src, "skill", name, $2 }
