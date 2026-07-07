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

# NAO recompilar/desinstalar o SageAttention aqui. A base ja traz o pacote, e o ComfyUI
# sobe com `--use-sage-attention` — se o pacote sumir, o ComfyUI CRASHA no boot (loop de
# restart). O Sage da base e' compilado so pra Blackwell; em GPU nao-Blackwell (L4/4090/
# 3090/A5000) deixe o toggle Sage OFF (sdpa gera igual). Cobrir Ada exige recompilar o
# sageattention de fonte num passo separado e VERIFICADO — fica pra depois, se necessario.

# --- NOTA: os RUN wget de modelo do repo original foram REMOVIDOS de proposito. ---
# Os modelos (High, Low, umt5, clip_vision, VAE, LoRAs Lightning) agora vivem no
# network volume, mapeado pelo extra_model_paths.yaml abaixo.

COPY . .
COPY extra_model_paths.yaml /ComfyUI/extra_model_paths.yaml
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
