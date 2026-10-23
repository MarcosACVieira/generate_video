# Dockerfile LEVE do fork — modelos NAO sao bakeados (vao pro network volume).
# Assim a imagem fica pequena e o GitHub Actions consegue buildar (runner tem ~50GB).
#
# A lentidao de leitura do volume e' tratada em RUNTIME, nao no build: o
# warm_local_models.sh copia os modelos de uso constante pro disco local do worker
# no arranque. Ver o cabecalho daquele script pros numeros medidos.
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

# O warm_local_models.sh e' um WRAPPER: copia os modelos pro disco local e so' depois
# faz exec no /entrypoint.sh deste repo (que sobe o ComfyUI e depois o handler).
# O entrypoint original segue INTACTO — o wrapper so' entra na frente dele.
#
# O `sed` tira CR de linha: estes arquivos sao editados no Windows, e um unico \r no
# shebang faz o kernel procurar um interpretador chamado "bash\r" e o container morre
# no arranque com "bad interpreter". O .gitattributes ja' forca LF, mas isso aqui
# protege contra checkout feito com outra config. Barato de prevenir, chato de achar.
RUN sed -i 's/\r$//' /warm_local_models.sh \
    && chmod +x /entrypoint.sh /warm_local_models.sh

CMD ["/warm_local_models.sh"]
