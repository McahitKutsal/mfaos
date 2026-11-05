#!/usr/bin/env bash
# Derleme adimlarini sirayla calistirir.
# Hata olursa derleme durur — yarim imaj uretmek istemiyoruz.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> ${OS_PRETTY_NAME:-mfaos} derleniyor (Fedora ${FEDORA_VERSION:-?})"
echo "==> NVIDIA: ${NVIDIA_ENABLED:-0}"

for script in "${SCRIPT_DIR}"/[0-9][0-9]-*.sh; do
    name="$(basename "${script}")"

    # NVIDIA adimi sadece nvidia varyantinda calisir.
    if [[ "${name}" == 40-nvidia.sh && "${NVIDIA_ENABLED:-0}" != "1" ]]; then
        echo ""
        echo "==> ${name} atlandi (bu varyantta NVIDIA yok)"
        continue
    fi

    echo ""
    echo "==> ${name}"
    bash "${script}"
done

echo ""
echo "==> Derleme adimlari tamam"
