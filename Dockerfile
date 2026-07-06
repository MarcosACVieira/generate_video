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

# RIFE (interpolacao de frames) — adicao nossa, nao vem no repo. Nao-fatal.
RUN set +e; cd /ComfyUI/custom_nodes; \
    ( git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation \
      && cd ComfyUI-Frame-Interpolation \
      && pip install -r requirements-no-cupy.txt \
      && sed -i 's|ckpts_path:.*|ckpts_path: "/ComfyUI/models/frame_interpolation"|' config.yaml \
      && mkdir -p /ComfyUI/models/frame_interpolation/rife \
      && python -c "import urllib.request; urllib.request.urlretrieve('https://github.com/styler00dollar/VSGAN-tensorrt-docker/releases/download/models/rife47.pth','/ComfyUI/models/frame_interpolation/rife/rife47.pth')" \
    ) || echo "WARN: Frame-Interpolation/RIFE falhou — toggle RIFE indisponivel."; \
    set -e

# --- NOTA: os RUN wget de modelo do repo original foram REMOVIDOS de proposito. ---
# Os modelos (High, Low, umt5, clip_vision, VAE, LoRAs Lightning) agora vivem no
# network volume, mapeado pelo extra_model_paths.yaml abaixo.

COPY . .
COPY extra_model_paths.yaml /ComfyUI/extra_model_paths.yaml
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
