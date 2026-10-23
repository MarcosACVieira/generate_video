# Fork worker — WAN 2.2 Native (High/Low + CLIP vision)

Arquivos pra o fork `MarcosACVieira/generate_video` (worker RunPod serverless).
Imagem LEVE: modelos vivem no network volume, mas são copiados pro **disco local
do worker no arranque** — ver "Cópia local no boot" abaixo.

## Arquivos

| Arquivo | Onde vai no fork | O que é |
|---|---|---|
| `Dockerfile` | raiz (substitui) | imagem leve: ComfyUI + nós + RIFE. Sem os 40GB de modelo. |
| `handler.py` | raiz (substitui) | Plano A: aceita `workflow` completo do app + materializa imagens em /ComfyUI/input. |
| `warm_local_models.sh` | raiz (novo) | wrapper de arranque: copia modelos do volume pro disco local, depois chama o entrypoint original. |
| `extra_model_paths.yaml` | raiz (substitui) | `/models_local/` (cópia) primeiro, volume como fallback |
| `.github/workflows/build.yml` | `.github/workflows/` | GitHub Actions → builda e publica em `ghcr.io/marcosacvieira/generate_video:latest` |
| `download_models_to_volume.sh` | raiz (opcional) | baixa os ~37GB de modelo pro volume (rodar 1x num pod) |
| `Dockerfile.rife_snippet` | — | referência (já absorvido no Dockerfile) |

## O que este build adiciona vs o repo original

1. **Modelos fora da imagem** (no volume) → imagem leve, GitHub Actions consegue buildar.
2. **Cópia pro disco local no boot** (`warm_local_models.sh`) → barateia a releitura
   de modelo que o ComfyUI faz quando a RAM aperta. Ver seção própria abaixo.
3. **RIFE** (Frame-Interpolation) — não vem no repo. Non-fatal no build.
4. **SageAttention recompilado** p/ Ampere(8.6)+Ada(8.9)+Hopper(9.0)+Blackwell(12.0) —
   a base só trazia Sage p/ Blackwell (crashava em L4/4090/3090/A5000). Non-fatal.

## Cópia local no boot (`warm_local_models.sh`)

### O problema

O worker (RTX 4090) tem **46GB de RAM pra ~40GB de modelo**. Quando a RAM aperta, o
ComfyUI descarta os pesos e relê **no meio da geração**. Medimos a mesma seed, no
mesmo worker, oscilando entre **40s e 160s** por causa disso.

### Números medidos

| | Velocidade |
|---|---|
| Volume MooseFS, leitura corrida (`dd bs=16M`) | ~670 MB/s |
| Volume MooseFS, como o ComfyUI lê (tensor a tensor) | ~340 MB/s |

O ComfyUI aproveita só metade da banda: ele faz 1095 leituras separadas por expert,
e cada uma paga latência de ida e volta na rede. Por isso 15GB levam ~44s em vez
dos ~22s que a banda permitiria.

### O que a cópia faz

No arranque, copia os modelos de uso constante (~39GB) pro disco local. A latência
por tensor praticamente some, e a releitura cai de ~44s pra ~27s por modelo.

**Importante:** isso **não resolve** a pressão de RAM — o despejo continua. Só
barateia a consequência. A cura seria mais RAM (GPU de 48GB) ou modelo menor.

### Requisito

**Container disk do endpoint com folga pros ~39GB.** Se não couber, a cópia falha
nos arquivos que sobraram e o ComfyUI lê esses do volume (mais lento, mas funciona).
O log do arranque diz exatamente o que copiou e o que falhou.

## Como buildar

1. Commitar estes arquivos no fork (pelo navegador — o terminal do pod trunca paste grande).
2. GitHub Actions builda sozinho no push → publica no GHCR.
3. Tornar o pacote GHCR **público** (perfil → Packages → generate_video → settings → visibility).
4. No endpoint RunPod: **Deploy from Docker image** → `ghcr.io/marcosacvieira/generate_video:latest`,
   anexar o network volume, GPU 24GB+, idle timeout baixo, exec timeout 600s,
   **container disk ≥ 45GB**.

## Onde cada modelo vive

Tudo no volume: `/workspace/wan_models/` (pod) = `/runpod-volume/wan_models/` (serverless).

**Copiados pro disco local no arranque** (`/models_local/`, ~39GB):
- `diffusion_models/` → High + Low A14B fp8 (15GB cada)
- `text_encoders/` → umt5-xxl-enc-fp8
- `clip_vision/` → clip_vision_h
- `vae/` → Wan2_1_VAE
- `loras/` → high_noise_model + low_noise_model (Lightning 4-step — usadas em toda geração)

**Ficam só no volume:**
- `loras/` → `lora_high_1..17` + `lora_low_1..17` (17 pares de teste, ~12GB, trocam com frequência)

Pra incluir ou tirar arquivo da cópia, editar a lista `FILES` no `warm_local_models.sh`.

## Ainda NÃO implementado (próximos)

- **Handoff lossless / flf2v** — precisa patch no `handler.py` (devolver PNG do último frame,
  hoje só devolve `gifs`) + nós no workflow.
- **Block swap** — nó `WanVideoEnhancedBlockSwap` (pacote eddy). Só se precisar de VRAM.
- **torch.compile** — node do WanVideoWrapper (~1.2–1.5×, custo de cold start). É via workflow, não build.
