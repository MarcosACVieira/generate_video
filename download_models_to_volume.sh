#!/bin/bash
# Baixa os ~40GB de modelo do WAN 2.2 pro NETWORK VOLUME. Rode UMA VEZ, num POD
# que tenha o volume anexado. Num pod o volume normalmente monta em /workspace.
# (No serverless o MESMO volume monta em /runpod-volume — por isso o extra_model_paths
#  aponta pra /runpod-volume/wan_models, e aqui a gente grava em $VOL/wan_models.)
# (sem `set -e`: se um arquivo falhar, segue os outros; rode de novo pra retomar.)

# Ajuste se o seu volume montar em outro lugar no pod:
VOL="${VOL:-/workspace}"
BASE="$VOL/wan_models"

echo "Gravando em: $BASE"
mkdir -p "$BASE/diffusion_models" "$BASE/text_encoders" "$BASE/clip_vision" "$BASE/vae" "$BASE/loras"

# Acelera download do HuggingFace
pip install -U "huggingface_hub[hf_transfer]" >/dev/null 2>&1 || true
export HF_HUB_ENABLE_HF_TRANSFER=1

dl () { # dl <url> <destino>
  if [ -f "$2" ] && [ "$(stat -c%s "$2" 2>/dev/null || echo 0)" -gt 1000000 ]; then
    echo "JA EXISTE (pulando): $2"
  else
    echo "Baixando: $2"
    wget -c --tries=0 --retry-connrefused --waitretry=15 --timeout=120 --progress=dot:giga "$1" -O "$2"
  fi
}

# Modelos base High/Low (fp8 scaled, ~14GB cada)
dl "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors" "$BASE/diffusion_models/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors"
dl "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/I2V/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors"  "$BASE/diffusion_models/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors"

# LoRAs Lightning 4-step (aceleracao — o que faz poucos steps funcionarem)
dl "https://huggingface.co/lightx2v/Wan2.2-Lightning/resolve/main/Wan2.2-I2V-A14B-4steps-lora-rank64-Seko-V1/high_noise_model.safetensors" "$BASE/loras/high_noise_model.safetensors"
dl "https://huggingface.co/lightx2v/Wan2.2-Lightning/resolve/main/Wan2.2-I2V-A14B-4steps-lora-rank64-Seko-V1/low_noise_model.safetensors"  "$BASE/loras/low_noise_model.safetensors"

# Suporte: CLIP vision, text encoder umt5, VAE
dl "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" "$BASE/clip_vision/clip_vision_h.safetensors"
dl "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-fp8_e4m3fn.safetensors" "$BASE/text_encoders/umt5-xxl-enc-fp8_e4m3fn.safetensors"
dl "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors"    "$BASE/vae/Wan2_1_VAE_bf16.safetensors"

echo ""
echo "=== PRONTO. Conteudo do volume: ==="
ls -lhR "$BASE"
