# Dockerfile LEVE do fork — modelos NAO sao mais bakeados (vao pro network volume).
# Assim a imagem fica pequena e o GitHub Actions consegue buildar (runner tem ~50GB).
# Os ~40GB de modelo sao baixados 1x pro volume via download_models_to_volume.sh.
FROM wlsdml1114/engui_genai-base_blackwell:1.1 as runtime

RUN pip install -U "huggingface_hub[hf_transfer]"
RUN pip install runpod websocket-client

WORKDIR /

RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd /ComfyUI && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/city96/ComfyUI-GGUF && \
    cd ComfyUI-GGUF && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-KJNodes && \
    cd ComfyUI-KJNodes && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    cd ComfyUI-VideoHelperSuite && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/orssorbit/ComfyUI-wanBlockswap

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper && \
    cd ComfyUI-WanVideoWrapper && \
    pip install -r requirements.txt

# RIFE via GACLove/ComfyUI-VFI (no `RIFEInterpolation`, o mesmo do workflow de referencia).
# Usa flownet.pkl, que BAIXA SOZINHO no 1o uso (o worker serverless tem internet) — por isso
# o 1o job com RIFE demora um pouco mais. Non-fatal: se falhar, o toggle RIFE fica off.
RUN set +e; cd /ComfyUI/custom_nodes; \
    ( git clone https://github.com/GACLove/ComfyUI-VFI.git \
      && cd ComfyUI-VFI && pip install -r requirements.txt ) \
    || echo "WARN: ComfyUI-VFI (RIFE) falhou — toggle RIFE indisponivel."; \
    set -e

# MMAudio (Kijai) — gera AUDIO pro video. Aqui so instala o PACK (fica pronto). Os modelos
# (models/mmaudio, ~GB) e a fiacao no app ficam pra um passo seguinte — sem eles o pack fica
# ocioso, mas nao atrapalha. Non-fatal.
RUN set +e; cd /ComfyUI/custom_nodes; \
    ( git clone https://github.com/kijai/ComfyUI-MMAudio.git \
      && cd ComfyUI-MMAudio && pip install -r requirements.txt ) \
    || echo "WARN: ComfyUI-MMAudio falhou."; \
    set -e

# SageAttention recompilado pra cobrir Ampere(8.6)+Ada(8.9)+Hopper(9.0)+Blackwell(12.0).
# A imagem base traz o Sage compilado SO pra Blackwell (sm_120) -> em L4/4090/3090/A5000
# crasha com "no kernel image is available for execution on the device". Recompilando de
# fonte com a lista de arcos abaixo, o Sage passa a funcionar em TODAS as suas GPUs (~1.4x).
# Non-fatal: se o build de fonte falhar, mantem o Sage da base (segue so em Blackwell) e a
# imagem builda mesmo assim — nesse caso, use Sage OFF nas GPUs nao-Blackwell.
RUN set +e; pip uninstall -y sageattention 2>/dev/null; \
    TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0;12.0" pip install --no-cache-dir git+https://github.com/thu-ml/SageAttention.git \
    || echo "WARN: recompilacao do SageAttention falhou — Sage segue so em Blackwell."; \
    set -e

# --- NOTA: os RUN wget de modelo do repo original foram REMOVIDOS de proposito. ---
# Os modelos (High, Low, umt5, clip_vision, VAE, LoRAs Lightning) agora vivem no
# network volume, mapeado pelo extra_model_paths.yaml abaixo.

COPY . .
COPY extra_model_paths.yaml /ComfyUI/extra_model_paths.yaml
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
