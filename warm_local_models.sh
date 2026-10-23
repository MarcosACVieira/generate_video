#!/usr/bin/env bash
# ============================================================================
# Copia os modelos de uso constante do NETWORK VOLUME pro DISCO LOCAL do worker,
# uma vez por worker, antes de subir o ComfyUI. Depois disso toda releitura de
# modelo sai do disco local em vez da rede.
#
# POR QUE (numeros medidos, nao estimativa):
#   - O volume e' MooseFS (mfs#euro-2.runpod.net:9421). Leitura corrida: ~670 MB/s
#     (medido com `dd bs=16M`: 15GB em 21-24s).
#   - Mas o ComfyUI carrega TENSOR A TENSOR (1095 por expert), e nesse padrao so'
#     aproveita ~340 MB/s — 15GB levam ~44s no log do worker. Metade do tempo e'
#     latencia de ida e volta na rede, nao transferencia.
#   - O worker tem 46GB de RAM pra ~40GB de modelo. Quando a RAM aperta, o ComfyUI
#     descarta os pesos e RELE no meio da geracao. Medimos a MESMA seed no MESMO
#     worker oscilando entre 40s e 160s por causa disso.
#   - Do disco local a latencia por tensor praticamente some. A releitura deixa de
#     custar ~44s e passa a custar ~27s ou menos.
#
# O QUE ISSO NAO RESOLVE: a RAM continua apertada e o despejo continua acontecendo.
# Isso aqui barateia a consequencia, nao elimina a causa. A causa so' sai com mais
# RAM (GPU de 48GB) ou modelo menor.
#
# FALHA E' NAO-FATAL DE PROPOSITO: o extra_model_paths.yaml lista o volume como
# segunda fonte. Se a copia nao couber no disco, o worker sobe e funciona — so'
# mais lento. Melhor degradar do que nao subir.
#
# REQUISITO: container disk do endpoint com folga pros ~39GB (ver README_BUILD.md).
# ============================================================================
set -u

SRC="${MODELS_SRC:-/runpod-volume/wan_models}"
DST="${MODELS_DST:-/models_local}"
ORIG_ENTRYPOINT="${ORIG_ENTRYPOINT:-/entrypoint.sh}"

log() { echo "[warm-models] $*"; }

if [ ! -d "$SRC" ]; then
  log "AVISO: $SRC nao existe. Seguindo sem copia local (ComfyUI le' do volume)."
  exec "$ORIG_ENTRYPOINT"
fi

log "Disco local antes da copia:"
df -h / | tail -1

# Ordem = prioridade. Os experts primeiro: sao os maiores (15GB cada) e os que mais
# sofrem com o despejo de cache. Se o disco acabar no meio, o que ja' copiou vale —
# o resto continua vindo do volume.
#
# As 17 LoRAs de teste (lora_high_1..17 / lora_low_1..17) NAO entram aqui: trocam
# com frequencia e sao ~12GB. Ficam no volume. Ja' as Lightning (high/low_noise_model)
# entram, porque sao usadas em TODA geracao.
FILES="
diffusion_models/Wan2_2-I2V-A14B-HIGH_fp8_e4m3fn_scaled_KJ.safetensors
diffusion_models/Wan2_2-I2V-A14B-LOW_fp8_e4m3fn_scaled_KJ.safetensors
text_encoders/umt5-xxl-enc-fp8_e4m3fn.safetensors
clip_vision/clip_vision_h.safetensors
vae/Wan2_1_VAE_bf16.safetensors
loras/high_noise_model.safetensors
loras/low_noise_model.safetensors
"

copied=0; skipped=0; failed=0
t0=$(date +%s)

for rel in $FILES; do
  src="$SRC/$rel"
  dst="$DST/$rel"

  if [ ! -f "$src" ]; then
    log "AVISO: nao achei $src — pulando."
    failed=$((failed + 1))
    continue
  fi

  src_size=$(stat -c%s "$src" 2>/dev/null || echo 0)

  # Ja' copiado num arranque anterior deste mesmo worker? Compara tamanho e pula.
  if [ -f "$dst" ] && [ "$(stat -c%s "$dst" 2>/dev/null || echo 0)" = "$src_size" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  mkdir -p "$(dirname "$dst")"

  # .tmp + mv = troca atomica. Uma copia interrompida (disco cheio) nunca aparece
  # com o nome final — senao o ComfyUI carregaria um safetensors truncado, que e'
  # pior que nao ter copia nenhuma (falharia a geracao em vez de so' ficar lento).
  if cp "$src" "$dst.tmp" 2>/dev/null \
     && [ "$(stat -c%s "$dst.tmp" 2>/dev/null || echo 0)" = "$src_size" ]; then
    mv "$dst.tmp" "$dst"
    copied=$((copied + 1))
    log "OK: $rel"
  else
    rm -f "$dst.tmp"
    failed=$((failed + 1))
    log "FALHOU: $rel (provavelmente sem espaco) — esse vai continuar vindo do volume."
  fi
done

log "Resumo: copiados=$copied ja-existiam=$skipped falharam=$failed em $(($(date +%s) - t0))s"
log "Disco local depois da copia:"
df -h / | tail -1

if [ "$failed" -gt 0 ]; then
  log "ATENCAO: $failed arquivo(s) sem copia local. Geracoes vao ficar mais lentas."
  log "Se for falta de espaco, aumente o container disk do endpoint."
fi

exec "$ORIG_ENTRYPOINT"
